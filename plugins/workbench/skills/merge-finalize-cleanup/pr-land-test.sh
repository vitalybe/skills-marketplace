#!/usr/bin/env bash
# Checks pr-land.sh's poll_jq program and the field parsing that reads it - the
# part of the loop that decides "CI failed" vs "still pending", and that must not
# let an empty field shift the others along.
#
# Runs offline against synthetic rollups (needs jq). To also probe real PRs:
#   PR_LAND_TEST_REPO=owner/repo PR_LAND_TEST_PRS="409 412" ./pr-land-test.sh
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-land.sh"
US=$'\x1f'

# Pull poll_jq out of the script itself, so the test cannot drift from it:
# everything from the poll_jq= line to the first line ending in a bare quote.
poll_jq="$(awk "/^poll_jq='/{f=1; sub(/^poll_jq='/,\"\")} f{print} f && /'\$/{exit}" "$SCRIPT" \
  | sed "s/'\$//")"
[ -n "$poll_jq" ] || { echo "FAIL: could not extract poll_jq from $SCRIPT"; exit 1; }

fail() { printf 'FAIL %s\n' "$1"; exit 1; }

if [ -n "${PR_LAND_TEST_REPO:-}" ]; then
  echo "=== live PRs (parsed exactly as the loop parses them) ==="
  for pr in ${PR_LAND_TEST_PRS:-}; do
    out="$(gh pr view "$pr" --repo "$PR_LAND_TEST_REPO" \
      --json state,mergeStateStatus,statusCheckRollup --jq "$poll_jq" 2>&1)" ||
      fail "gh failed for PR $pr: $out"
    IFS="$US" read -r state merge failed tally <<<"$out"
    printf 'PR %s: state=%s merge=%s failed=[%s]\n  tally=%s\n' \
      "$pr" "$state" "$merge" "$failed" "${tally:-(none)}"
    [ -n "$state" ] || fail "no state parsed for PR $pr"
  done
  echo
fi

echo
echo "=== synthetic rollups: does 'failed' hold only conclusive failures? ==="
run_case() {
  local name=$1 json=$2 want=$3 out failed
  out="$(printf '%s' "$json" | jq -r "$poll_jq")" || fail "$name: jq error"
  IFS="$US" read -r _ _ failed _ <<<"$out"
  [ "$failed" = "$want" ] ||
    fail "$(printf '%-34s failed=[%s] want=[%s]' "$name" "$failed" "$want")"
  printf 'ok   %-34s failed=[%s]\n' "$name" "$failed"
}

# A queued CheckRun with an empty conclusion is what a startup_failure run looks
# like from the rollup: pending, not failed. This is the case that burned 30min.
run_case "queued check, empty conclusion" \
  '{"state":"OPEN","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"name":"no-merge-commits","status":"QUEUED","conclusion":""}]}' \
  ""
run_case "no checks at all" \
  '{"state":"OPEN","mergeStateStatus":"BLOCKED","statusCheckRollup":[]}' \
  ""
run_case "CheckRun FAILURE" \
  '{"state":"OPEN","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"name":"build","status":"COMPLETED","conclusion":"FAILURE"}]}' \
  "build"
run_case "StatusContext ERROR (no conclusion)" \
  '{"state":"OPEN","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"context":"ci/legacy","state":"ERROR"}]}' \
  "ci/legacy"
run_case "success + pending mixed" \
  '{"state":"OPEN","mergeStateStatus":"BEHIND","statusCheckRollup":[{"name":"build","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"lint","status":"IN_PROGRESS","conclusion":null}]}' \
  ""
run_case "SKIPPED is not a failure" \
  '{"state":"OPEN","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"name":"close-jira","status":"COMPLETED","conclusion":"SKIPPED"}]}' \
  ""
run_case "two failures listed" \
  '{"state":"OPEN","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"name":"a","conclusion":"TIMED_OUT"},{"name":"b","conclusion":"CANCELLED"}]}' \
  "a,b"

echo
echo "=== mergeStateStatus reaches field 2, and an empty field 3 does not shift it ==="
for m in DIRTY BEHIND BLOCKED CLEAN; do
  out="$(printf '{"state":"OPEN","mergeStateStatus":"%s","statusCheckRollup":[{"name":"build","status":"QUEUED","conclusion":""}]}' "$m" | jq -r "$poll_jq")"
  IFS="$US" read -r st got fl tal <<<"$out"
  [ "$got" = "$m" ] || fail "$m: field2=$got"
  [ "$st" = "OPEN" ] || fail "$m: field1=$st"
  [ -z "$fl" ] || fail "$m: field3 should be empty, got [$fl]"
  [ "$tal" = "build=QUEUED/-" ] || fail "$m: field4=[$tal]"
  printf 'ok   %-8s state=%s failed=[] tally=%s\n' "$m" "$st" "$tal"
done

echo
echo "ALL PASS"
