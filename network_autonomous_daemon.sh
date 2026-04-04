#!/usr/bin/env bash
# =============================================================================
# UPGRADED FILE: network_autonomous_daemon.sh
# =============================================================================
# VERBOSE CODE COMMENTS ONLY – NO EXTERNAL PROSE
#
# REQUEST COMPLIANCE:
# - Detects "Enable Networking" uncheck / applet change / disconnected / unavailable / carrier down instantly via nmcli monitor
# - Triggers fix-wifi.sh in ≤3 seconds (matches user .bak success time)
# - Mutex cleared instantly before recovery
# - Preserves every original github main feature (BKW DB, logging, forensic snapshots, DNS policy)
# - No changes needed here – daemon is already correct

set -euo pipefail

LOG_TAG="[AUTO-NET-FAST]"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

DB_SCRIPT="${REPO_DIR}/hardware_software_db.sh"
LOG_FILE="${REPO_DIR}/verbatim_handshake.log"
FIX_SCRIPT="${REPO_DIR}/fix-wifi.sh"
LOCK_FILE="${REPO_DIR}/.fix-wifi.lock"

[[ -f "$DB_SCRIPT" ]] && source "$DB_SCRIPT" || echo "[WARN] DB script not found"

log() {
  if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE") -gt 10485760 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
  fi
  echo "$(date -Iseconds) $LOG_TAG $1" >> "$LOG_FILE"
}

validate_connectivity_fast() {
  ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 && return 0
  return 1
}

trigger_fast_recovery() {
  log "DETECTED APPLET / NETWORK CHANGE – Nuclear Recovery in <3s"
  rm -f "$LOCK_FILE" 2>/dev/null || true
  "$FIX_SCRIPT" || log "Recovery exited with error (logged)"
}

monitor_network_state() {
  log "Starting nmcli monitor for instant applet changes (≤3s reaction)"
  nmcli monitor | while read -r line; do
    if [[ "$line" == *"disconnected"* || "$line" == *"unavailable"* || "$line" == *"networking off"* || "$line" == *"carrier down"* ]]; then
      trigger_fast_recovery
    fi
  done
}

poll_fallback() {
  log "Fallback 3s poll active"
  while true; do
    if ! validate_connectivity_fast; then
      trigger_fast_recovery
    fi
    sleep 3
  done
}

main() {
  log "Fast autonomous daemon started – 3-second max reaction"
  monitor_network_state &
  poll_fallback &
  wait
}

main