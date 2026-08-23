#!/bin/bash
# SessionStart hook: keeps this fork's `main` from silently drifting behind
# Crossbill-App/crossbill-web. Any new branch cut from `main` should always
# start from real upstream content, not a stale copy sitting in the fork.
#
# Safe by construction: it only ever fast-forwards. If local `main` carries
# commits upstream doesn't have (a genuine divergence), it refuses to touch
# `main` and fails loudly instead of guessing.
set -euo pipefail

UPSTREAM_URL="https://github.com/Crossbill-App/crossbill-web.git"
UPSTREAM_BRANCH="main"
LOCAL_BRANCH="main"

cd "$CLAUDE_PROJECT_DIR"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
fi

if ! git fetch upstream "$UPSTREAM_BRANCH" --quiet; then
  echo "WARNING: could not fetch $UPSTREAM_URL ($UPSTREAM_BRANCH). New branches may start from a stale base until this succeeds." >&2
  exit 0
fi

if ! git show-ref --verify --quiet "refs/heads/$LOCAL_BRANCH"; then
  # No local main yet (fresh clone in a session already on a feature branch) -
  # nothing to reconcile.
  exit 0
fi

if [ "$(git rev-parse "$LOCAL_BRANCH")" = "$(git rev-parse "upstream/$UPSTREAM_BRANCH")" ]; then
  echo "Fork's $LOCAL_BRANCH is already in sync with upstream/$UPSTREAM_BRANCH."
  exit 0
fi

if ! git merge-base --is-ancestor "$LOCAL_BRANCH" "upstream/$UPSTREAM_BRANCH"; then
  cat >&2 <<EOF
ERROR: fork's '$LOCAL_BRANCH' has commits that upstream/$UPSTREAM_BRANCH does
not have - this is a real divergence, not simple staleness. Refusing to
touch '$LOCAL_BRANCH' automatically. Resolve this manually (e.g. rebase or
merge) before branching new work from it.
EOF
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [ "$CURRENT_BRANCH" = "$LOCAL_BRANCH" ]; then
  git merge --ff-only "upstream/$UPSTREAM_BRANCH"
else
  # main isn't checked out (a session usually starts on a feature branch) -
  # move the ref directly without touching the working tree.
  git update-ref "refs/heads/$LOCAL_BRANCH" "refs/remotes/upstream/$UPSTREAM_BRANCH"
fi

echo "Fast-forwarded fork's $LOCAL_BRANCH to upstream/$UPSTREAM_BRANCH ($(git rev-parse --short "upstream/$UPSTREAM_BRANCH"))."

if git push origin "$LOCAL_BRANCH" --quiet 2>/dev/null; then
  echo "Pushed updated $LOCAL_BRANCH to origin."
else
  echo "NOTE: could not push updated $LOCAL_BRANCH to origin (no push access in this session, or a network issue). Local $LOCAL_BRANCH is caught up regardless; the remote fork's $LOCAL_BRANCH page may still show as behind until this is pushed." >&2
fi
