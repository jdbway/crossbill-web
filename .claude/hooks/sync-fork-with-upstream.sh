#!/bin/bash
# SessionStart hook: keeps this fork's `main` from silently drifting behind
# Crossbill-App/crossbill-web. Any new branch cut from `main` should always
# start from real upstream content, not a stale copy sitting in the fork.
#
# `main` can carry commits upstream will never have (this hook's own setup
# commit, for instance) - that's not a conflict, just fork-local tooling, and
# gets folded in with an ordinary merge. Only a genuine conflict (upstream
# and the fork both changed the same thing) is refused: the merge is
# aborted and this fails loudly instead of guessing.
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

LOCAL_SHA="$(git rev-parse "$LOCAL_BRANCH")"
UPSTREAM_SHA="$(git rev-parse "upstream/$UPSTREAM_BRANCH")"

if [ "$LOCAL_SHA" = "$UPSTREAM_SHA" ]; then
  echo "Fork's $LOCAL_BRANCH is already in sync with upstream/$UPSTREAM_BRANCH."
  exit 0
fi

if git merge-base --is-ancestor "upstream/$UPSTREAM_BRANCH" "$LOCAL_BRANCH"; then
  # Every upstream commit is already in main - main is only ahead by its own
  # fork-local commits (or is already caught up). Nothing to pull in.
  echo "Fork's $LOCAL_BRANCH already contains everything on upstream/$UPSTREAM_BRANCH."
  exit 0
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "WARNING: uncommitted changes present - skipping the automatic $LOCAL_BRANCH sync rather than switching branches out from under them. Sync it manually once your working tree is clean." >&2
  exit 0
fi

if [ "$CURRENT_BRANCH" != "$LOCAL_BRANCH" ]; then
  git checkout --quiet "$LOCAL_BRANCH"
fi

restore_branch() {
  if [ "$CURRENT_BRANCH" != "$LOCAL_BRANCH" ]; then
    git checkout --quiet "$CURRENT_BRANCH"
  fi
}

if git merge-base --is-ancestor "$LOCAL_BRANCH" "upstream/$UPSTREAM_BRANCH"; then
  # Plain staleness: main has nothing upstream doesn't have. Fast-forward.
  git merge --ff-only "upstream/$UPSTREAM_BRANCH" --quiet
  echo "Fast-forwarded fork's $LOCAL_BRANCH to upstream/$UPSTREAM_BRANCH ($(git rev-parse --short "upstream/$UPSTREAM_BRANCH"))."
else
  # Both sides have commits the other lacks (e.g. fork-local tooling commits
  # plus new upstream commits). Try an ordinary merge; only a real content
  # conflict should block this.
  if git merge "upstream/$UPSTREAM_BRANCH" --no-edit --quiet; then
    echo "Merged upstream/$UPSTREAM_BRANCH into fork's $LOCAL_BRANCH ($(git rev-parse --short "$LOCAL_BRANCH"))."
  else
    git merge --abort
    restore_branch
    cat >&2 <<EOF
ERROR: merging upstream/$UPSTREAM_BRANCH into '$LOCAL_BRANCH' produced real
conflicts - upstream and the fork changed the same content. Merge aborted;
'$LOCAL_BRANCH' is untouched. Resolve this manually before branching new
work from it.
EOF
    exit 1
  fi
fi

if git push origin "$LOCAL_BRANCH" --quiet 2>/dev/null; then
  echo "Pushed updated $LOCAL_BRANCH to origin."
else
  echo "NOTE: could not push updated $LOCAL_BRANCH to origin (no push access in this session, or a network issue). Local $LOCAL_BRANCH is caught up regardless; the remote fork's $LOCAL_BRANCH page may still show as behind until this is pushed." >&2
fi

restore_branch
