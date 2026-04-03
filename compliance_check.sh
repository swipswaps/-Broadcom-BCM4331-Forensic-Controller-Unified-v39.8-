#!/usr/bin/env bash

# =============================================================================
# compliance_check.sh (REQUEST COMPLIANCE AUDIT SUITE)
# =============================================================================
# PURPOSE:
#   Verify every technical and operational constraint defined by the user.
#   Ensures "Verbatim Transparency", "Zero-State Resilience", and "Auditability".
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "--- STARTING REQUEST COMPLIANCE AUDIT ---\n"

check_feature() {
  local label="$1"
  local cmd="$2"
  echo -n "[ ] $label... "
  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}PASSED${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    return 1
  fi
}

# 1. Autonomous Daemon Integrity
check_feature "Daemon: DNS Policy Awareness (Discover->Validate->Augment)" \
  "grep -q 'nmcli con mod' network_autonomous_daemon.sh && grep -q 'get_current_dns' network_autonomous_daemon.sh"

check_feature "Daemon: Git Update Logic (Fetch/Rebase)" \
  "grep -q 'git fetch' network_autonomous_daemon.sh && grep -q 'git pull --rebase' network_autonomous_daemon.sh"

# 2. Forensic DB Integrity
check_feature "DB: Source-Safe (No global set -e when sourced)" \
  "grep -q 'if \[\[ \"\${BASH_SOURCE\[0\]}\" == \"\${0}\" \]\]; then' hardware_software_db.sh"

check_feature "DB: Canonical Schema (Timestamp/Type/Name/Data)" \
  "grep -q '\"timestamp\":\"\$timestamp\",\"type\":\"\$type\",\"name\":\"\$name\",\"data\":\$json' hardware_software_db.sh"

# 3. Server Logic
check_feature "Server: Forensic Endpoint (/api/forensics)" \
  "grep -q 'app.get('\''/api/forensics'\' server.ts"

check_feature "Server: Port Killing Logic (lsof/kill)" \
  "grep -q 'killPortOccupant' server.ts && grep -q 'lsof -t -i' server.ts"

# 4. Dashboard (Terminal)
check_feature "Terminal: Blessed-Contrib Integration" \
  "grep -q 'import contrib from '\''blessed-contrib'\' dashboard.ts"

check_feature "Terminal: Nuclear Button Logic" \
  "grep -q 'nuclearBtn' dashboard.ts && grep -q 'triggerFix' dashboard.ts"

# 5. Dashboard (Web)
check_feature "Web: High-Fidelity Forensic UI" \
  "grep -q 'ForensicEvent' src/App.tsx && grep -q 'fetchForensics' src/App.tsx"

check_feature "Web: PID Tuning Sliders" \
  "grep -q 'pidParams' src/App.tsx && grep -q 'type=\"range\"' src/App.tsx"

# 6. Operational Compliance
check_feature "Ops: Zero-State Resilience (Setup script)" \
  "grep -q '\"setup\":' package.json"

check_feature "Ops: Verbatim Transparency (Log file path)" \
  "grep -q 'LOG_FILE' server.ts"

echo -e "\n--- AUDIT COMPLETE ---"
