import blessed from 'blessed';
import contrib from 'blessed-contrib';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

export function startDashboard(getTelemetry: () => any, triggerFix: () => void) {
  const WORKSPACE_DIR = process.env.PROJECT_ROOT || process.cwd();
  const LOG_FILE = path.join(WORKSPACE_DIR, 'verbatim_handshake.log');
  
  const logToFile = (msg: string) => {
    const timestamp = new Date().toISOString();
    fs.appendFileSync(LOG_FILE, `[${timestamp}] [DASH] ${msg}\n`);
  };

  logToFile('Initializing dashboard...');

  let screen;
  try {
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
    throw e;
  }

  const grid = new contrib.grid({ rows: 12, cols: 12, screen: screen });

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

  // --- Row 4-5: Health & PID (3-4) ---
  const healthGauges = grid.set(4, 0, 2, 4, contrib.gaugeList, {
    label: ' 🩺 Interface Weights ',
    gaugeHeight: 2,
    gaugeSpacing: 1,
    gauges: [] // Fix: Initialize with empty array to prevent TypeError in blessed-contrib
  });

  const pidBars = grid.set(4, 4, 2, 4, contrib.bar, {
    label: ' 🎛️ Interface Throughput (KB/s) ',
    barWidth: 10,
    barSpacing: 4,
    xOffset: 0,
    maxHeight: 500
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
  let signalData = { title: 'Signal', x: Array(30).fill(''), y: Array(30).fill(-100) };
  let rxData = { title: 'RX', x: Array(30).fill(''), y: Array(30).fill(0), style: { line: 'cyan' } };
  let txData = { title: 'TX', x: Array(30).fill(''), y: Array(30).fill(0), style: { line: 'magenta' } };

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
    triggerFix();
  });

  nuclearBtn.on('click', () => {
    logToFile('Handshake requested via click on Nuclear Recovery');
    triggerFix();
  });

  // Focus cycling
  const focusable = [forensicLog, telemetryTable];
  let focusIdx = 0;
  screen.key(['tab'], () => {
    focusIdx = (focusIdx + 1) % focusable.length;
    focusable[focusIdx].focus();
  });

  function update() {
    const data = getTelemetry();
    if (!data) return;

    // Update Charts
    signalData.y.shift(); signalData.y.push(data.signal);
    rxData.y.shift(); rxData.y.push(data.rx || 0);
    txData.y.shift(); txData.y.push(data.tx || 0);
    
    signalLine.setData([signalData]);
    trafficLine.setData([rxData, txData]);

    // Update Gauges (Interface Weights)
    if (healthGauges.ctx && data.interfaces) {
      healthGauges.setGauges(data.interfaces.map((iface: any) => ({
        label: iface.name,
        stack: [{ percent: Math.round(iface.weight * 100), stroke: 'cyan' }]
      })));
    }

    // Update Bar Chart (Interface Throughput)
    if (data.interfaces) {
      pidBars.setData({
        titles: data.interfaces.map((iface: any) => iface.name),
        data: data.interfaces.map((iface: any) => Math.round(iface.rx + iface.tx))
      });
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
    if (data.interfaces) {
      telemetryTable.setData({
        headers: ['Interface', 'RX (KB/s)', 'TX (KB/s)', 'Weight (%)'],
        data: data.interfaces.map((iface: any) => [
          iface.name,
          (iface.rx || 0).toFixed(1),
          (iface.tx || 0).toFixed(1),
          ((iface.weight || 0) * 100).toFixed(1)
        ])
      });
    }

    screen.render();
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
