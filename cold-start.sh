#!/usr/bin/env bash

# =============================================================================
# cold-start.sh (ZERO-STATE RECOVERY v39.8)
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[COLD-START] Starting zero-state recovery in $PROJECT_ROOT"

# 1. Clean environment
echo "[COLD-START] Cleaning node_modules."
rm -rf node_modules package-lock.json

# 2. Install dependencies
echo "[COLD-START] Installing npm dependencies."
npm install

# 3. System Integration
echo "[COLD-START] Performing system integration."
npm run setup

# 4. Launch Unified Dashboard
echo "[COLD-START] Launching Unified Dashboard."
npm run dev
