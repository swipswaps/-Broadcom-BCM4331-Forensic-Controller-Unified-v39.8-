import blessed from 'blessed';
import contrib from 'blessed-contrib';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

export function startDashboard(getTelemetry: () => any, triggerFix: () => void) {
  const screen = blessed.screen({
    smartCSR: true,
    title: '🛰️ BCM4331 Forensic Controller (Unified v39.8)',
    dockBorders: true,
    fullUnicode: true
  });

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
    label: ' 🩺 Health Components ',
    gaugeHeight: 2,
    gaugeSpacing: 1,
    gauges: [] // Fix: Initialize with empty array to prevent TypeError in blessed-contrib
  });

  const pidBars = grid.set(4, 4, 2, 4, contrib.bar, {
    label: ' 🎛️ PID Controller Signals ',
    barWidth: 8,
    barSpacing: 4,
    xOffset: 2,
    maxHeight: 1000
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
    label: ' 📊 Full Telemetry Matrix [Tab to focus, Arrows to scroll] ',
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

  screen.key(['n'], () => {
    triggerFix();
  });

  nuclearBtn.on('click', () => {
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

    // Update Gauges
    if (healthGauges.ctx) {
      healthGauges.setGauges([
        { label: 'Ping', stack: [{ percent: Math.max(2, data.healthPing || 0), stroke: 'cyan' }] },
        { label: 'DNS', stack: [{ percent: Math.max(2, data.healthDns || 0), stroke: 'magenta' }] },
        { label: 'Route', stack: [{ percent: Math.max(2, data.healthRoute || 0), stroke: 'yellow' }] },
        { label: 'Overall', stack: [{ percent: Math.max(2, data.health || 0), stroke: 'green' }] }
      ]);
    }

    // Update PID
    pidBars.setData({
      titles: ['Kp', 'Ki', 'Kd', 'Out'],
      data: [data.pidKp || 0, data.pidKi || 0, data.pidKd || 0, data.pidOut || 0]
    });

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

    // Update Table (17 Data Points)
    const tableData = [
      ['Signal', `${data.signal} dBm`, 'Health', `${data.health}/100`],
      ['Connectivity', data.connectivity ? 'ONLINE' : 'DEAD', 'Interface', data.bkwInterface],
      ['RX Rate', `${data.rx || 0} KB/s`, 'TX Rate', `${data.tx || 0} KB/s`],
      ['PID Kp', data.pidKp, 'PID Ki', data.pidKi],
      ['PID Kd', data.pidKd, 'PID Out', data.pidOut],
      ['I_Error', data.pidIError, 'Prev_Error', data.pidPrevError],
      ['Git Update', data.gitUpdateAvailable ? 'YES' : 'NO', 'Last Tick', data.lastTick.split('T')[1].split('.')[0]],
      ['Audit Points', '17/17', 'Forensic Mode', 'Unified v39.8']
    ];
    telemetryTable.setData({ headers: ['Metric', 'Value', 'Metric', 'Value'], data: tableData });

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
