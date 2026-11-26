#!/bin/bash
# Syncs this fork with upstream Aurorastation/Aurora.3 via a real git merge --
# NOT file copying. The old scripts\sync-upstream.ps1 blindly Copy-Item -Force'd
# every file not on a tiny hardcoded 3-file list, destroying any fork
# customization in a shared base-game file that wasn't on that list. This
# replaces that entirely.
#
# -X ours resolves per CONFLICTING LINE, not per file: anything upstream
# changed that doesn't overlap a fork edit merges in in full either way; only
# lines that actually conflict with a fork change fall back to this fork's
# version. aurorastation.dme's own #include lines need no special handling as
# a result -- they're just lines upstream never touches.
#
# Never pushes, never touches the branch it started from -- always stops on
# its own "upstream-sync" branch for a human (or the calling workflow) to
# review, compile-check, and merge in themselves.
#
# Writes a full markdown report to scripts/.sync-summary.md (every incoming
# upstream commit by subject, every changed file, every conflict -- not a
# terse count) both for a human reading the console and so a calling
# workflow can hand it straight to a PR body with nothing missing.
#
# Usage: scripts/sync-upstream.sh   (run from anywhere; finds the repo root
#        from its own location)

set -uo pipefail

UPSTREAM_URL="https://github.com/Aurorastation/Aurora.3.git"
UPSTREAM_BRANCH="master"
SYNC_BRANCH="upstream-sync"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

SUMMARY="$ROOT/scripts/.sync-summary.md"

BASE_BRANCH="$(git symbolic-ref --short HEAD)"
echo "Base branch: $BASE_BRANCH"

if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "Adding upstream remote -> $UPSTREAM_URL"
    git remote add upstream "$UPSTREAM_URL"
fi

echo "Fetching upstream/$UPSTREAM_BRANCH..."
if ! git fetch upstream "$UPSTREAM_BRANCH"; then
    echo "ERROR: could not fetch upstream. Check network/remote access." >&2
    exit 1
fi

# This fork's history and upstream's share no common ancestor at all (git
# itself reports "no common commits"). A real merge would therefore import
# Aurora.3's ENTIRE multi-year commit history into this repo permanently --
# every past commit and every since-superseded blob -- bloating this repo
# forever and risking a hard push failure if any historical blob ever
# exceeded GitHub's 100MB-per-file limit (plausible for years of sprites/
# maps/audio). --squash takes only the resulting tree (upstream's current
# content, -X ours conflict-resolved) as one ordinary single-parent commit,
# never touching upstream's commit graph.
#
# A squash merge never creates ancestry with upstream, this run or any
# future one, so there is no merge-base to diff against. Instead the last
# sync's own commit message carries the upstream SHA it synced to, so the
# next run can recover exactly where it left off.
LAST_SYNC_MSG="$(git log "$BASE_BRANCH" --grep='^Merge upstream Aurora\.3 \(master\) @ ' -E --pretty='%s' -n 1)"
LAST_SYNC_SHA="$(printf '%s\n' "$LAST_SYNC_MSG" | grep -oE '@ [0-9a-f]{7,40}' | head -1 | awk '{print $2}')"

git checkout -B "$SYNC_BRANCH" "$BASE_BRANCH"

echo "Merging upstream/$UPSTREAM_BRANCH into $SYNC_BRANCH (-X ours, squashed)..."
git merge -X ours --squash --no-commit --allow-unrelated-histories "upstream/$UPSTREAM_BRANCH"
MERGE_STATUS=$?

UNRESOLVED="$(git diff --name-only --diff-filter=U 2>/dev/null || true)"

UPSTREAM_SHA="$(git rev-parse upstream/"$UPSTREAM_BRANCH")"

# Every upstream commit this sync is pulling in, oldest first, by subject --
# not a count -- except on the very first sync ever (no prior marker commit
# to diff from), where it's genuinely all of upstream's history, so the list
# is capped for a readable PR body instead of dumping years of commits.
if [ -n "$LAST_SYNC_SHA" ]; then
    INCOMING_RANGE="${LAST_SYNC_SHA}..upstream/${UPSTREAM_BRANCH}"
else
    echo "No previous sync marker found -- this is the first sync, every upstream commit is 'incoming'."
    INCOMING_RANGE="upstream/${UPSTREAM_BRANCH}"
fi
INCOMING_COUNT="$(git rev-list --count "$INCOMING_RANGE")"
INCOMING_COMMITS_FULL="$(git log --reverse --pretty='- %h %s (%an)' "$INCOMING_RANGE")"
INCOMING_CAP=300
if [ "$INCOMING_COUNT" -gt "$INCOMING_CAP" ]; then
    INCOMING_COMMITS="(showing the most recent $INCOMING_CAP of $INCOMING_COUNT -- older commits are omitted so this stays readable)
$(printf '%s\n' "$INCOMING_COMMITS_FULL" | tail -n "$INCOMING_CAP")"
else
    INCOMING_COMMITS="$INCOMING_COMMITS_FULL"
fi

{
    echo "# Upstream sync -- Aurorastation/Aurora.3 ($UPSTREAM_BRANCH)"
    echo ""
    echo "Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "Base branch: \`$BASE_BRANCH\`"
    echo ""
    echo "## Incoming upstream commits ($INCOMING_COUNT)"
    echo ""
    if [ -n "$INCOMING_COMMITS" ]; then
        echo "$INCOMING_COMMITS"
    else
        echo "(none)"
    fi
    echo ""
} > "$SUMMARY"

if [ -n "$UNRESOLVED" ]; then
    {
        echo "## :warning: Structural conflicts -- \`-X ours\` could NOT auto-resolve these"
        echo ""
        echo "These need a human. Conflict markers are committed as-is on \`$SYNC_BRANCH\` so this is reviewable/pushable; resolve by hand, re-commit, then compile-check before merging."
        echo ""
        while IFS= read -r f; do echo "- \`$f\`"; done <<< "$UNRESOLVED"
        echo ""
    } >> "$SUMMARY"
    git add -A
    git commit -m "Merge upstream Aurora.3 (master) @ ${UPSTREAM_SHA} -- squashed, UNRESOLVED structural conflicts, see summary" >/dev/null
    echo ""
    cat "$SUMMARY"
    exit 2
fi

if [ "$MERGE_STATUS" -ne 0 ]; then
    echo "Merge failed for a reason other than an ordinary resolvable conflict -- check the output above." >&2
    git merge --abort 2>/dev/null
    git checkout "$BASE_BRANCH"
    git branch -D "$SYNC_BRANCH" >/dev/null 2>&1
    rm -f "$SUMMARY"
    exit "$MERGE_STATUS"
fi

git commit -m "Merge upstream Aurora.3 (master) @ ${UPSTREAM_SHA} -- squashed, conflicts resolved in favor of this fork" >/dev/null 2>&1

# No-op check: did this merge actually change anything relative to the
# branch we started from? Avoids leaving a dangling branch or (for the
# scheduled workflow) opening/updating an empty PR when upstream had
# nothing new.
if git diff --quiet "$BASE_BRANCH" "$SYNC_BRANCH"; then
    echo ""
    echo "Up to date -- upstream had nothing new to bring in. Nothing to review."
    git checkout "$BASE_BRANCH"
    git branch -D "$SYNC_BRANCH" >/dev/null 2>&1
    rm -f "$SUMMARY"
    exit 0
fi

CHANGED_FILES_FULL="$(git diff --name-status "$BASE_BRANCH" "$SYNC_BRANCH")"
FILE_COUNT="$(git diff --name-only "$BASE_BRANCH" "$SYNC_BRANCH" | wc -l | tr -d ' ')"
FILE_CAP=500
if [ "$FILE_COUNT" -gt "$FILE_CAP" ]; then
    CHANGED_FILES="(showing the first $FILE_CAP of $FILE_COUNT -- the rest are omitted so this stays readable)
$(printf '%s\n' "$CHANGED_FILES_FULL" | head -n "$FILE_CAP")"
else
    CHANGED_FILES="$CHANGED_FILES_FULL"
fi

{
    echo "## Files changed vs \`$BASE_BRANCH\` ($FILE_COUNT)"
    echo ""
    echo '```'
    echo "$CHANGED_FILES"
    echo '```'
    echo ""
    echo "## Next steps"
    echo ""
    echo "1. Review the diff on \`$SYNC_BRANCH\`."
    echo "2. Run \`scripts\\debug-compile.ps1 -ReportOnly\` -- 0 errors/warnings required."
    echo "3. Merge \`$SYNC_BRANCH\` into \`$BASE_BRANCH\` yourself. Nothing here does that automatically."
} >> "$SUMMARY"

echo ""
echo "=== Sync complete on branch '$SYNC_BRANCH' ==="
cat "$SUMMARY"
exit 0
