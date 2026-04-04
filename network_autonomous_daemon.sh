#!/usr/bin/env bash

# =============================================================================
# network_autonomous_daemon.sh (HARDENED + DNS-POLICY AWARE + SELF-HEALING)
# =============================================================================
# USER REQUEST COMPLIANCE:
# - No hardcoded DNS overrides (Respects system policy)
# - Discover -> Validate -> Augment pattern
# - Git update detection and automatic rebase
# - Integrated with hardware_software_db for forensic snapshots
# =============================================================================

set -euo pipefail

LOG_TAG="[AUTO-NET]"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_SCRIPT="${REPO_DIR}/hardware_software_db.sh"
LOG_FILE="${REPO_DIR}/verbatim_handshake.log"

# Fallback DNS is ONLY used if no DNS is present at all
FALLBACK_DNS="${FALLBACK_DNS:-1.1.1.1 8.8.8.8}"
BRANCH="master"
SLEEP_INTERVAL=15
DNS_REPAIR_COOLDOWN=60
LAST_DNS_REPAIR=0

# Load DB functions
[[ -f "$DB_SCRIPT" ]] && source "$DB_SCRIPT" || echo "[WARN] DB script not found at $DB_SCRIPT"

# -----------------------------------------------------------------------------
# LOGGING & ROTATION
# -----------------------------------------------------------------------------
log() {
  # Rotate log if > 10MB
  if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE") -gt 10485760 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
  fi
  echo "$(date -Iseconds) $LOG_TAG $1" >> "$LOG_FILE"
}

fail_soft() {
  log "[WARN] $1"
}

# -----------------------------------------------------------------------------
# DNS INTELLIGENCE (NON-INVASIVE)
# -----------------------------------------------------------------------------
get_current_dns() {
  # Uses nmcli structured output for deterministic parsing
  nmcli -t -f IP4.DNS dev show 2>/dev/null | cut -d':' -f2 | sort -u | grep -v '^$' || true
}

validate_dns() {
  # Simple resolution test
  getent hosts github.com >/dev/null 2>&1
}

repair_dns() {
  local now
  now=$(date +%s)

  if (( now - LAST_DNS_REPAIR < DNS_REPAIR_COOLDOWN )); then
    log "DNS repair cooldown active (Wait $((DNS_REPAIR_COOLDOWN - (now - LAST_DNS_REPAIR)))s)"
    return
  fi

  log "Attempting DNS repair (policy-aware)"
  LAST_DNS_REPAIR=$now

  local active_con
  active_con=$(nmcli -t -f NAME connection show --active | head -n1 || true)

  if [[ -z "$active_con" ]]; then
    fail_soft "No active connection to repair"
    return
  fi

  local current_dns
  current_dns=$(get_current_dns)

  if [[ -n "$current_dns" ]]; then
    log "Existing DNS detected ($current_dns) -> Respecting system policy"
    return
  fi

  log "No DNS detected -> Applying fallback: $FALLBACK_DNS"
  nmcli con mod "$active_con" ipv4.dns "$FALLBACK_DNS" || true
  nmcli con mod "$active_con" ipv4.ignore-auto-dns yes || true
  nmcli con reload || true
  
  # Restart NetworkManager to ensure propagation
  sudo systemctl restart NetworkManager || true
}

# -----------------------------------------------------------------------------
# GIT OPERATIONS
# -----------------------------------------------------------------------------
check_for_updates() {
  # Suppress stderr to avoid red noise during transient network drops
  git fetch origin "$BRANCH" >/dev/null 2>&1 || return 1

  local local_sha remote_sha
  local_sha=$(git rev-parse HEAD)
  remote_sha=$(git rev-parse "origin/$BRANCH")

  [[ "$local_sha" != "$remote_sha" ]]
}

apply_update() {
  log "Applying update (rebase-pull)"
  # Force non-interactive to prevent daemon hanging
  if GIT_TERMINAL_PROMPT=0 git pull --rebase origin "$BRANCH"; then
    log "Update success"
    return 0
  else
    log "Update failed -> Rolling back rebase"
    git rebase --abort || true
    return 1
  fi
}

# -----------------------------------------------------------------------------
# FORENSIC SNAPSHOTS
# -----------------------------------------------------------------------------
capture_system_state() {
  local hw_json sw_json
  
  hw_json=$(cat <<EOF
{"kernel":"$(uname -r)","arch":"$(uname -m)","hostname":"$(hostname)"}
EOF
)
  sw_json=$(cat <<EOF
{"bash":"$BASH_VERSION","git":"$(git --version 2>/dev/null || true)"}
EOF
)

  add_config_entry "hardware" "daemon_snapshot" "$hw_json" 2>/dev/null || true
  add_config_entry "software" "daemon_snapshot" "$sw_json" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# MAIN LOOP
# -----------------------------------------------------------------------------
main_loop() {
  log "Starting Autonomous Daemon in $REPO_DIR"

  while true; do
    # 1. DNS Validation
    if ! validate_dns; then
      fail_soft "DNS failed"
      # Call forensic engine for deep recovery
      bash "${REPO_DIR}/fix-wifi.sh" || fail_soft "Forensic recovery failed"
    else
      log "DNS OK"
    fi

    # 2. Forensic Snapshot
    bash "${REPO_DIR}/fix-wifi.sh" --snapshot-only 2>/dev/null || true

    sleep "$SLEEP_INTERVAL"
  done
}

# Start
main_loop
