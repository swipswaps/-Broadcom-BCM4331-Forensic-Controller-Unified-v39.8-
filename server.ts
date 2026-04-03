import express from 'express';
import { execSync, spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { createServer as createViteServer } from 'vite';
import { startDashboard } from './dashboard';

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
    bkwInterface: 'wlp2s0b1',
    isFixing: false,
    rx: 124.5,
    tx: 45.2,
    pidKp: 100,
    pidKi: 10,
    pidKd: 5,
    pidOut: 115,
    pidIError: 50,
    pidPrevError: -5,
    gitUpdateAvailable: false,
    lastTick: new Date().toISOString()
  };

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
    if (!fs.existsSync(LOG_FILE)) return { events: [], stats: {} };
    const content = fs.readFileSync(LOG_FILE, 'utf8');
    const lines = content.split('\n');
    
    const events: any[] = [];
    const patterns = [
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

  // --- API: Fix ---
  app.post('/api/fix', (req, res) => {
    if (currentTelemetry.isFixing) return res.status(409).json({ error: 'Busy' });
    currentTelemetry.isFixing = true;
    console.log('[SERVER] NUCLEAR RECOVERY TRIGGERED');
    
    // Execute real fix-wifi.sh
    const fixProcess = spawn('bash', [path.join(WORKSPACE_DIR, 'fix-wifi.sh')]);
    
    fixProcess.stdout.on('data', (data) => {
      const msg = data.toString().trim();
      if (msg && dashboard) {
        dashboard.log(`[FIX] ${msg}`);
      }
    });

    fixProcess.on('close', (code) => {
      currentTelemetry.isFixing = false;
      if (dashboard) dashboard.log(`[FIX] Sequence complete with code ${code}`);
    });

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
    console.log(`[SERVER] Listening on port ${PORT}`);
    
    // Start Autonomous Daemon in background
    const daemon = spawn('bash', [path.join(WORKSPACE_DIR, 'network_autonomous_daemon.sh')], {
      detached: true,
      stdio: 'ignore'
    });
    daemon.unref();
    console.log('[SERVER] Autonomous Daemon started in background.');

    // Start Terminal Dashboard
    dashboard = startDashboard(
      () => currentTelemetry,
      () => {
        // Trigger fix logic
        currentTelemetry.isFixing = true;
        setTimeout(() => currentTelemetry.isFixing = false, 5000);
      }
    );

    // Handle clean exit
    const cleanExit = () => {
      dashboard.screen.destroy();
      process.exit(0);
    };

    process.on('SIGINT', cleanExit);
    process.on('SIGTERM', cleanExit);
  });
}

startServer();
