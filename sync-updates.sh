#!/usr/bin/env bash

# =============================================================================
# sync-updates.sh (GIT SYNC v39.8)
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH="master"

echo "[SYNC] Checking for remote updates in $PROJECT_ROOT"

cd "$PROJECT_ROOT"
git fetch origin "$BRANCH" || { echo "[SYNC] Remote unreachable."; exit 0; }

LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse "origin/$BRANCH")

if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
    echo "[SYNC] Update available. Applying rebase-pull."
    git pull --rebase origin "$BRANCH"
    echo "[SYNC] Update successful."
else
    echo "[SYNC] Already up to date."
fi
