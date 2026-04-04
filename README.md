# 🛰️ Broadcom BCM4331 Forensic Controller (Unified v39.9)

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

### 7. The "Ethernet Mask" Failure (v39.8 → v39.9)
`system_is_healthy()` returned true when ethernet was connected, causing `fix-wifi.sh` to exit without
attempting Wi-Fi recovery. BCM4331 showed `WIFI-HW: missing` while ethernet kept the health check
passing. Wi-Fi was never attempted.

### 8. The "brcmsmac Intercept" (v39.9)
`brcmsmac` has module aliases that match BCM4331 PCI ID `[14e4:4331]` before `b43` in the kernel's
alias table. Every `modprobe b43` call silently loaded `brcmsmac` instead. Confirmed from dmesg:
29 consecutive lines of `brcmsmac: unknown parameter 'allhwsupport' ignored` — b43 never ran.
Fix: `/etc/modprobe.d/broadcom-bcm4331.conf` blacklists brcmsmac and brcmfmac permanently.

### 9. The "Initramfs Gap" (v39.9)
b43 firmware existed at `/usr/lib/firmware/b43` but was not in the initramfs. Boot-time b43 load
failed with `error -2 (ENOENT)` even though files were on disk. The firmware was installed after
the last `dracut` run and was never included in the boot image. Fix: `dracut --force` rebuilds the
initramfs with firmware; `/etc/dracut.conf.d/b43-firmware.conf` ensures it survives kernel updates.

### 10. The "bcma Refcount Underflow" (v39.9, session-induced)
Running `modprobe -r bcma` while b43 was loaded caused b43's reference count to go to -1.
Both `modprobe -r b43` and `rmmod -f b43` then failed with "Device or resource busy". Only a reboot
recovered the module state. Fix: `fix-wifi.sh` never removes bcma while b43 is loaded.

### 11. The "Dracut CWD" Corruption (v39.9)
Running `sudo dracut --force` from inside the project directory caused dracut to write the initramfs
as a file named `cmdline:` (46MB) in the current directory. `lsinitrd` subsequently read this file
and flooded stdout, which overwrote scripts deployed immediately after via `tee`. Multiple scripts
were corrupted including `fix-wifi.sh` and `compliance_check.sh`.
Fix: `setup-system.sh` always runs dracut with an absolute output path, never from the project directory.

### 12. The "Source-Text Compliance" Failure (v39.8 compliance_check.sh)
`compliance_check.sh` tested for literal strings in script source (e.g. `AUDIT POINT 17`). Any
refactoring caused false failures; real system gaps (missing blacklist, firmware not in initramfs)
went undetected. Fix: compliance now checks observable system state — files present, firmware in
initramfs, WIFI-HW enabled, database has recent snapshot.

---

## 🛠️ What's New in v39.9 (April 2026)

- **Wi-Fi-aware recovery**: `fix-wifi.sh` now checks Wi-Fi independently of ethernet state via
  `wifi_is_healthy()`. Recovery runs even when ethernet is fully connected.
- **brcmsmac blacklist**: `setup-system.sh` writes `/etc/modprobe.d/broadcom-bcm4331.conf`
  blacklisting brcmsmac and brcmfmac, ensuring b43 binds to BCM4331 without interception.
- **Initramfs firmware**: `setup-system.sh` writes `/etc/dracut.conf.d/b43-firmware.conf` and
  runs `dracut --force` so b43 firmware survives kernel updates and is present at boot.
- **Boot-time service**: `fix-wifi.service` installed to `/etc/systemd/system/` and enabled,
  providing a post-boot safety net if the initramfs load fails.
- **Telemetry database**: `fix-wifi.sh` writes all 18 deterministic audit points to
  `config_db.jsonl` on every run as `audit_snapshot` entries, before and after recovery.
- **State-based compliance**: `compliance_check.sh` checks system state not source text —
  blacklist present, firmware on disk, firmware in initramfs, service enabled, database populated.
- **Pre-commit gate**: `.git/hooks/pre-commit` runs `compliance_check.sh` before every commit.
  A failing compliance check blocks the commit, preventing silent feature removal.
- **Safe module reload**: `fix-wifi.sh` never removes `bcma` while b43 is loaded, preventing the
  refcount underflow that requires a reboot to recover.
- **Firmware fetch restored**: `prepare-bundle.sh` fetches b43 firmware via `dnf install
  b43-firmware` (RPMFusion) or `b43-fwcutter` + Broadcom driver download, then rebuilds initramfs.

### What Still Applies from v39.8
- Ultra-fast recovery: press **N** (terminal) or **NUCLEAR RECOVERY** (web) triggers fix-wifi.sh
- Applet compliance: `systemctl reset-failed` + restart clears NM rate-limit hit
- Autonomous daemon: `nmcli monitor` (D-Bus) + 3-second fallback poll
- ≤3-second reaction on "Enable Networking" uncheck or connectivity loss

### Test Recovery
- Terminal dashboard → press **N**
- Web dashboard (`http://localhost:3000`) → click **NUCLEAR RECOVERY**
- Left-click NetworkManager applet → shows normal Wi-Fi settings and connected networks
- Run `bash compliance_check.sh` → expect all PASS

---

## ⚠️ Known Issues (v39.9)

### Sudoers Bootstrap Catch-22
On a fresh clone, `setup-system.sh` needs sudo to write the sudoers file, but the sudoers file
is what grants passwordless sudo. **One-time manual fix required:**
```bash
sudo bash setup-system.sh
```
After this, all subsequent runs are passwordless and autonomous.

### dracut Must Not Run From Project Directory
Running `sudo dracut --force` from inside the project directory writes the initramfs as `cmdline:`
in the current directory. Always run `setup-system.sh` which handles the path correctly, or run
dracut from `/` or your home directory.

### wifi_is_healthy() Association Race
`fix-wifi.sh` may report `WIFI_RECOVERY_FAILED` when NetworkManager is still associating (DHCP
in progress). The interface is present and connecting — the report section will show the correct
state. This is a timing issue, not a recovery failure.

---

## 🛠️ Component Breakdown

### 📡 Autonomous Daemon (`network_autonomous_daemon.sh`)
- Real-time `nmcli monitor` for instant applet / connectivity events
- 3-second fallback poll
- Triggers full Nuclear Recovery in ≤3 seconds

### 🛡️ Forensic Engine (`fix-wifi.sh`)
- `wifi_is_healthy()` checks Wi-Fi independently of ethernet
- `collect_and_store_telemetry()` writes 18 audit points to `config_db.jsonl`
- Safe module reload: never removes bcma while b43 is loaded
- Rate-limit safe NetworkManager restart with `systemctl reset-failed`
- 3-second mutex
- Firmware injection, driver strategy, power-save disable

### 🔧 System Integration (`setup-system.sh`)
- Writes sudoers NOPASSWD drop-in for all forensic commands
- Writes brcmsmac/brcmfmac blacklist
- Writes dracut firmware config
- Writes b43 to modules-load.d
- Rebuilds initramfs if firmware is present
- Idempotent: safe to run multiple times

### 📦 Firmware Fetcher (`prepare-bundle.sh`)
- Checks for existing firmware before fetching
- Method 1: `dnf install b43-firmware` (RPMFusion)
- Method 2: `b43-fwcutter` + Broadcom driver download
- Rebuilds initramfs after installation
- Confirms firmware in initramfs via `lsinitrd`

### ✅ Compliance Auditor (`compliance_check.sh`)
- Checks scripts executable, system files present, firmware on disk and in initramfs
- Checks WIFI-HW enabled, wl* interface present, b43 loaded, brcmsmac absent
- Checks database has recent `audit_snapshot` with Wi-Fi interface
- Pre-commit hook blocks commits that fail compliance
- Exit code 0 = all pass, exit code 1 = failures requiring action

### 🖥️ Terminal Dashboard (`dashboard.ts`)
- Blessed-Contrib high-performance ASCII grid
- Live verbatim log tail
- Press **N** for instant recovery

### 🌐 Web Dashboard (`App.tsx`)
- Nuclear Recovery button
- Real-time telemetry and balancer
- Cold Start button

---

## 🚀 Quick Start

```bash
# Fresh clone -- one-time setup (requires password once)
git clone https://github.com/swipswaps/-Broadcom-BCM4331-Forensic-Controller-Unified-v39.8-.git
cd Broadcom-BCM4331-Forensic-Controller-Unified-v39.8

# Fetch firmware (requires internet)
bash prepare-bundle.sh

# System integration (one-time sudo, then passwordless forever)
sudo bash setup-system.sh

# Start dashboard
npm run cold-start

# Compliance audit
bash compliance_check.sh
```

---

## ✅ Request Compliance Explanation

This project adheres to the following core principles:

1. **Verbatim Transparency**: Every command run by the system is logged with its raw output and exit code in `verbatim_handshake.log`.
2. **Zero-State Resilience**: The system assumes it starts in the worst possible state. `fix-wifi.sh` recovers from missing firmware, wrong driver, rfkill block, and NM rate-limit simultaneously.
3. **Self-Healing**: The code detects its own failures and resolves them without user intervention. The autonomous daemon reacts in ≤3 seconds.
4. **Auditability**: Every action leaves a trace in `verbatim_handshake.log` or `config_db.jsonl`. The 18 deterministic audit points are written as structured JSON on every recovery run.
5. **Regression Prevention**: `compliance_check.sh` runs as a pre-commit hook. Upgrades that remove working features are blocked before they reach the repository.

---

*License: MIT | Compliance Certified: April 2026 by swipswaps*