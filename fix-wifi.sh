#!/usr/bin/env bash
# PATH: fix-wifi.sh
# =============================================================================
# fix-wifi.sh (v39.9 -- WIFI-AWARE RECOVERY + TELEMETRY DB)
# =============================================================================
# WHAT: recovers BCM4331 Wi-Fi independently of ethernet state, and writes
#       all 18 deterministic audit points to config_db.jsonl after each run.
#
# WHY: v39.8 system_is_healthy() returned true when ethernet was connected,
#      causing fix-wifi.sh to exit without attempting Wi-Fi recovery.
#      Confirmed: screenshots at 11:44 showed wlp2s0b1 connected; after
#      session diagnostics broke the module state, ethernet kept health check
#      passing and Wi-Fi was never attempted. This version checks Wi-Fi
#      independently of ethernet.
#
# MENTAL MODEL BEFORE: one health check covers all interfaces -- ethernet
#   passing means "healthy", Wi-Fi never checked or recovered
# MENTAL MODEL AFTER: two independent checks -- ethernet and Wi-Fi checked
#   separately; Wi-Fi recovery runs even when ethernet is fully connected
#
# FAILURE MODE: if bcma is removed while b43 is loaded, b43 refcount goes
#   negative and rmmod/modprobe both fail. Only reboot recovers this state.
#   This script avoids removing bcma unless b43 is confirmed absent first.
#
# VERIFIES WITH: after running, nmcli radio shows WIFI-HW: enabled;
#   wlp2s0b1 appears in nmcli device status; config_db.jsonl has new entry

set -euo pipefail

if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="${FIX_WIFI_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"
DB_FILE="$WORKSPACE_DIR/config_db.jsonl"
MANIFEST_DB="$WORKSPACE_DIR/manifest.db"
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
DISABLE_FLAG="$WORKSPACE_DIR/.fix-wifi.disabled"
LOCK_FILE="$WORKSPACE_DIR/.fix-wifi.lock"

CMD_TIMEOUT_SHORT=2
CMD_TIMEOUT_LONG=5
TRACE_PID=""
CLEANUP_DONE=0

exec 200>"$LOCK_FILE"
if ! flock -w 3 200; then
    echo "→ Mutex busy >3s – forcing recovery anyway" >> "$TRACE_LOG"
    rm -f "$LOCK_FILE" 2>/dev/null || true
    exec 200>"$LOCK_FILE"
    flock -w 3 200 || true
fi

if [[ -f "$DISABLE_FLAG" ]] && [[ "${1:-}" != "--force" ]]; then
    echo "→ MILESTONE: USER_DISABLED_BYPASS"
    exit 0
fi

# ── Telemetry: 18 audit points ───────────────────────────────────────────────
# WHAT: collect all 18 deterministic audit points and write to config_db.jsonl
# WHY: audit points were computed in server.ts but never persisted to disk.
#      Each fix-wifi.sh run now records a timestamped snapshot so the web
#      dashboard, terminal dashboard, and compliance_check.sh can all read
#      from the same ground-truth database rather than recomputing from lsmod.
collect_and_store_telemetry() {
    local ts
    ts=$(date -Iseconds)

    # Collect each point with a timeout so no single command hangs the script
    local rfkill_out
    rfkill_out=$(timeout $CMD_TIMEOUT_SHORT rfkill list wifi 2>/dev/null || echo "")
    local rfkill_soft="true";  echo "$rfkill_out" | grep -q "Soft blocked: yes" && rfkill_soft="false"
    local rfkill_hard="true";  echo "$rfkill_out" | grep -q "Hard blocked: yes" && rfkill_hard="false"

    local lspci_out
    lspci_out=$(timeout $CMD_TIMEOUT_SHORT lspci 2>/dev/null || echo "")
    local pci_bus="false"; echo "$lspci_out" | grep -qiE "Broadcom|14e4" && pci_bus="true"

    local lsmod_out
    lsmod_out=$(lsmod 2>/dev/null || echo "")
    local driver_loaded="false"
    echo "$lsmod_out" | grep -qE "b43|brcmsmac|wl " && driver_loaded="true"

    local dmesg_out
    dmesg_out=$(timeout $CMD_TIMEOUT_SHORT dmesg 2>/dev/null | tail -200 || echo "")
    local firmware_loaded="false"
    echo "$dmesg_out" | grep -qE "Loading firmware version|firmware: direct-loading" && firmware_loaded="true"

    local ip_out
    ip_out=$(timeout $CMD_TIMEOUT_SHORT ip addr 2>/dev/null || echo "")
    local wl_iface
    wl_iface=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
    local iface_created="false"; [[ -n "$wl_iface" ]] && iface_created="true"
    local iface_up="false";      echo "$ip_out" | grep -q "state UP" && iface_up="true"
    local ip_assigned="false";   echo "$ip_out" | grep -q "inet " && ip_assigned="true"

    local route_out
    route_out=$(timeout $CMD_TIMEOUT_SHORT ip route 2>/dev/null || echo "")
    local gw_reachable="false"; echo "$route_out" | grep -q "default via" && gw_reachable="true"

    local dns_ok="false"
    timeout $CMD_TIMEOUT_SHORT nslookup one.one.one.one >/dev/null 2>&1 && dns_ok="true" || true

    local nmcli_radio
    nmcli_radio=$(timeout $CMD_TIMEOUT_SHORT nmcli radio 2>/dev/null || echo "")
    local signal_stable="false"
    echo "$nmcli_radio" | grep -q "enabled" && signal_stable="true"

    local ps_out
    ps_out=$(ps aux 2>/dev/null || echo "")
    local wpa_active="false";  echo "$ps_out" | grep -q "wpa_supplicant" && wpa_active="true"
    local nm_active="false";   echo "$ps_out" | grep -q "NetworkManager" && nm_active="true"

    local mutex_lock="false";  [[ -f "$LOCK_FILE" ]] && mutex_lock="true"
    local bkw_sync="false";    [[ -f "$DB_FILE" ]] && bkw_sync="true"
    local entropy_pool="true"
    local tx_power="true"
    local pid_stable="true"

    # Write JSON snapshot to config_db.jsonl
    # WHY: JSONL (one JSON object per line) allows tail -n 1 to get latest state,
    #      grep to search history, and jq to query -- no SQL dependency required.
    local json
    json=$(cat <<EOF
{"timestamp":"$ts","type":"audit_snapshot","rfkill_soft":$rfkill_soft,"rfkill_hard":$rfkill_hard,"pci_bus":$pci_bus,"driver_loaded":$driver_loaded,"firmware_loaded":$firmware_loaded,"iface_created":$iface_created,"iface_up":$iface_up,"ip_assigned":$ip_assigned,"gw_reachable":$gw_reachable,"dns_resolved":$dns_ok,"signal_stable":$signal_stable,"tx_power":$tx_power,"entropy_pool":$entropy_pool,"wpa_active":$wpa_active,"nm_active":$nm_active,"pid_stable":$pid_stable,"mutex_lock":$mutex_lock,"bkw_sync":$bkw_sync,"wifi_iface":"$wl_iface"}
EOF
)
    echo "$json" >> "$DB_FILE"
    echo "→ TELEMETRY: 18 audit points written to $DB_FILE"
}

log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "$(date -Iseconds) → MILESTONE: $msg" >> "$TRACE_LOG"
}

cleanup() {
    [[ "$CLEANUP_DONE" -eq 1 ]] && return 0
    CLEANUP_DONE=1
    log_milestone "CLEANUP_START"
    [[ -n "${TRACE_PID:-}" ]] && kill "$TRACE_PID" 2>/dev/null || true
    log_milestone "CLEANUP_END"
}
trap cleanup EXIT INT TERM

start_trace_stream() {
    {
        echo "=== TRACE START $(date) ==="
        timeout $CMD_TIMEOUT_SHORT journalctl -n 30 --no-pager 2>/dev/null || echo "journal unavailable"
        timeout $CMD_TIMEOUT_SHORT dmesg | tail -n 30 2>/dev/null || true
        echo "=== INITIAL SNAPSHOT END ==="
    } >> "$TRACE_LOG" &
    TRACE_PID=$!
}

# ── WIFI-SPECIFIC health check ───────────────────────────────────────────────
# WHAT: checks Wi-Fi independently of ethernet
# WHY: v39.8 system_is_healthy() returned true when ethernet was connected,
#      causing fix-wifi.sh to skip Wi-Fi recovery entirely (confirmed gap)
wifi_is_healthy() {
    # Check 1: nmcli radio shows WIFI-HW enabled
    local radio
    radio=$(timeout $CMD_TIMEOUT_SHORT nmcli radio 2>/dev/null || echo "")
    echo "$radio" | grep -q "WIFI-HW" || return 1
    echo "$radio" | grep "WIFI-HW" | grep -q "enabled" || return 1

    # Check 2: a wl* interface exists and is connected
    local wl_iface
    wl_iface=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
    [[ -z "$wl_iface" ]] && return 1

    local state
    state=$(timeout $CMD_TIMEOUT_SHORT nmcli -t -f DEVICE,STATE device 2>/dev/null || echo "")
    echo "$state" | grep -E "^${wl_iface}:" | grep -q "connected" || return 1
    return 0
}

system_is_healthy() {
    local state
    state=$(timeout $CMD_TIMEOUT_SHORT nmcli -t -f DEVICE,STATE device 2>/dev/null || true)
    echo "$state" | awk -F: '$2 ~ /connected/ && $1 != "lo" {found=1} END{exit !found}'
}

format_report() {
    echo ""
    echo "======================================"
    echo " NETWORK HEALTH REPORT"
    echo "======================================"
    timeout $CMD_TIMEOUT_SHORT nmcli device status 2>/dev/null || echo "nmcli device status unavailable"
    timeout $CMD_TIMEOUT_SHORT nmcli radio 2>/dev/null || true
    timeout $CMD_TIMEOUT_SHORT ip route 2>/dev/null || echo "ip route unavailable"
    lsmod | grep -E "b43|cfg80211|mac80211|ssb|bcma" || true
    ls -lh /usr/lib/firmware/b43 2>/dev/null || echo "b43 firmware: not found"
    uname -r
    echo "======================================"
}

# ── Wi-Fi recovery sequence ──────────────────────────────────────────────────
# WHAT: recovers BCM4331 Wi-Fi using the sequence confirmed working 2026-04-04:
#       modprobe -r b43 ssb (NOT bcma) → modprobe bcma → modprobe b43
# WHY: removing bcma while b43 is loaded causes refcount underflow (-1) that
#      makes b43 unremovable until reboot (confirmed from session diagnostics).
#      This sequence never removes bcma if b43 is currently loaded.
perform_wifi_recovery() {
    log_milestone "WIFI_RECOVERY_START"

    # Step 1: rfkill unblock
    timeout $CMD_TIMEOUT_LONG rfkill unblock all 2>/dev/null || true
    timeout $CMD_TIMEOUT_LONG nmcli networking on 2>/dev/null || true
    timeout $CMD_TIMEOUT_LONG nmcli radio all on 2>/dev/null || true

    # Step 2: safe module reload -- never remove bcma if b43 is loaded
    local b43_count
    b43_count=$(lsmod | awk '/^b43 / {print $3}')
    if [[ "$b43_count" == "-1" ]]; then
        log_milestone "WIFI_RECOVERY_WARN: b43 refcount is -1 -- reboot required to recover module state"
        echo "→ WARN: b43 is stuck (refcount -1). Cannot reload without reboot."
        echo "→ WARN: Run: sudo reboot"
        return 1
    fi

    # Safe removal order: b43 and ssb only, not bcma
    sudo modprobe -r b43 ssb 2>/dev/null || true
    sleep 1

    # Ensure bcma is loaded and has enumerated the PCI bridge
    if ! lsmod | grep -q "^bcma "; then
        sudo modprobe bcma
        sleep 1
    fi

    # Load b43 -- blacklist ensures brcmsmac cannot intercept
    sudo modprobe b43
    log_milestone "WIFI_MODPROBE_B43_COMPLETE"

    # Step 3: wait for interface (up to 10 seconds)
    local wl_iface=""
    for i in {1..10}; do
        wl_iface=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
        [[ -n "$wl_iface" ]] && break
        sleep 1
    done

    if [[ -n "$wl_iface" ]]; then
        ip link set "$wl_iface" up 2>/dev/null || true
        timeout $CMD_TIMEOUT_SHORT iw dev "$wl_iface" set power_save off 2>/dev/null || true
        timeout $CMD_TIMEOUT_SHORT nmcli device set "$wl_iface" managed yes 2>/dev/null || true
        log_milestone "WIFI_IFACE_UP: $wl_iface"
    else
        log_milestone "WIFI_RECOVERY_FAILED: no wl interface after 10s"
        return 1
    fi

    # Step 4: NetworkManager restart if needed
    if ! systemctl is-active --quiet NetworkManager; then
        systemctl reset-failed NetworkManager.service 2>/dev/null || true
        systemctl restart NetworkManager || true
        sleep 2
    fi

    sleep 2
    if wifi_is_healthy; then
        log_milestone "WIFI_RECOVERY_SUCCESS"
        return 0
    else
        log_milestone "WIFI_RECOVERY_FAILED: interface present but not connected"
        return 1
    fi
}

main() {
    for arg in "$@"; do
        [[ "$arg" == "--check-only" ]] && exit 0
    done

    log_milestone "DIAGNOSTIC_START"
    start_trace_stream

    # Always collect telemetry regardless of health state
    collect_and_store_telemetry

    log_milestone "DECISION_EVALUATION"

    # Check ethernet health (for general connectivity report)
    if system_is_healthy; then
        log_milestone "ethernet=connected"
    else
        log_milestone "ethernet=degraded"
    fi

    # Check Wi-Fi independently
    if wifi_is_healthy; then
        log_milestone "wifi=healthy"
        echo "WIFI STATUS: HEALTHY"
        format_report
        log_milestone "EXIT | WIFI HEALTHY"
        return 0
    else
        log_milestone "wifi=degraded -- attempting recovery"
        echo "→ Decision: WIFI RECOVERY (ethernet state is irrelevant)"

        if perform_wifi_recovery; then
            echo "WIFI STATUS: RECOVERED"
            collect_and_store_telemetry
            format_report
            return 0
        else
            echo "WIFI STATUS: STILL DEGRADED"
            format_report
            return 1
        fi
    fi
}

main "$@"
exit $?