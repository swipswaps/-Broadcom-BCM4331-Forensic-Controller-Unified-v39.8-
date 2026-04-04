#!/usr/bin/env bash

# =============================================================================
# cold-start.sh (ZERO-STATE RECOVERY v39.8)
# =============================================================================
# USER REQUEST COMPLIANCE:
# - Atomic cleanup of orphaned processes
# - Hard reset to origin/main
# - Full dependency and system integration
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo "[COLD-START] Initiating zero-state recovery in $PROJECT_ROOT"

# 1. Kill orphaned processes
echo "[COLD-START] Terminating background forensics and server..."
pkill -f "tsx server.ts" || true
pkill -f "network_autonomous_daemon.sh" || true
pkill -f "dashboard.ts" || true
rm -f .fix-wifi.lock

# 2. Sync with remote
echo "[COLD-START] Syncing with origin/main."
git fetch origin
git reset --hard origin/main

# 3. Rebuild environment
echo "[COLD-START] Installing npm dependencies."
npm install

# 4. System Integration
echo "[COLD-START] Performing system integration (sudoers update)."
npm run setup

# 5. Launch Unified Dashboard
echo "[COLD-START] Launching Unified Dashboard."
npm run dev
