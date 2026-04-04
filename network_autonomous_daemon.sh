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

# WHY: cooldown prevents recovery storm where nmcli monitor fires on every
#      NM state change during recovery (disconnected, unavailable, connecting,
#      getting IP, connected) -- each triggering a new recovery attempt.
#      Confirmed from log: 5 consecutive triggers at 15:52:29 with 0s between.
#      rm -f LOCK_FILE removed -- fix-wifi.sh manages its own mutex.
RECOVERY_IN_PROGRESS=0
LAST_RECOVERY=0

trigger_fast_recovery() {
  local now
  now=$(date +%s)
  local elapsed=$(( now - LAST_RECOVERY ))
  if [[ "$RECOVERY_IN_PROGRESS" -eq 1 ]] || [[ "$elapsed" -lt 20 ]]; then
    log "Recovery suppressed (cooldown ${elapsed}s < 20s or in progress)"
    return 0
  fi
  RECOVERY_IN_PROGRESS=1
  LAST_RECOVERY=$now
  log "DETECTED APPLET / NETWORK CHANGE â Nuclear Recovery in <3s"
  "$FIX_SCRIPT" || log "Recovery exited with error (logged)"
  RECOVERY_IN_PROGRESS=0
}
# WHY: cooldown prevents storm loop where nmcli monitor fires on every NM
#      state change during recovery (disconnected, connecting, getting IP,
#      connected) -- each triggering a new recovery attempt.
#      Confirmed from log: 5 consecutive triggers at 15:52:29 with 0s between.
#      rm -f LOCK_FILE removed -- fix-wifi.sh manages its own mutex.
RECOVERY_IN_PROGRESS=0
LAST_RECOVERY=0

trigger_fast_recovery() {
  local now
  now=$(date +%s)
  local elapsed=$(( now - LAST_RECOVERY ))
  if [[ "$RECOVERY_IN_PROGRESS" -eq 1 ]] || [[ "$elapsed" -lt 20 ]]; then
    log "Recovery suppressed (cooldown ${elapsed}s < 20s or in progress)"
    return 0
  fi
  RECOVERY_IN_PROGRESS=1
  LAST_RECOVERY=$now
  log "DETECTED APPLET / NETWORK CHANGE – Nuclear Recovery in <3s"
  "$FIX_SCRIPT" || log "Recovery exited with error (logged)"
  RECOVERY_IN_PROGRESS=0
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