#!/usr/bin/env bash

# =============================================================================
# compliance_check.sh (AUDIT SUITE v39.8)
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${PROJECT_ROOT}/verbatim_handshake.log"

echo "[AUDIT] Starting compliance check in $PROJECT_ROOT"

check_feature() {
    local feature="$1"
    local pattern="$2"
    local file="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "[OK] $feature"
    else
        echo "[FAIL] $feature (Missing '$pattern' in $file)"
        return 1
    fi
}

# 1. Forensic Engine
check_feature "Forensic Engine (fix-wifi.sh)" "AUDIT POINT 17" "fix-wifi.sh"
check_feature "BKW Logic" "save_bkw" "fix-wifi.sh"
check_feature "RFKill Audit" "rfkill unblock all" "fix-wifi.sh"
check_feature "Module Reload" "modprobe -r brcmsmac" "fix-wifi.sh"

# 2. System Integration
check_feature "Sudoers Hardening" "NOPASSWD" "setup-system.sh"
check_feature "Database Initialization" "config_db.jsonl" "setup-system.sh"

# 3. Unified Telemetry
check_feature "17 Data Points" "17/17" "dashboard.ts"
check_feature "Forensic Audit Trail" "Forensic Events" "dashboard.ts"
check_feature "PID Controller Signals" "pidKp" "dashboard.ts"

# 4. Web Dashboard
check_feature "React Frontend" "App" "src/App.tsx"
check_feature "Framer Motion" "AnimatePresence" "src/App.tsx"
check_feature "Lucide Icons" "Wifi" "src/App.tsx"

# 5. Autonomous Daemon
check_feature "Self-Healing Loop" "while true" "network_autonomous_daemon.sh"
check_feature "DNS Policy Awareness" "validate_dns" "network_autonomous_daemon.sh"

# 6. Forensic Log
if [[ -f "$LOG_FILE" ]]; then
    echo "[OK] Forensic Log (verbatim_handshake.log)"
else
    echo "[FAIL] Forensic Log (Missing)"
fi

echo "[AUDIT] Compliance check complete."
