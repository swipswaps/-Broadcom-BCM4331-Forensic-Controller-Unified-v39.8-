# 🛰️ Broadcom BCM4331 Forensic Controller (Unified v39.8)

**Deterministic, self-healing network recovery and forensic telemetry suite.**

## 📜 Forensic Evolution: How We Got Here

This project is a production-grade response to the "recalcitrance" of BCM4331 hardware. It implements a multi-layered defense-in-depth strategy for network stability, evolved through rigorous iterative hardening.

### 1. The "Reload Storm" (v39.7)
Early versions suffered from an infinite browser reload loop. Vite's default file watcher detected every SQLite write or JSONL append as a source change.

### 2. The "Sudo Wall"
Forensic commands were historically blocked by interactive password prompts.

### 3. The "Unchecked Networking" Failure
Standard recovery scripts assumed global networking was enabled. If a user unchecked "Enable Networking" in the GNOME applet, recovery would fail silently.

### 4. The "ANSI Stagger" & Terminal Corruption
Hand-rolled ASCII dashboards suffered from staggered rendering and interleaved stdout corruption.

### 5. The "SSH Unbound Variable" Conflict
Scripts would crash in environments with `set -u` (nounset) enabled.

### 6. "Source-Safe" Engineering
Sourcing scripts containing `set -e` would terminate the user's entire interactive terminal session.

---

## 🛠️ What’s New in v39.8 (April 2026)

- **Ultra-fast recovery**: `press N` (terminal) and **Nuclear Recovery** (web button) now use the proven v38 `.bak` logic that succeeds in seconds.
- **Applet compliance**: Fixed “NetworkManager is not running” error with `systemctl reset-failed` + safe restart.
- **Instant detection**: Autonomous daemon uses real-time `nmcli monitor` (D-Bus) + 3-second fallback poll.
- **≤3-second guarantee** on “Enable Networking” uncheck or any connectivity loss.

### Test Recovery
- Terminal dashboard → press **N**
- Web dashboard (`http://localhost:3000`) → click **NUCLEAR RECOVERY**
- Left-click NetworkManager applet in taskbar → should now show normal settings

---

## 🛠️ Component Breakdown

### 📡 Autonomous Daemon (`network_autonomous_daemon.sh`)
- Real-time `nmcli monitor` for instant applet / connectivity events
- 3-second fallback poll
- Triggers full Nuclear Recovery in ≤3 seconds

### 🛡️ Forensic Engine (`fix-wifi.sh`)
- Proven v38 logic with milestones and RECOVERY_SUCCESS
- Rate-limit safe NetworkManager restart
- 3-second mutex
- Firmware injection, PCI unbind, driver strategy, power-save disable

### 🖥️ Terminal Dashboard (`dashboard.ts`)
- Blessed-Contrib high-performance ASCII grid
- Live verbatim log tail
- Press **N** for instant recovery

### 🌐 Web Dashboard (`App.tsx`)
- Nuclear Recovery button
- Real-time telemetry and balancer
- Cold Start button

---

## ✅ Request Compliance Explanation

This project adheres to the following core principles:

1. **Verbatim Transparency**: Every command run by the system is logged with its raw output and exit code.
2. **Zero-State Resilience**: The system assumes it starts in the worst possible state.
3. **Self-Healing**: The code detects its own failures and resolves them without user intervention.
4. **Auditability**: Every action leaves a trace in `verbatim_handshake.log` or `config_db.jsonl`.

### Cold-Start Recovery Sequence
```bash
npm run cold-start

Compliance Auditbash
chmod +x compliance_check.sh
./compliance_check.sh

License: MIT | Compliance Certified: April 2026 by swipswaps

