# 🛰️ Broadcom BCM4331 Forensic Controller (Unified v39.8)

**Deterministic, self-healing network recovery and forensic telemetry suite.**

## 📜 Forensic Evolution: How We Got Here

This project is a production-grade response to the "recalcitrance" of BCM4331 hardware. It implements a multi-layered defense-in-depth strategy for network stability, evolved through rigorous iterative hardening to overcome systemic failures common in standard AI-generated solutions.

### 1. The "Reload Storm" (v39.7)
*   **The Struggle:** Early versions suffered from an infinite browser reload loop. Vite's default file watcher detected every SQLite write or JSONL append as a source change, triggering a full HMR refresh every 2-10 seconds.
*   **The Fix:** Implementation of `watch.ignored` in `vite.config.ts` and moving state files outside the watched `src` directory.

### 2. The "Sudo Wall"
*   **The Struggle:** Forensic commands like `tcpdump`, `modprobe`, and `nmcli` were historically blocked by interactive password prompts, causing automated recovery scripts to hang indefinitely.
*   **The Fix:** A hardened `/etc/sudoers.d/broadcom-control` drop-in (generated via `setup-system.sh`) that grants `NOPASSWD` for the exact binary paths used in the forensic audit.

### 3. The "Unchecked Networking" Failure
*   **The Struggle:** Standard recovery scripts assumed global networking was enabled. If a user manually unchecked "Enable Networking" in the GNOME applet, `nmcli device connect` would fail silently with `Network is unreachable`.
*   **The Fix:** The recovery logic now explicitly forces `nmcli networking on` during the hardware handshake phase.

### 4. The "ANSI Stagger" & Terminal Corruption
*   **The Struggle:** Hand-rolled ASCII dashboards suffered from "staggered" rendering. Invisible ANSI escape codes (for colors) inflated string length calculations, causing `padEnd()` to misalign columns. Interleaved `stdout` from background processes further corrupted the screen buffer.
*   **The Fix:** Migration to `blessed-contrib` for atomic screen rendering. The dashboard now owns the terminal via `SmartCSR` mode, intercepting all writes to prevent frame corruption.

### 5. The "SSH Unbound Variable" Conflict
*   **The Struggle:** In environments with `set -u` (nounset) enabled globally, scripts would crash when referencing `$SSH_CONNECTION` if it wasn't defined.
*   **The Fix:** Implementation of safe variable expansion (`${VAR:-}`) and explicit environment neutralization (`: "${SSH_CONNECTION:=}"`) to ensure portability across hardened shells.

### 6. "Source-Safe" Engineering
*   **The Struggle:** Sourcing scripts containing `set -e` would terminate the user's entire interactive terminal session upon the first minor command failure.
*   **The Fix:** A critical architectural shift using `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guards. This ensures strict mode applies only during direct execution, while maintaining shell stability during interactive sourcing.

---

## 🛠️ Component Breakdown

### 📡 Autonomous Daemon (`network_autonomous_daemon.sh`)
- **Self-Healing**: Monitors DNS and Git state in a 15s loop.
- **Auto-Update**: Detects remote changes and performs a safe `git pull --rebase`.
- **Forensic Snapshots**: Automatically records system state into the JSONL DB.

### 🗄️ Forensic DB (`hardware_software_db.sh`)
- **Append-Only**: Preserves a full audit trail of environment changes.
- **Queryable**: Built-in functions for filtering by type or retrieving the latest state.
- **Zero-Risk**: Safe for `source` or `bash` execution.

### 🖥️ Terminal Dashboard (`dashboard.ts`)
- **Blessed-Contrib**: High-performance ASCII grid layout.
- **Nuclear Button**: Physical handshake trigger via `[N]` key or click.
- **Live Charts**: Real-time signal strength and throughput visualization.

### 🌐 Web Dashboard (`App.tsx`)
- **High-Fidelity**: React + Tailwind + Framer Motion UI.
- **Forensic Audit**: Structured parsing of `verbatim_handshake.log`.
- **PID Tuning**: Real-time adjustment of recovery response parameters.

---

## ✅ Request Compliance Explanation

This project adheres to the following core principles:

1.  **Verbatim Transparency**: Every command run by the system is logged with its raw output and exit code. No hidden failures.
2.  **Zero-State Resilience**: The system assumes it starts in the worst possible state. The `npm run setup` command builds the path to success from scratch.
3.  **Self-Healing**: The code detects its own failures (e.g., port conflicts) and resolves them (e.g., killing stale occupants) without user intervention.
4.  **Auditability**: Every action leaves a trace in `verbatim_handshake.log` or `config_db.jsonl`.

### Cold-Start Recovery Sequence
```bash
# 1. Install dependencies
npm install

# 2. System Integration
npm run setup

# 3. Launch Unified Dashboard
npm run dev
```

### Compliance Audit
Run the built-in audit suite to verify feature integrity:
```bash
chmod +x compliance_check.sh
./compliance_check.sh
```

---
**License:** MIT | **Compliance Certified:** April 2026 by swipswaps
