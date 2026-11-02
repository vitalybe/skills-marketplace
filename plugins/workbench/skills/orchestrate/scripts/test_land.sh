#!/usr/bin/env bash
# Purpose: self-contained test of scripts/land against throwaway git repos in a temp directory.
set -uo pipefail

LAND="$(cd "$(dirname "$0")" && pwd)/land"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fails=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

printf 'msg\n\nCo-Authored-By: Claude\n' > "$T/good.md"
printf 'msg\n' > "$T/nocoauthor.md"

# fresh <name>: repo at $T/<name>/main with worktree $T/<name>/wt on branch feat (one commit).
fresh() {
  R="$T/$1"; mkdir -p "$R"; M="$R/main"; W="$R/wt"
  git init -q -b main "$M"
  git -C "$M" commit -q --allow-empty -m init
  echo base > "$M/f.txt"; echo x > "$M/g.txt"; git -C "$M" add .; git -C "$M" commit -q -m base
  git -C "$M" worktree add -q "$W" -b feat
  echo feat > "$W/new.txt"; git -C "$W" add .; git -C "$W" commit -q -m feat
}
land() { (cd "$W" && LAND_TEST_CMD="${LAND_TEST_CMD:-true}" "$LAND" "$@") > "$R/out" 2>&1; }

# success, also with main having moved ahead
fresh ok; echo more > "$M/m.txt"; git -C "$M" add .; git -C "$M" commit -q -m ahead
land --message-file "$T/good.md"; rc=$?
check "success exit 0" "[ $rc = 0 ]"
check "success worktree removed" "[ ! -d '$W' ]"
check "success branch deleted" "! git -C '$M' show-ref -q refs/heads/feat"
check "success merge commit has 2 parents and message" "[ \$(git -C '$M' rev-list --parents -n1 HEAD | wc -w) = 3 ] && git -C '$M' log -1 --format=%B | rg -q 'Co-Authored-By: Claude'"
check "success file landed" "[ -f '$M/new.txt' ]"

# by branch name from main checkout
fresh byname; (cd "$M" && LAND_TEST_CMD=true "$LAND" --message-file "$T/good.md" feat) > "$R/out" 2>&1
check "land by branch name" "[ ! -d '$W' ] && [ -f '$M/new.txt' ]"

# dirty worktree
fresh dirtywt; echo d >> "$W/f.txt"; land --message-file "$T/good.md"; rc=$?
check "dirty worktree refused" "[ $rc != 0 ] && [ -d '$W' ] && rg -q 'uncommitted' '$R/out'"

# dirty main (tracked), untracked ignored
fresh dirtymain; echo d >> "$M/f.txt"; land --message-file "$T/good.md"; rc=$?
check "dirty main refused" "[ $rc != 0 ] && [ -d '$W' ] && rg -q 'main checkout has uncommitted' '$R/out'"
fresh untracked; echo u > "$M/untracked.txt"; land --message-file "$T/good.md"; rc=$?
check "untracked in main ignored" "[ $rc = 0 ]"

# main not on default branch
fresh offdef; git -C "$M" switch -q -c other; land --into main --message-file "$T/good.md"; rc=$?
check "main off default refused" "[ $rc != 0 ] && [ -d '$W' ]"

# non-main target
fresh tgt; git -C "$M" switch -q -c orch; echo o > "$M/o.txt"; git -C "$M" add .; git -C "$M" commit -q -m orch
land --into orch --message-file "$T/good.md"; rc=$?
check "non-main target lands" "[ $rc = 0 ] && [ -f '$M/new.txt' ] && [ -f '$M/o.txt' ] && [ \"\$(git -C '$M' branch --show-current)\" = orch ]"
fresh tgt2; git -C "$M" switch -q -c orch; land --message-file "$T/good.md"; rc=$?
check "default target is the main checkout branch" "[ $rc = 0 ] && git -C '$M' log -1 --format=%B | rg -q Co-Authored"
fresh tgt3; git -C "$M" switch -q -c orch; land --into main --message-file "$T/good.md"; rc=$?
check "checkout on a different branch than --into refused" "[ $rc != 0 ] && [ -d '$W' ] && rg -q 'not on target' '$R/out'"
fresh tgt4; land --into nosuch --message-file "$T/good.md"; rc=$?
check "missing target branch refused" "[ $rc != 0 ] && [ -d '$W' ]"
fresh tgt5; land --into feat --message-file "$T/good.md"; rc=$?
check "worker branch as target refused" "[ $rc != 0 ] && [ -d '$W' ]"

# default branch refused
fresh onmain; (cd "$M" && LAND_TEST_CMD=true "$LAND" --message-file "$T/good.md") > "$R/out" 2>&1; rc=$?
check "run from main checkout refused" "[ $rc != 0 ]"

# conflict
fresh conflict; echo A > "$M/f.txt"; git -C "$M" commit -q -am mainedit
echo B > "$W/f.txt"; git -C "$W" commit -q -am wtedit
before="$(git -C "$M" rev-parse HEAD)"
land --message-file "$T/good.md"; rc=$?
check "conflict exit non-zero, lists file, worktree kept, main untouched" "[ $rc != 0 ] && rg -q 'f.txt' '$R/out' && [ -d '$W' ] && [ \"\$(git -C '$M' rev-parse HEAD)\" = $before ] && git -C '$W' status | rg -q 'unmerged|Unmerged'"

# failing test, no retry success
fresh failtest; before="$(git -C "$M" rev-parse HEAD)"
LAND_TEST_CMD=false land --message-file "$T/good.md"; rc=$?
check "failing test refused, retried, main untouched" "[ $rc != 0 ] && rg -q 'retrying once' '$R/out' && [ -d '$W' ] && [ \"\$(git -C '$M' rev-parse HEAD)\" = $before ]"

# flaky test passes on retry
fresh flaky; flag="$R/flag"
LAND_TEST_CMD="if [ -e '$flag' ]; then exit 0; else touch '$flag'; exit 1; fi" land --message-file "$T/good.md"; rc=$?
check "flaky test passes on retry" "[ $rc = 0 ] && rg -q 'passed on the retry' '$R/out'"

# --no-test skips the failing command
fresh notest; LAND_TEST_CMD=false land --no-test --message-file "$T/good.md"; rc=$?
check "--no-test skips tests" "[ $rc = 0 ]"

# locked worktree (harness lock): merge lands, worktree and branch kept, exit 0
fresh locked; git -C "$M" worktree lock "$W"; land --message-file "$T/good.md"; rc=$?
check "locked worktree: exit 0, merged, worktree and branch kept, message printed" "[ $rc = 0 ] && [ -f '$M/new.txt' ] && [ -d '$W' ] && git -C '$M' show-ref -q refs/heads/feat && rg -q 'locked by the harness.*git worktree unlock' '$R/out'"

# message file problems
fresh nomsg; land --message-file "$T/missing.md"; rc=$?
check "missing message file" "[ $rc != 0 ] && [ -d '$W' ]"
fresh nomsgarg; land; rc=$?
check "no --message-file" "[ $rc != 0 ] && [ -d '$W' ]"
fresh noco; land --message-file "$T/nocoauthor.md"; rc=$?
check "missing Co-Authored-By" "[ $rc != 0 ] && [ -d '$W' ] && rg -q 'Co-Authored-By' '$R/out'"

echo; [ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
