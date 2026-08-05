#!/bin/bash
# Pulls the deployment branch and recompiles if it has moved since the last
# successful compile. Never touches DreamDaemon itself -- restarting to pick
# up the new .dmb is a separate step (see DEPLOYMENT.md).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DEPLOY_BRANCH="${DEPLOY_BRANCH:-deployment}"
MARKER_FILE="scripts/.last-deployed-commit"
LOG_FILE="scripts/deploy.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== deploy.sh started $(date -Iseconds), branch=$DEPLOY_BRANCH ==="

git fetch origin "$DEPLOY_BRANCH"
git checkout -B "$DEPLOY_BRANCH" "origin/$DEPLOY_BRANCH"
CURRENT="$(git rev-parse HEAD)"
LAST_DEPLOYED="$(cat "$MARKER_FILE" 2>/dev/null || echo "")"

if [[ "$CURRENT" == "$LAST_DEPLOYED" ]]; then
	echo "Already compiled at $CURRENT, nothing to do."
	exit 0
fi

echo "Compiling $CURRENT (previously deployed: ${LAST_DEPLOYED:-none})..."
if tools/build/build.sh; then
	echo "$CURRENT" > "$MARKER_FILE"
	echo "Compile succeeded -- $CURRENT is ready. Restart DreamDaemon to go live (not done by this script)."
else
	echo "Compile FAILED at $CURRENT -- marker not updated, will retry next run."
	exit 1
fi
