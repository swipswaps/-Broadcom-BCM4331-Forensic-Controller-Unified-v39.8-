#!/usr/bin/env bash

# =============================================================================
# hardware_software_db.sh (ZERO-RISK, SOURCE-SAFE, PRODUCTION-HARDENED)
# =============================================================================
# USER REQUEST COMPLIANCE:
# - NEVER terminate an interactive shell when sourced (Fixes "terminal closing" bug)
# - Maintain deterministic behavior when executed directly
# - Avoid -u / -e / -o pipefail in sourced context to prevent environment collisions
# - Provide explicit, controlled error handling for all DB operations
# =============================================================================

# -----------------------------
# STRICT MODE (EXECUTION ONLY)
# -----------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Safe to enable strict mode ONLY when executed directly
  # This guarantees deterministic behavior without affecting the parent shell
  set -euo pipefail
fi

# -----------------------------
# INTERNAL CONFIGURATION
# -----------------------------
# DB_FILE is the append-only JSONL store that lives in the repo
DB_FILE="config_db.jsonl"

# -----------------------------
# FILE INITIALIZATION (SAFE)
# -----------------------------
if [[ ! -f "$DB_FILE" ]]; then
  # Explicit, safe creation — no reliance on implicit redirection failures
  touch "$DB_FILE" 2>/dev/null || {
    echo "[ERROR] Failed to create DB file: $DB_FILE"
    return 1 2>/dev/null || exit 1
  }
fi

# -----------------------------
# CORE FUNCTION: ADD ENTRY
# -----------------------------
# Usage: add_config_entry "hardware" "my_laptop" '{"cpu":"intel"}'
add_config_entry() {
  local type="${1:-}"
  local name="${2:-}"
  local json="${3:-}"

  # Manual validation (no set -u dependency)
  if [[ -z "$type" || -z "$name" || -z "$json" ]]; then
    echo "[ERROR] add_config_entry requires: type, name, json"
    return 1
  fi

  # RFC3339 timestamp (portable and sortable)
  local timestamp
  timestamp="$(date -Iseconds)"

  # Append in strict JSONL format (Canonical Schema)
  # No jq dependency for writing — raw echo is most reliable for cold-starts
  echo "{\"timestamp\":\"$timestamp\",\"type\":\"$type\",\"name\":\"$name\",\"data\":$json}" >> "$DB_FILE" || {
    echo "[ERROR] Failed to write to DB file"
    return 1
  }

  echo "[OK] Added -> $type / $name @ $timestamp"
}

# -----------------------------
# QUERY: FILTER BY TYPE
# -----------------------------
get_configs_by_type() {
  local type="${1:-}"

  if [[ -z "$type" ]]; then
    echo "[ERROR] get_configs_by_type requires type"
    return 1
  fi

  # Safe grep (do not fail shell if no match)
  grep "\"type\":\"$type\"" "$DB_FILE" 2>/dev/null || true
}

# -----------------------------
# QUERY: GET LATEST ENTRY
# -----------------------------
get_latest_by_type() {
  local type="${1:-}"

  if [[ -z "$type" ]]; then
    echo "[ERROR] get_latest_by_type requires type"
    return 1
  fi

  # Reverse read (tac) + first match ensures we get the most recent snapshot
  tac "$DB_FILE" 2>/dev/null | grep -m1 "\"type\":\"$type\"" || true
}

# -----------------------------
# EXPORT FUNCTIONS FOR SOURCING
# -----------------------------
# Ensures functions are available in current shell context without requiring script execution
export -f add_config_entry 2>/dev/null || true
export -f get_configs_by_type 2>/dev/null || true
export -f get_latest_by_type 2>/dev/null || true

# -----------------------------
# ENVIRONMENT SAFETY FIX
# -----------------------------
# Prevent SSH variable errors when strict environments reference it
# This avoids "unbound variable" crashes in some shells that have set -u globally
: "${SSH_CONNECTION:=}"

# -----------------------------
# END OF SCRIPT
# -----------------------------
# This file is SAFE to:
#   source ./hardware_software_db.sh
# and
#   bash ./hardware_software_db.sh
# =============================================================================
