#!/usr/bin/env bash
# Land the current branch's PR end to end:
#   1. Refuse detached HEAD / the default branch / a closed-unmerged PR.
#   2. Create the PR if none exists (repo's own `pr-create` script if it has one).
#   3. Rebase onto the PR's base branch and force-push, so the head is current
#      with a linear history (auto-merge stalls on a BEHIND branch when the repo
#      requires up-to-date branches and forbids merge commits).
#   4. Enable auto-merge (`gh pr merge --merge --auto`, falling back to --squash).
#   5. Poll until the PR merges. Exit 1 on CI failure, a conflict with the base, a
#      closed PR, or timeout - and re-rebase whenever the base moves under us.
#
# The loop reads `mergeStateStatus` alongside the state, because that is the field
# which says "this will never merge on its own": DIRTY is a conflict with the base,
# and BEHIND means the base moved, which holds auto-merge forever in a repo that
# requires up-to-date branches. Watching only the PR state and the check
# conclusions cannot see either.
#
# Every non-merge exit prints the check tally, so "timed out" says which check was
# still pending - or that a required check was never created at all. An absent
# check is otherwise indistinguishable from a slow one, and a run-level
# `startup_failure` never reaches a check's own conclusion, so the tally is the
# only place either shows up.
#
# Tunable via env: PR_LAND_POLL_INTERVAL (default 3s), PR_LAND_TIMEOUT (default
# 1800s), PR_LAND_MAX_REBASES (default 5).
set -euo pipefail

POLL_INTERVAL="${PR_LAND_POLL_INTERVAL:-3}"
TIMEOUT="${PR_LAND_TIMEOUT:-1800}"
MAX_REBASES="${PR_LAND_MAX_REBASES:-5}"

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

# rebase_onto_base rebases and force-pushes, returning non-zero on a conflict so
# the caller can report it. Also the BEHIND path's recovery, hence a function:
# once is not enough when the base moves mid-poll.
rebase_onto_base() {
  echo "Rebasing '$branch' onto origin/$base..." >&2
  git fetch origin "$base"
  if ! git rebase "origin/$base"; then
    git rebase --abort 2>/dev/null || true
    return 1
  fi
  # --force-with-lease refuses if someone else pushed to the branch since our last
  # fetch, so we never clobber unseen commits.
  echo "Pushing rebased '$branch' (force-with-lease)..." >&2
  git push --force-with-lease origin "$branch"
}

if ! rebase_onto_base; then
  echo "error: rebase of '$branch' onto origin/$base hit conflicts - resolve manually, then re-run" >&2
  exit 1
fi

echo "Enabling auto-merge for '$branch'..." >&2
if ! gh pr merge --merge --auto; then
  echo "warning: '--merge' was rejected (already enabled, or merge commits are forbidden); trying --squash" >&2
  gh pr merge --squash --auto || echo "warning: enabling auto-merge failed; polling anyway" >&2
fi

# One `gh pr view` per cycle carries every predicate, as four fields: state,
# mergeStateStatus, the names of any conclusively-failed checks, and the tally of
# them all. `gh --jq` is gh's own jq, so this needs no jq binary.
#
# The separator is the ASCII unit separator rather than a tab, because tab is an
# IFS *whitespace* character: bash collapses a run of them into one delimiter, so
# an empty failed-checks field would silently shift the tally into it.
#
# A check's verdict is read from `conclusion` (a CheckRun) or `state` (a
# StatusContext), whichever it carries. Only conclusive verdicts count as failure
# - a pending or queued check has none yet, and `gh pr checks`' exit code is not
# used at all, because it cannot distinguish "CI failed" from "gh could not reach
# GitHub".
# shellcheck disable=SC2016  # \(...) are jq interpolations, not shell expansions
poll_jq='
  [ .state,
    (.mergeStateStatus // "UNKNOWN"),
    ([ .statusCheckRollup[]?
       | (.conclusion // .state // "") as $c
       | select(["FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE","ERROR"] | index($c))
       | (.name // .context) ] | join(",")),
    ([ .statusCheckRollup[]?
       | . as $c
       | (if ($c.conclusion // "") != "" then $c.conclusion
          elif ($c.state // "") != "" then $c.state
          else "-" end) as $verdict
       | "\($c.name // $c.context)=\($c.status // "-")/\($verdict)" ] | join(" "))
  ] | join("\u001f")'

echo "Polling every ${POLL_INTERVAL}s for merge (timeout ${TIMEOUT}s)..." >&2
deadline=$(( $(date +%s) + TIMEOUT ))
rebases=0
api_fails=0
tally=""
while true; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    if [ "$api_fails" -gt 0 ]; then
      echo "error: timed out after ${TIMEOUT}s - gh could not reach GitHub on the last ${api_fails} poll(s)" >&2
    else
      echo "error: timed out after ${TIMEOUT}s waiting for '$branch' to merge" >&2
      echo "  checks: ${tally:-(none reported)}" >&2
    fi
    exit 1
  fi

  # Empty output means gh could not reach GitHub. That is a transient fault, never
  # a verdict about the PR, so it is retried until the deadline rather than
  # reported as a failure - one dropped packet must not end the watch.
  view="$(gh pr view --json state,mergeStateStatus,statusCheckRollup --jq "$poll_jq" 2>/dev/null || true)"
  if [ -z "$view" ]; then
    api_fails=$(( api_fails + 1 ))
    [ $(( api_fails % 10 )) -eq 0 ] &&
      echo "warning: gh unreachable for ${api_fails} consecutive polls; still retrying" >&2
    sleep "$POLL_INTERVAL"
    continue
  fi
  api_fails=0
  IFS=$'\x1f' read -r state merge failed tally <<<"$view"

  if [ "$state" = "MERGED" ]; then
    echo "PR for '$branch' merged." >&2
    exit 0
  fi
  if [ "$state" = "CLOSED" ]; then
    echo "error: PR for '$branch' was closed without merging" >&2
    echo "  checks: ${tally:-(none reported)}" >&2
    exit 1
  fi

  if [ -n "$failed" ]; then
    echo "error: CI checks failed for '$branch': $failed" >&2
    echo "  checks: $tally" >&2
    exit 1
  fi

  case "$merge" in
    DIRTY)
      echo "error: '$branch' conflicts with origin/$base - resolve manually, then re-run" >&2
      echo "  checks: ${tally:-(none reported)}" >&2
      exit 1
      ;;
    BEHIND)
      # The base moved. Auto-merge stays enabled across a force-push, but it will
      # never fire while the branch is behind and the repo requires up-to-date
      # branches - so rebase again and let CI re-run.
      if [ "$rebases" -ge "$MAX_REBASES" ]; then
        echo "error: '$branch' fell behind origin/$base ${rebases} times - base moves faster than CI completes" >&2
        echo "  checks: ${tally:-(none reported)}" >&2
        exit 1
      fi
      rebases=$(( rebases + 1 ))
      echo "'$branch' is behind origin/$base - rebasing again (${rebases}/${MAX_REBASES})..." >&2
      if ! rebase_onto_base; then
        echo "error: re-rebase of '$branch' onto origin/$base hit conflicts - resolve manually, then re-run" >&2
        exit 1
      fi
      ;;
  esac

  sleep "$POLL_INTERVAL"
done
