#!/bin/bash
# Acceptance checks for TASK_08 (OSV batch query, spec Sections 4.2, 4.3, and 2.4).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/osv_test.sh
# No test makes a network call. osv_http_post is replaced by a fake that returns recorded
# responses from tests/fixtures/osv/.

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
FIX=$ROOT/tests/fixtures/osv
SCA=$ROOT/tests/fixtures/sca
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# scan <case dir> <target dir> [env]: runs one lookup in a fresh shell. The fake HTTP function
# reads $case/resp.N (and optional $case/code.N, $case/curlfail) for call N, and records each
# request body as $case/req.N. Prints RC, the error message, the call count, and the findings.
scan() {
  local case=$1 target=$2
  mkdir -p "$case"
  /bin/bash -c '
    . "$1/lib/traverse.sh"; . "$1/lib/classify.sh"; . "$1/lib/sca.sh"
    . "$1/lib/severity.sh"; . "$1/lib/report.sh"; . "$1/lib/osv.sh"
    CASE=$2
    CLI_OFFLINE=$4
    OSV_BATCH_SIZE=$5
    osv_http_post() {
      local n=0
      [ -f "$CASE/calls" ] && n=$(cat "$CASE/calls")
      n=$((n + 1)); echo "$n" > "$CASE/calls"
      cp "$1" "$CASE/req.$n"
      [ -f "$CASE/curlfail" ] && return 1
      OSV_HTTP_CODE=$(cat "$CASE/code.$n" 2>/dev/null || echo 200)
      cp "$CASE/resp.$n" "$2"
      return 0
    }
    # Advisory details: $CASE/vuln.<id>.json when recorded, otherwise HTTP 404.
    osv_http_get() {
      local id=${1##*/}
      [ -f "$CASE/getfail" ] && return 1
      if [ -f "$CASE/vuln.$id.json" ]; then
        OSV_HTTP_CODE=200
        cp "$CASE/vuln.$id.json" "$2"
      else
        OSV_HTTP_CODE=404
        : > "$2"
      fi
      return 0
    }
    traverse_target "$3"; classify_target; sca_parse_target
    osv_scan
    echo "RC=$?"
    echo "ERR=$OSV_ERROR"
    echo "CALLS=$(cat "$CASE/calls" 2>/dev/null || echo 0)"
    for i in "${!FINDING_CATEGORY[@]}"; do
      echo "F ${FINDING_CATEGORY[$i]} ${FINDING_SEVERITY[$i]} ${FINDING_FILE[$i]}"
      echo "D ${FINDING_DESCRIPTION[$i]}"
    done' _ "$ROOT" "$case" "$target" "${TEST_OFFLINE:-0}" "${TEST_BATCH:-100}"
}

# check <name> <got> <want>
check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    echo "    got:  [$2]"
    echo "    want: [$3]"
  fi
}

# has <name> <output> <pattern>: passes when the output contains the fixed text.
has() {
  case $2 in
    *"$3"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL: $1"; echo "    output: [$2]"; echo "    missing: [$3]" ;;
  esac
}

# npm-no-lock has one pinned tuple (lodash 4.17.20) and a package.json with no lock file.
NPM=$SCA/npm-no-lock
# pipfile has two tuples (pytest 7.4.0, requests 2.28.1), so it can show batching and paging.
PIP=$SCA/pipfile

# --offline: no request is made, and no missing-lock finding is produced (spec 8.2).
out=$(TEST_OFFLINE=1 scan "$WORK/offline" "$NPM")
check "offline makes no request" "$(cat "$WORK/offline/calls" 2>/dev/null || echo none)" "none"
check "offline returns 0 with no findings" "$out" "RC=0
ERR=
CALLS=0"

# A clean response: exit 0, one request carrying only name, ecosystem, and version (spec 2.3).
mkdir -p "$WORK/clean" && cp "$FIX/clean-1.json" "$WORK/clean/resp.1"
out=$(scan "$WORK/clean" "$NPM")
check "clean response exits 0" "$(echo "$out" | sed -n 1p)" "RC=0"
check "request has only name, ecosystem, and version" "$(jq -c . "$WORK/clean/req.1")" \
  '{"queries":[{"package":{"name":"lodash","ecosystem":"npm"},"version":"4.17.20"}]}'
check "clean response reports only the missing lock file" "$(echo "$out" | grep '^F ')" \
  "F MISSING_LOCKFILE LOW package.json"

# A matched advisory takes its severity from its CVSS v3 base score (item 64). 9.8 is CRITICAL.
mkdir -p "$WORK/critical" && cp "$FIX/match-1.json" "$WORK/critical/resp.1"
cp "$FIX/vuln-critical.json" "$WORK/critical/vuln.GHSA-fake-0001.json"
out=$(scan "$WORK/critical" "$NPM")
check "matched advisory exits 0" "$(echo "$out" | sed -n 1p)" "RC=0"
check "CVSS 9.8 gives a CRITICAL finding" "$(echo "$out" | grep '^F VULNERABLE')" "F VULNERABLE_DEPENDENCY CRITICAL package.json"
has "finding names package, version, ecosystem, and advisory" "$out" "lodash 4.17.20 (npm) is affected by advisory GHSA-fake-0001 (CVSS 9.8)"

# CVSS 5.3 gives MEDIUM.
mkdir -p "$WORK/medium" && cp "$FIX/match-1.json" "$WORK/medium/resp.1"
cp "$FIX/vuln-medium.json" "$WORK/medium/vuln.GHSA-fake-0001.json"
out=$(scan "$WORK/medium" "$NPM")
check "CVSS 5.3 gives a MEDIUM finding" "$(echo "$out" | grep '^F VULNERABLE')" "F VULNERABLE_DEPENDENCY MEDIUM package.json"

# An advisory with no CVSS v3 score (none recorded, or only CVSS v4) cannot be mapped, so the
# scan fails rather than guessing.
mkdir -p "$WORK/nosev" && cp "$FIX/match-1.json" "$WORK/nosev/resp.1"
cp "$FIX/vuln-no-severity.json" "$WORK/nosev/vuln.GHSA-fake-0001.json"
out=$(scan "$WORK/nosev" "$NPM")
check "no CVSS v3 score exits 1" "$(echo "$out" | sed -n 1p)" "RC=1"
has "no CVSS v3 score names item 64" "$out" "no CVSS v3 score"

mkdir -p "$WORK/v4" && cp "$FIX/match-1.json" "$WORK/v4/resp.1"
cp "$FIX/vuln-v4-only.json" "$WORK/v4/vuln.GHSA-fake-0001.json"
out=$(scan "$WORK/v4" "$NPM")
has "CVSS v4 only is reported as having no v3 score" "$out" "no CVSS v3 score"

# An advisory that cannot be fetched fails the scan (HTTP 404 here, unreachable below).
mkdir -p "$WORK/nofetch" && cp "$FIX/match-1.json" "$WORK/nofetch/resp.1"
out=$(scan "$WORK/nofetch" "$NPM")
check "advisory fetch 404 exits 1" "$(echo "$out" | sed -n 1p)" "RC=1"
has "advisory fetch 404 message" "$out" "OSV returned HTTP 404"

mkdir -p "$WORK/getfail" && cp "$FIX/match-1.json" "$WORK/getfail/resp.1" && touch "$WORK/getfail/getfail"
out=$(scan "$WORK/getfail" "$NPM")
has "advisory fetch unreachable message" "$out" "OSV is unreachable or timed out"

# Failure paths: unreachable, rate-limited, other HTTP errors, and bad responses all exit 1.
mkdir -p "$WORK/curl" && touch "$WORK/curl/curlfail"
out=$(scan "$WORK/curl" "$NPM")
check "unreachable OSV exits 1" "$(echo "$out" | sed -n 1p)" "RC=1"
has "unreachable message" "$out" "OSV is unreachable or timed out"

mkdir -p "$WORK/429" && cp "$FIX/clean-1.json" "$WORK/429/resp.1" && echo 429 > "$WORK/429/code.1"
out=$(scan "$WORK/429" "$NPM")
check "rate limit exits 1" "$(echo "$out" | sed -n 1p)" "RC=1"
has "rate limit message" "$out" "rate-limited"

mkdir -p "$WORK/500" && cp "$FIX/clean-1.json" "$WORK/500/resp.1" && echo 500 > "$WORK/500/code.1"
out=$(scan "$WORK/500" "$NPM")
has "server error message" "$out" "OSV returned HTTP 500"

mkdir -p "$WORK/junk" && echo "not json" > "$WORK/junk/resp.1"
out=$(scan "$WORK/junk" "$NPM")
check "unparseable response exits 1" "$(echo "$out" | sed -n 1p)" "RC=1"
has "unparseable message" "$out" "could not be parsed"

# Two results for one query is a mismatch, so the response is rejected.
mkdir -p "$WORK/mismatch" && cp "$FIX/clean-2.json" "$WORK/mismatch/resp.1"
out=$(scan "$WORK/mismatch" "$NPM")
has "result count mismatch is rejected" "$out" "could not be parsed"

# Paging: a next_page_token is queried again with page_token, and the second page is used.
mkdir -p "$WORK/page" && cp "$FIX/page-1.json" "$WORK/page/resp.1" && cp "$FIX/page-2.json" "$WORK/page/resp.2"
cp "$FIX/vuln-critical.json" "$WORK/page/vuln.GHSA-fake-0001.json"
cp "$FIX/vuln-high.json" "$WORK/page/vuln.GHSA-fake-0002.json"
out=$(scan "$WORK/page" "$PIP")
check "paging sends a second request" "$(cat "$WORK/page/calls")" "2"
check "second request carries the page token" "$(jq -r '.queries[0].page_token' "$WORK/page/req.2")" "tok1"
has "advisory from the second page is reached" "$out" "advisory GHSA-fake-0002 (CVSS 7.5)"
check "second-page advisory gives HIGH" "$(echo "$out" | grep -c '^F VULNERABLE_DEPENDENCY HIGH')" "1"

# Batching: with a batch size of 1, each unique tuple is sent in its own request.
mkdir -p "$WORK/batch" && cp "$FIX/clean-1.json" "$WORK/batch/resp.1" && cp "$FIX/clean-1.json" "$WORK/batch/resp.2"
out=$(TEST_BATCH=1 scan "$WORK/batch" "$PIP")
check "batch size 1 sends two requests" "$(cat "$WORK/batch/calls")" "2"
check "each batch holds one query" "$(jq '.queries | length' "$WORK/batch/req.2")" "1"
check "clean batches exit 0" "$(echo "$out" | sed -n 1p)" "RC=0"

# A directory with no manifests makes no request and exits 0 (spec 2.4).
mkdir -p "$WORK/empty-target" "$WORK/empty"
out=$(scan "$WORK/empty" "$WORK/empty-target")
check "no tuples: no request, exit 0" "$out" "RC=0
ERR=
CALLS=0"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
