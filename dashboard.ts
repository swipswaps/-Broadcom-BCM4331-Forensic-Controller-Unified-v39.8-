import blessed from 'blessed';
import contrib from 'blessed-contrib';
import fs from 'fs';
import path from 'path';

// Use dynamic import for fetch to avoid issues in some environments
const fetchTelemetry = async () => {
  try {
    const response = await fetch('http://localhost:3000/api/status');
    return await response.json();
  } catch (e) {
    return null;
  }
};

const triggerFixViaApi = async () => {
  try {
    await fetch('http://localhost:3000/api/fix', { method: 'POST' });
  } catch (e) {
    // Ignore
  }
};

export function startDashboard() {
  const WORKSPACE_DIR = process.env.PROJECT_ROOT || process.cwd();
  const LOG_FILE = path.join(WORKSPACE_DIR, 'verbatim_handshake.log');
  
  const logToFile = (msg: string) => {
    const timestamp = new Date().toISOString();
    fs.appendFileSync(LOG_FILE, `[${timestamp}] [DASH] ${msg}\n`);
  };

  logToFile('Initializing dashboard...');

  let screen: any;
  try {
    // Check if we have a TTY
    if (!process.stdout.isTTY) {
      logToFile('No TTY detected. Dashboard will run in headless mode (logging only).');
      setInterval(async () => {
        const data = await fetchTelemetry();
        if (data) {
          logToFile(`TELEMETRY: Health=${data.health}, RX=${(data.rx || 0).toFixed(2)}, TX=${(data.tx || 0).toFixed(2)}, Signal=${data.signal || -100}`);
        }
      }, 10000);
      return;
    }

    screen = blessed.screen({
      smartCSR: true,
      title: '🛰️ BCM4331 Forensic Controller (Unified v39.8)',
      dockBorders: true,
      fullUnicode: true,
      mouse: true
    });
    logToFile('Screen created successfully.');
  } catch (e: any) {
    logToFile(`CRITICAL: Failed to create blessed screen: ${e.message}`);
    return;
  }

  const grid = new (contrib as any).grid({ rows: 12, cols: 12, screen: screen });

  // --- Row 0-3: Charts (1-2) ---
  const signalLine = grid.set(0, 0, 4, 6, contrib.line, {
    style: { line: "yellow", text: "white", baseline: "black" },
    xLabelPadding: 3,
    xPadding: 5,
    label: ' 📡 Signal Strength (dBm) ',
    minY: -100,
    maxY: 0,
    showLegend: true
  });

  const trafficLine = grid.set(0, 6, 4, 6, contrib.line, {
    style: { line: "cyan", text: "white", baseline: "black" },
    xLabelPadding: 3,
    xPadding: 5,
    label: ' 🚀 Network Throughput (KB/s) ',
    showLegend: true
  });

  // --- Row 4-5: Health & Audit (3-4) ---
  const auditPointsBox = grid.set(4, 0, 2, 8, blessed.box, {
    label: ' 🛡️ Forensic Audit Status (18 Deterministic Points) ',
    content: 'Initializing audit points...',
    tags: true,
    style: {
      border: { fg: 'cyan' }
    }
  });

  const nuclearBtn = grid.set(4, 8, 2, 4, blessed.box, {
    label: ' ☢️ Nuclear Recovery ',
    content: '\n   [ PRESS N ]\n   TRIGGER HANDSHAKE',
    align: 'center',
    valign: 'middle',
    style: {
      bg: 'red',
      fg: 'white',
      bold: true,
      border: { fg: 'white' }
    }
  });

  // --- Row 6-8: Forensic Events (5) ---
  const forensicLog = grid.set(6, 0, 3, 12, contrib.log, {
    fg: "green",
    selectedFg: "green",
    label: ' 🕵️ Forensic Events (Audit Trail) ',
    interactive: true,
    scrollable: true,
    scrollbar: { ch: ' ', track: { bg: 'cyan' }, style: { inverse: true } }
  });

  // --- Row 9-11: Telemetry Table (6-17) ---
  const telemetryTable = grid.set(9, 0, 3, 12, contrib.table, {
    keys: true,
    fg: 'white',
    selectedFg: 'white',
    selectedBg: 'blue',
    interactive: true,
    label: ' 📊 Multi-Interface Load Matrix ',
    width: '100%',
    height: '100%',
    border: { type: "line", fg: "cyan" },
    columnSpacing: 2,
    columnWidth: [15, 12, 15, 12, 15, 12, 15, 12]
  });

  // --- State ---
  let signalData = { title: 'Signal', x: Array(30).fill(' '), y: Array(30).fill(-100) };
  let rxData = { title: 'RX', x: Array(30).fill(' '), y: Array(30).fill(0), style: { line: 'cyan' } };
  let txData = { title: 'TX', x: Array(30).fill(' '), y: Array(30).fill(0), style: { line: 'magenta' } };

  // --- Interaction ---
  screen.key(['q', 'C-c'], () => {
    screen.destroy();
    process.exit(0);
  });

  screen.on('keypress', (ch, key) => {
    if (key) {
      logToFile(`Key pressed: ${key.name} (full: ${JSON.stringify(key)})`);
    }
  });

  screen.key(['n'], () => {
    logToFile('Handshake requested via key [N]');
    if (forensicLog) forensicLog.log('[DASH] Handshake requested via key [N]');
    triggerFixViaApi();
  });

  nuclearBtn.on('click', () => {
    logToFile('Handshake requested via click on Nuclear Recovery');
    triggerFixViaApi();
  });

  // Focus cycling
  const focusable = [forensicLog, telemetryTable];
  let focusIdx = 0;
  screen.key(['tab'], () => {
    focusIdx = (focusIdx + 1) % focusable.length;
    focusable[focusIdx].focus();
  });

  const AUDIT_LABELS: Record<string, string> = {
    rfkill_soft: 'RF-SOFT',
    rfkill_hard: 'RF-HARD',
    pci_bus: 'PCI-BUS',
    driver_loaded: 'DRIVER',
    firmware_loaded: 'FIRMWARE',
    iface_created: 'IFACE',
    iface_up: 'UP',
    ip_assigned: 'IP',
    gw_reachable: 'GW',
    dns_resolved: 'DNS',
    signal_stable: 'SIGNAL',
    tx_power: 'TX-PWR',
    entropy_pool: 'ENTROPY',
    wpa_active: 'WPA',
    nm_active: 'NM',
    pid_stable: 'PID',
    mutex_lock: 'MUTEX',
    bkw_sync: 'BKW'
  };

  async function update() {
    try {
      const data = await fetchTelemetry();
      if (!data) return;

      // Update Charts
      if (data.signal !== undefined) {
        signalData.y.shift(); signalData.y.push(Number(data.signal) || -100);
      }
      rxData.y.shift(); rxData.y.push(Number(data.rx) || 0);
      txData.y.shift(); txData.y.push(Number(data.tx) || 0);
      
      signalLine.setData([signalData]);
      trafficLine.setData([rxData, txData]);

      // Update Audit Points
      if (data.auditPoints) {
        let auditContent = '';
        const points = Object.entries(data.auditPoints);
        for (let i = 0; i < points.length; i++) {
          const [key, val] = points[i];
          const label = AUDIT_LABELS[key] || key.toUpperCase();
          const color = val ? '{green-fg}' : '{red-fg}';
          auditContent += `${color}${label}{/}  `;
          if ((i + 1) % 6 === 0) auditContent += '\n';
        }
        auditPointsBox.setContent(auditContent);
      }

      // Update Nuclear Button
      if (data.isFixing) {
        nuclearBtn.style.bg = 'yellow';
        nuclearBtn.style.fg = 'black';
        nuclearBtn.setContent('\n   [ RECOVERY ]\n   IN PROGRESS...');
      } else {
        nuclearBtn.style.bg = 'red';
        nuclearBtn.style.fg = 'white';
        nuclearBtn.setContent('\n   [ PRESS N ]\n   TRIGGER HANDSHAKE');
      }

      // Update Table (Multi-Interface Load Matrix)
      if (data.interfaces && data.interfaces.length > 0) {
        telemetryTable.setData({
          headers: ['Interface', 'RX (KB/s)', 'TX (KB/s)', 'Weight (%)'],
          data: data.interfaces.map((iface: any) => [
            String(iface.name),
            (Number(iface.rx) || 0).toFixed(1),
            (Number(iface.tx) || 0).toFixed(1),
            ((Number(iface.weight) || 0) * 100).toFixed(1)
          ])
        });
      } else if (data.bkwInterface) {
        // Fallback if no interfaces array
        telemetryTable.setData({
          headers: ['Interface', 'RX (KB/s)', 'TX (KB/s)', 'Weight (%)'],
          data: [[String(data.bkwInterface), (Number(data.rx) || 0).toFixed(1), (Number(data.tx) || 0).toFixed(1), '100.0']]
        });
      }

      screen.render();
    } catch (e: any) {
      logToFile(`Update error: ${e.message}`);
    }
  }

  // Initial render
  screen.render();
  setInterval(update, 2000);

  // Expose log method
  return {
    log: (msg: string) => forensicLog.log(msg),
    screen
  };
}

// Start the dashboard
startDashboard();
