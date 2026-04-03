#!/usr/bin/env bash

# =============================================================================
# prepare-bundle.sh (BUNDLE PACKER v39.8)
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_FILE="${PROJECT_ROOT}/bcm4331-forensic-bundle.tar.gz"

echo "[BUNDLE] Creating forensic bundle in $PROJECT_ROOT"

# Exclude node_modules and dist
tar --exclude='node_modules' --exclude='dist' --exclude='.git' -czf "$BUNDLE_FILE" -C "$PROJECT_ROOT" .

echo "[BUNDLE] Created: $BUNDLE_FILE"
