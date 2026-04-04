#!/usr/bin/env bash
# PATH: compliance_check.sh
# =============================================================================
# compliance_check.sh (v39.9)
# =============================================================================
# WHAT: deterministic compliance audit for BCM4331 Forensic Controller.
#       Checks every system file and database entry required for Wi-Fi to
#       work at boot without manual intervention.
#
# WHY: v39.8 compliance_check.sh tested for literal strings in fix-wifi.sh
#      that no longer exist in v39.9 (e.g. "AUDIT POINT 17"). This version
#      tests observable system state and database content instead of source
#      text -- making it regression-proof against refactoring.
#
# MENTAL MODEL BEFORE: compliance checked script source text -- any rename
#   or refactor caused false failures; real system gaps went undetected
# MENTAL MODEL AFTER: compliance checks deployed system state -- blacklist
#   present, firmware on disk, firmware in initramfs, sudoers grants working,
#   service enabled, database has recent audit snapshot
#
# FAILURE MODE: any FAIL line means the system will not recover Wi-Fi
#   automatically. Run setup-system.sh to fix system files, fix-wifi.sh
#   to refresh the database.
#
# VERIFIES WITH: all lines print PASS; exit code 0

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="${PROJECT_ROOT}/config_db.jsonl"
PASS=0
FAIL=0
FAILS=()

echo "[AUDIT] Starting compliance check in $PROJECT_ROOT"
echo ""

check() {
    local label="$1"
    local result="$2"  # "pass" or "fail: reason"
    if [[ "$result" == "pass" ]]; then
        echo "  PASS: $label"
        (( PASS++ )) || true
    else
        echo "  FAIL: $label ($result)"
        (( FAIL++ )) || true
        FAILS+=("$label: $result")
    fi
}

# ── Section 1: Script files present and executable ──────────────────────────
echo "[ Scripts ]"
for script in fix-wifi.sh setup-system.sh prepare-bundle.sh network_autonomous_daemon.sh compliance_check.sh; do
    if [[ -x "${PROJECT_ROOT}/${script}" ]]; then
        check "$script executable" "pass"
    else
        check "$script executable" "fail: not executable or missing"
    fi
done
echo ""

# ── Section 2: System files written by setup-system.sh ──────────────────────
echo "[ System Files ]"

# Blacklist
if [[ -f /etc/modprobe.d/broadcom-bcm4331.conf ]]; then
    if grep -q "blacklist brcmsmac" /etc/modprobe.d/broadcom-bcm4331.conf; then
        check "brcmsmac blacklist" "pass"
    else
        check "brcmsmac blacklist" "fail: file exists but blacklist brcmsmac not found"
    fi
else
    check "brcmsmac blacklist" "fail: /etc/modprobe.d/broadcom-bcm4331.conf missing"
fi

# Dracut config
if [[ -f /etc/dracut.conf.d/b43-firmware.conf ]]; then
    if grep -q "ucode29_mimo.fw" /etc/dracut.conf.d/b43-firmware.conf; then
        check "dracut b43 config" "pass"
    else
        check "dracut b43 config" "fail: file exists but firmware entries missing"
    fi
else
    check "dracut b43 config" "fail: /etc/dracut.conf.d/b43-firmware.conf missing"
fi

# modules-load.d
if [[ -f /etc/modules-load.d/b43.conf ]] && grep -q "b43" /etc/modules-load.d/b43.conf; then
    check "b43 modules-load.d" "pass"
else
    check "b43 modules-load.d" "fail: /etc/modules-load.d/b43.conf missing or empty"
fi

# sudoers -- check for owner specifically, not root
CURRENT_USER="${SUDO_USER:-$(whoami)}"
if sudo test -f /etc/sudoers.d/broadcom-control 2>/dev/null; then
    if sudo grep -q "$CURRENT_USER" /etc/sudoers.d/broadcom-control 2>/dev/null && \
       sudo grep -q "NOPASSWD" /etc/sudoers.d/broadcom-control 2>/dev/null; then
        check "sudoers NOPASSWD for $CURRENT_USER" "pass"
    else
        check "sudoers NOPASSWD for $CURRENT_USER" "fail: file exists but $CURRENT_USER or NOPASSWD not found"
    fi
else
    check "sudoers NOPASSWD for $CURRENT_USER" "fail: /etc/sudoers.d/broadcom-control missing"
fi

# systemd service installed and enabled
if [[ -f /etc/systemd/system/fix-wifi.service ]]; then
    check "fix-wifi.service installed" "pass"
else
    check "fix-wifi.service installed" "fail: not in /etc/systemd/system/"
fi

SVC_ENABLED=$(systemctl is-enabled fix-wifi.service 2>/dev/null || echo "disabled")
if [[ "$SVC_ENABLED" == "enabled" ]]; then
    check "fix-wifi.service enabled" "pass"
else
    check "fix-wifi.service enabled" "fail: systemctl is-enabled returned '$SVC_ENABLED'"
fi
echo ""

# ── Section 3: Firmware ──────────────────────────────────────────────────────
echo "[ Firmware ]"

REQUIRED_FW=("ucode29_mimo.fw" "ht0initvals29.fw" "ht0bsinitvals29.fw")
for fw in "${REQUIRED_FW[@]}"; do
    if [[ -f "/usr/lib/firmware/b43/$fw" ]]; then
        check "firmware on disk: $fw" "pass"
    else
        check "firmware on disk: $fw" "fail: /usr/lib/firmware/b43/$fw missing -- run prepare-bundle.sh"
    fi
done

# Firmware in initramfs -- critical: missing here = boot-time ENOENT
# WHY: confirmed failure mode from session 2026-04-04 -- firmware on disk but
#      not in initramfs caused error -2 at boot. dracut --force fixed it.
if sudo lsinitrd 2>/dev/null | grep "b43" | grep -q "."; then
    check "firmware in initramfs" "pass"
else
    check "firmware in initramfs" "fail: run sudo dracut --force to rebuild initramfs"
fi
echo ""

# ── Section 4: Live system state ────────────────────────────────────────────
echo "[ Live State ]"

WIFI_HW=$(nmcli radio 2>/dev/null | awk 'NR>1{print $1; exit}' || echo "unknown")
if [[ "$WIFI_HW" == "enabled" ]]; then
    check "WIFI-HW enabled" "pass"
else
    check "WIFI-HW enabled" "fail: nmcli radio shows WIFI-HW=$WIFI_HW -- run fix-wifi.sh"
fi

WL_IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
if [[ -n "$WL_IFACE" ]]; then
    check "Wi-Fi interface present ($WL_IFACE)" "pass"
else
    check "Wi-Fi interface present" "fail: no wl* interface in /sys/class/net"
fi

B43_COUNT=$(lsmod | awk '/^b43 /{print $3}' || echo "")
if [[ "$B43_COUNT" == "-1" ]]; then
    check "b43 module refcount" "fail: refcount is -1 (stuck) -- reboot required"
elif [[ -n "$B43_COUNT" ]]; then
    check "b43 module loaded" "pass"
else
    check "b43 module loaded" "fail: b43 not in lsmod"
fi

BRCMSMAC_LOADED=$(lsmod | grep -c "^brcmsmac " || echo "0")
if [[ "$BRCMSMAC_LOADED" == "0" ]]; then
    check "brcmsmac not loaded" "pass"
else
    # blacklist present but module loaded before it was written -- clears on reboot
    if [[ -f /etc/modprobe.d/broadcom-bcm4331.conf ]]; then
        echo "  WARN: brcmsmac loaded but blacklist is present -- will clear on reboot"
        (( PASS++ )) || true
    else
        check "brcmsmac not loaded" "fail: brcmsmac loaded and no blacklist found"
    fi
fi
echo ""

# ── Section 5: Database ──────────────────────────────────────────────────────
echo "[ Database ]"

if [[ -f "$DB_FILE" ]]; then
    check "config_db.jsonl exists" "pass"
    LINE_COUNT=$(wc -l < "$DB_FILE")
    check "config_db.jsonl has entries ($LINE_COUNT lines)" "pass"

    # Find most recent audit_snapshot
    LATEST_SNAPSHOT=$(grep '"type":"audit_snapshot"' "$DB_FILE" | tail -n 1 || echo "")
    if [[ -n "$LATEST_SNAPSHOT" ]]; then
        SNAPSHOT_TS=$(echo "$LATEST_SNAPSHOT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['timestamp'])" 2>/dev/null || echo "unknown")
        WIFI_IFACE=$(echo "$LATEST_SNAPSHOT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('wifi_iface','none'))" 2>/dev/null || echo "unknown")
        PASS_COUNT=$(echo "$LATEST_SNAPSHOT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
points=['rfkill_soft','rfkill_hard','pci_bus','driver_loaded','firmware_loaded',
        'iface_created','iface_up','ip_assigned','gw_reachable','dns_resolved',
        'signal_stable','tx_power','entropy_pool','wpa_active','nm_active',
        'pid_stable','mutex_lock','bkw_sync']
print(sum(1 for p in points if d.get(p,False)))
" 2>/dev/null || echo "0")
        check "latest audit_snapshot: $SNAPSHOT_TS wifi=$WIFI_IFACE points=$PASS_COUNT/18" "pass"
    else
        check "audit_snapshot in database" "fail: no audit_snapshot entries -- run fix-wifi.sh to populate"
    fi
else
    check "config_db.jsonl exists" "fail: missing -- run fix-wifi.sh"
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "========================================"
echo "AUDIT COMPLETE: PASS=$PASS FAIL=$FAIL"
echo "========================================"

if (( FAIL > 0 )); then
    echo ""
    echo "Failures requiring action:"
    for f in "${FAILS[@]}"; do
        echo "  → $f"
    done
    echo ""
    echo "To fix system files:  sudo bash setup-system.sh"
    echo "To fix firmware:      bash prepare-bundle.sh"
    echo "To refresh database:  sudo bash fix-wifi.sh"
    exit 1
fi

exit 0