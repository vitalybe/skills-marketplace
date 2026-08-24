#!/usr/bin/env bash
# Land the current branch's PR end to end:
#   1. Refuse detached HEAD / the default branch / a closed-unmerged PR.
#   2. Create the PR if none exists (repo's own `pr-create` script if it has one).
#   3. Rebase onto the PR's base branch and force-push, so the head is current
#      with a linear history (auto-merge stalls on a BEHIND branch when the repo
#      requires up-to-date branches and forbids merge commits).
#   4. Enable auto-merge (`gh pr merge --merge --auto`, falling back to --squash).
#   5. Poll until the PR merges. Exit 1 on CI failure, a closed PR, or timeout.
#
# Tunable via env: PR_LAND_POLL_INTERVAL (default 3s), PR_LAND_TIMEOUT (default 1800s).
set -euo pipefail

POLL_INTERVAL="${PR_LAND_POLL_INTERVAL:-3}"
TIMEOUT="${PR_LAND_TIMEOUT:-1800}"

cd "$(git rev-parse --show-toplevel)"

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "HEAD" ]; then
  echo "error: detached HEAD - checkout a branch first" >&2
  exit 1
fi

default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)"
if [ "$branch" = "$default_branch" ]; then
  echo "error: refusing to self-merge from '$branch' (the default branch)" >&2
  exit 1
fi

# pr_state echoes OPEN / MERGED / CLOSED for the current branch's PR, or empty
# when no PR exists yet.
pr_state() {
  gh pr view --json state --jq .state 2>/dev/null || true
}

state="$(pr_state)"
if [ "$state" = "CLOSED" ]; then
  echo "error: PR for '$branch' is closed (not merged); reopen it manually" >&2
  exit 1
fi

# Create the PR if there isn't one. Prefer the repo's own pr-create script -
# it usually fills a body the way that repo wants.
if [ -z "$state" ] || [ "$state" = "MERGED" ]; then
  echo "No PR for '$branch' yet - creating..." >&2
  if [ -f package.json ] && grep -q '"pr-create"' package.json; then
    pnpm run pr-create
  else
    git push -u origin "$branch"
    gh pr create --fill
  fi
fi

base="$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null || true)"
[ -n "$base" ] || base="$default_branch"

echo "Rebasing '$branch' onto origin/$base..." >&2
git fetch origin "$base"
if ! git rebase "origin/$base"; then
  git rebase --abort 2>/dev/null || true
  echo "error: rebase of '$branch' onto origin/$base hit conflicts - resolve manually, then re-run" >&2
  exit 1
fi
# --force-with-lease refuses if someone else pushed to the branch since our last
# fetch, so we never clobber unseen commits.
echo "Pushing rebased '$branch' (force-with-lease)..." >&2
git push --force-with-lease origin "$branch"

echo "Enabling auto-merge for '$branch'..." >&2
if ! gh pr merge --merge --auto; then
  echo "warning: '--merge' was rejected (already enabled, or merge commits are forbidden); trying --squash" >&2
  gh pr merge --squash --auto || echo "warning: enabling auto-merge failed; polling anyway" >&2
fi

echo "Polling every ${POLL_INTERVAL}s for merge (timeout ${TIMEOUT}s)..." >&2
deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  state="$(pr_state)"
  if [ "$state" = "MERGED" ]; then
    echo "PR for '$branch' merged." >&2
    exit 0
  fi
  if [ "$state" = "CLOSED" ]; then
    echo "error: PR for '$branch' was closed without merging" >&2
    exit 1
  fi

  # `gh pr checks` exit codes: 0 = all passed, 8 = pending, other = failure
  # (or "no checks reported", handled below).
  set +e
  checks_out="$(gh pr checks 2>&1)"
  checks_rc=$?
  set -e
  case "$checks_rc" in
    0 | 8) : ;;
    *)
      if printf '%s' "$checks_out" | grep -qi "no checks reported"; then
        : # no CI configured - auto-merge will complete shortly
      else
        echo "error: CI checks failed for '$branch':" >&2
        printf '%s\n' "$checks_out" >&2
        exit 1
      fi
      ;;
  esac

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "error: timed out after ${TIMEOUT}s waiting for '$branch' to merge" >&2
    exit 1
  fi
  sleep "$POLL_INTERVAL"
done
