import express from 'express';
import { execSync, spawn, spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { createServer as createViteServer } from 'vite';

async function startServer() {
  const app = express();
  const PORT = 3000;
  const WORKSPACE_DIR = process.env.PROJECT_ROOT || process.cwd();
  const LOG_FILE = path.join(WORKSPACE_DIR, 'verbatim_handshake.log');
  const DB_FILE = path.join(WORKSPACE_DIR, 'config_db.jsonl');

  app.use(express.json());

  // --- Telemetry State ---
  let currentTelemetry = {
    signal: -45,
    health: 100,
    healthPing: 40,
    healthDns: 30,
    healthRoute: 30,
    connectivity: true,
    bkwInterface: 'eth1',
    isFixing: false,
    rx: 0,
    tx: 0,
    pidKp: 100,
    pidKi: 10,
    pidKd: 5,
    pidOut: 115,
    pidIError: 50,
    pidPrevError: -5,
    gitUpdateAvailable: false,
    lastTick: new Date().toISOString(),
    // Multi-interface load balancing state
    interfaces: [] as any[],
    isBenchmarking: false
  };

  // Initial interface discovery
  try {
    // Prioritize /proc/net/dev for throughput tracking
    const procNetDev = fs.readFileSync('/proc/net/dev', 'utf8');
    let ifaces = procNetDev.split('\n')
      .filter(line => line.includes(':'))
      .map(line => line.split(':')[0].trim())
      .filter(name => name !== 'lo');

    if (ifaces.length === 0) {
      console.log('[SERVER] /proc/net/dev returned no interfaces, falling back to nmcli');
      const nmcliOutput = execSync('nmcli -t -f DEVICE dev | grep -v "lo"', { encoding: 'utf8' });
      ifaces = nmcliOutput.split('\n').filter(Boolean);
    }

    currentTelemetry.interfaces = ifaces.map(name => ({
      name,
      rx: 0,
      tx: 0,
      weight: 1 / ifaces.length,
      health: 100
    }));
    if (ifaces.length > 0) currentTelemetry.bkwInterface = ifaces[0];
  } catch (e) {
    console.error('[SERVER] Failed to discover interfaces on startup:', e);
    currentTelemetry.interfaces = [{ name: 'eth1', rx: 0, tx: 0, weight: 1.0, health: 100 }];
    currentTelemetry.bkwInterface = 'eth1';
  }

  // --- PID Load Balancer Logic ---
  function updateLoadBalancing() {
    const targetThroughput = 500; // KB/s target for the "ideal" interface
    
    currentTelemetry.interfaces.forEach((iface, idx) => {
      const currentThroughput = iface.rx + iface.tx;
      const error = targetThroughput - currentThroughput;
      
      // Basic PID-like weight adjustment
      // Higher error (less throughput) means we want to increase weight
      // Lower error (more throughput) means we want to decrease weight
      const p = currentTelemetry.pidKp / 1000 * error;
      const i = currentTelemetry.pidKi / 1000 * (currentTelemetry.pidIError + error);
      const d = currentTelemetry.pidKd / 1000 * (error - currentTelemetry.pidPrevError);
      
      const adjustment = p + i + d;
      iface.weight = Math.max(0, Math.min(1, iface.weight + adjustment / 1000));
      
      // Update PID state for next tick
      currentTelemetry.pidIError += error;
      currentTelemetry.pidPrevError = error;
    });
    
    // Normalize weights
    const totalWeight = currentTelemetry.interfaces.reduce((sum, iface) => sum + iface.weight, 0);
    if (totalWeight > 0) {
      currentTelemetry.interfaces.forEach(iface => iface.weight /= totalWeight);
    }
  }

  // --- API: Benchmark ---
  const runBenchmark = () => {
    if (currentTelemetry.isBenchmarking) return;
    currentTelemetry.isBenchmarking = true;
    
    const benchProcess = spawn('bash', [path.join(WORKSPACE_DIR, 'network_sniff_bench.sh')]);
    let output = '';
    
    benchProcess.stdout.on('data', (data) => {
      output += data.toString();
    });

    benchProcess.on('close', (code) => {
      currentTelemetry.isBenchmarking = false;
      if (code === 0) {
        const parts = output.trim().split(',').filter(Boolean);
        let totalRx = 0;
        let totalTx = 0;
        
        const newInterfaces = parts.map(p => {
          const [name, rx, tx] = p.split(':');
          if (!name) return null;
          const rxVal = parseFloat(rx) || 0;
          const txVal = parseFloat(tx) || 0;
          totalRx += rxVal;
          totalTx += txVal;
          return {
            name,
            rx: rxVal,
            tx: txVal,
            weight: 0.5,
            health: 100
          };
        }).filter(Boolean) as any[];
        
        if (newInterfaces.length > 0) {
          currentTelemetry.interfaces = newInterfaces;
          currentTelemetry.rx = totalRx;
          currentTelemetry.tx = totalTx;
          updateLoadBalancing();
        }
        
        console.error(`[BENCH] Completed with ${newInterfaces.length} interfaces.`);
      } else {
        console.error(`[BENCH] Failed with code ${code}`);
      }
    });
  };

  app.post('/api/benchmark', (req, res) => {
    runBenchmark();
    res.json({ status: 'initiated' });
  });

  // Background tasks
  setInterval(() => {
    runBenchmark();
    // Also parse signal from logs periodically
    const forensics = parseForensics();
    const lastSignal = forensics.find((e: any) => e.type === 'TELEMETRY' && e.message.includes('Signal:'));
    if (lastSignal) {
      const signalMatch = lastSignal.message.match(/Signal: (.*?) dBm/);
      if (signalMatch) {
        currentTelemetry.signal = parseInt(signalMatch[1]) || -45;
      }
    }
  }, 30000);

  // --- API: PID Tune ---
  app.post('/api/pid/tune', (req, res) => {
    const { kp, ki, kd } = req.body;
    if (kp !== undefined) currentTelemetry.pidKp = kp;
    if (ki !== undefined) currentTelemetry.pidKi = ki;
    if (kd !== undefined) currentTelemetry.pidKd = kd;
    res.json({ status: 'updated', pid: { kp: currentTelemetry.pidKp, ki: currentTelemetry.pidKi, kd: currentTelemetry.pidKd } });
  });

  // --- Helper: Kill Port Occupant ---
  function killPortOccupant(port: number) {
    try {
      const pid = execSync(`lsof -t -i:${port}`, { encoding: 'utf8' }).trim();
      if (pid && parseInt(pid) !== process.pid) {
        process.kill(parseInt(pid), 'SIGTERM');
      }
    } catch (e) {}
  }

  // --- Forensic Log Parser ---
  function parseForensics() {
    if (!fs.existsSync(LOG_FILE)) return [];
    const content = fs.readFileSync(LOG_FILE, 'utf8');
    const lines = content.split('\n');
    
    const events: any[] = [];
    const patterns = [
      { type: 'TELEMETRY', regex: /Signal: (.*?) dBm on (.*)/, label: 'Signal Strength' },
      { type: 'MODULE', regex: /modprobe (\w+)/, label: 'Kernel Module' },
      { type: 'RFKILL', regex: /rfkill unblock (\w+)/, label: 'RFKill Event' },
      { type: 'NMCLI', regex: /nmcli (device|connection) (\w+)/, label: 'NetworkManager' },
      { type: 'HEALTH', regex: /Health degradation: (.*)/, label: 'Health Alert' },
      { type: 'PID', regex: /PID Signal: (.*)/, label: 'PID Controller' },
      { type: 'MUTEX', regex: /Mutex (acquired|released)/, label: 'Lock Event' },
      { type: 'BINARY', regex: /(\w+) not found/, label: 'Missing Binary' },
      { type: 'RECOVERY', regex: /Starting recovery sequence/, label: 'Recovery Start' }
    ];

    lines.forEach(line => {
      for (const p of patterns) {
        const match = line.match(p.regex);
        if (match) {
          events.push({
            timestamp: line.match(/\[(.*?)\]/)?.[1] || 'unknown',
            type: p.type,
            label: p.label,
            message: match[0],
            details: match[1] || ''
          });
        }
      }
    });

    return events.slice(-50).reverse();
  }

  // --- API: Status ---
  app.get('/api/status', (req, res) => {
    currentTelemetry.lastTick = new Date().toISOString();
    res.json(currentTelemetry);
  });

  // --- API: Forensics ---
  app.get('/api/forensics', (req, res) => {
    try {
      if (!fs.existsSync(LOG_FILE)) return res.json({ events: [], logTail: [], dbSnapshots: [] });
      const content = fs.readFileSync(LOG_FILE, 'utf8');
      const lines = content.split('\n');
      const events = parseForensics();
      const dbTail = fs.existsSync(DB_FILE)
        ? execSync(`tail -n 50 "${DB_FILE}"`, { encoding: 'utf8' })
        : '';

      res.json({
        events,
        logTail: lines.slice(-100),
        dbSnapshots: dbTail.split('\n').filter(Boolean).map(line => {
          try { return JSON.parse(line); } catch(e) { return null; }
        }).filter(Boolean)
      });
    } catch (error) {
      res.status(500).json({ error: 'Forensic failure' });
    }
  });

  let dashboard: any = null;

  app.get('/api/trigger-fix', (req, res) => {
    triggerRecovery();
    res.json({ status: 'triggered' });
  });

  // --- API: Fix ---
  const triggerRecovery = () => {
    console.error('[SERVER] triggerRecovery called');
    if (currentTelemetry.isFixing) {
      console.error('[SERVER] Recovery already in progress, ignoring.');
      return;
    }
    currentTelemetry.isFixing = true;
    console.error('[SERVER] NUCLEAR RECOVERY TRIGGERED');
    
    // Execute real fix-wifi.sh
    const fixProcess = spawn('bash', [path.join(WORKSPACE_DIR, 'fix-wifi.sh')]);
    
    fixProcess.stdout.on('data', (data) => {
      const msg = data.toString().trim();
      console.log(`[FIX STDOUT] ${msg}`);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [FIX STDOUT] ${msg}\n`);
    });

    fixProcess.stderr.on('data', (data) => {
      const msg = data.toString().trim();
      console.error(`[FIX STDERR] ${msg}`);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [FIX STDERR] ${msg}\n`);
    });

    fixProcess.on('close', (code) => {
      currentTelemetry.isFixing = false;
      console.error(`[SERVER] fix-wifi.sh closed with code ${code}`);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] fix-wifi.sh closed with code ${code}\n`);
    });

    fixProcess.on('error', (err) => {
      currentTelemetry.isFixing = false;
      console.error(`[SERVER] Failed to start fix-wifi.sh: ${err.message}`);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] Failed to start fix-wifi.sh: ${err.message}\n`);
    });
  };

  app.post('/api/fix', (req, res) => {
    if (currentTelemetry.isFixing) return res.status(409).json({ error: 'Busy' });
    triggerRecovery();
    res.json({ status: 'initiated' });
  });

  // --- Vite Middleware ---
  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  killPortOccupant(PORT);

  const server = app.listen(PORT, '0.0.0.0', () => {
    console.error(`[SERVER] Listening on port ${PORT}`);
    fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] UID: ${process.getuid()}, EUID: ${process.geteuid()}\n`);
    fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] PATH: ${process.env.PATH}\n`);
    
    // Run system integration
    try {
      console.error('[SERVER] Running system integration...');
      const setup = spawnSync('bash', [path.join(WORKSPACE_DIR, 'setup-system.sh')], {
        encoding: 'utf8'
      });
      if (setup.error) {
        const msg = `[SERVER] Setup failed: ${setup.error}`;
        console.error(msg);
        fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`);
      } else {
        const msg = `[SERVER] Setup complete. Output: ${setup.stdout}`;
        console.error(msg);
        fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] Setup complete.\n`);
        if (setup.stderr) {
          fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] Setup stderr: ${setup.stderr}\n`);
        }
      }
    } catch (err) {
      console.error('[SERVER] System integration error:', err);
    }

    // Start Autonomous Daemon in background
    const daemon = spawn('bash', [path.join(WORKSPACE_DIR, 'network_autonomous_daemon.sh')], {
      detached: true,
      stdio: 'pipe'
    });
    daemon.stdout.on('data', (data) => {
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [DAEMON-STDOUT] ${data}\n`);
    });
    daemon.stderr.on('data', (data) => {
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [DAEMON-STDERR] ${data}\n`);
    });
    daemon.unref();
    console.error('[SERVER] Autonomous Daemon started in background.');
    
    // Start Terminal Dashboard
    try {
      dashboard = spawn('tsx', [path.join(WORKSPACE_DIR, 'dashboard.ts')], {
        stdio: 'inherit',
        env: { ...process.env, PROJECT_ROOT: WORKSPACE_DIR }
      });
      console.error('[SERVER] Terminal Dashboard spawned.');
    } catch (e: any) {
      console.error('[SERVER] Failed to spawn dashboard:', e.message);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] Dashboard failed: ${e.message}\n`);
    }

    // Handle clean exit
    const cleanExit = () => {
      if (dashboard && dashboard.kill) {
        dashboard.kill();
      }
      process.exit(0);
    };

    process.on('SIGINT', cleanExit);
    process.on('SIGTERM', cleanExit);

    process.on('uncaughtException', (err) => {
      console.error('[SERVER] Uncaught Exception:', err);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] CRASH: ${err.message}\n`);
      cleanExit();
    });

    process.on('unhandledRejection', (reason, promise) => {
      console.error('[SERVER] Unhandled Rejection at:', promise, 'reason:', reason);
      fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] [SERVER] REJECTION: ${reason}\n`);
    });
  });
}

startServer();
