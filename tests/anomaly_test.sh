#!/bin/bash
# Acceptance checks for TASK_09 (supply chain anomalies, spec Section 4.3).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/anomaly_test.sh
# No test makes a network call. popular_http_get is replaced by a fake that serves
# tests/fixtures/popular/top-sample.json, or fails when the case has a pfail file.

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
FIX=$ROOT/tests/fixtures/popular/top-sample.json
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    echo "  want: $3"
    echo "  got:  $2"
  fi
}

# has <name> <output> <text>: passes when the output contains the text.
has() {
  case $2 in
    *"$3"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL: $1"; echo "  missing: $3" ;;
  esac
}

# lacks <name> <output> <text>: passes when the output does not contain the text.
lacks() {
  case $2 in
    *"$3"*) FAIL=$((FAIL + 1)); echo "FAIL: $1"; echo "  unexpected: $3" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

# scan <case dir> <target dir>: runs the anomaly checks in a fresh shell. The case directory
# holds the cache (cache/), the call count (pcalls), and the failure switch (pfail).
# Environment: TEST_OFFLINE (0 or 1), TEST_PREFIXES (space-separated), TEST_TOPN.
# Prints RC, the error, the call count, warnings, and the findings.
scan() {
  local case=$1 target=$2
  mkdir -p "$case"
  /bin/bash -c '
    . "$1/lib/traverse.sh"; . "$1/lib/classify.sh"; . "$1/lib/sca.sh"
    . "$1/lib/severity.sh"; . "$1/lib/report.sh"; . "$1/lib/popular.sh"; . "$1/lib/anomaly.sh"
    CASE=$2
    FIXTURE=$6
    CLI_OFFLINE=$4
    CLI_INTERNAL_PREFIXES=($5)
    POPULAR_TOP_N=${TEST_TOPN:-1000}
    XDG_CACHE_HOME=$CASE/cache
    export XDG_CACHE_HOME
    popular_http_get() {
      local n=0
      [ -f "$CASE/pcalls" ] && n=$(cat "$CASE/pcalls")
      n=$((n + 1)); echo "$n" > "$CASE/pcalls"
      [ -f "$CASE/pfail" ] && return 1
      POPULAR_HTTP_CODE=200
      cp "$FIXTURE" "$2"
      return 0
    }
    traverse_target "$3"; classify_target; sca_parse_target
    anomaly_scan
    echo "RC=$?"
    echo "ERR=$ANOM_ERROR"
    echo "CALLS=$(cat "$CASE/pcalls" 2>/dev/null || echo 0)"
    for i in "${!SCA_WARN_MSG[@]}"; do echo "W ${SCA_WARN_MSG[$i]}"; done
    for i in "${!FINDING_CATEGORY[@]}"; do
      echo "F ${FINDING_CATEGORY[$i]} ${FINDING_SEVERITY[$i]} ${FINDING_FILE[$i]}"
      echo "D ${FINDING_DESCRIPTION[$i]}"
    done' _ "$ROOT" "$case" "$target" "${TEST_OFFLINE:-0}" "${TEST_PREFIXES:-}" "$FIX"
}

# Typosquat fixture: each line is one of the cases in the checks below.
mkdir -p "$WORK/typo"
cat > "$WORK/typo/requirements.txt" <<'EOF'
requets==2.31.0
requests==2.31.0
django==4.2
Python_Dateutil==2.8.2
python__dateutil==2.8.2
flasks==2.0
flaxks==1.0
sqlalchemyxy==2.0
zzqx-helper==1.0
EOF

out=$(scan "$WORK/typo/case" "$WORK/typo")
check "typo: exit 0" "$(echo "$out" | sed -n 1p)" "RC=0"
check "typo: one fetch for the PyPI list" "$(echo "$out" | sed -n 3p)" "CALLS=1"
check "typo: three typosquat findings" "$(echo "$out" | grep -c '^F TYPOSQUAT_SUSPECT HIGH requirements.txt')" "3"
has "typo: one edit from requests is flagged" "$out" "PyPI package 'requets' is close to the popular package 'requests' (possible typosquat)"
has "typo: one edit from flask (5 chars) is flagged" "$out" "PyPI package 'flasks' is close to the popular package 'flask'"
has "typo: two edits from a 12-char name is flagged" "$out" "PyPI package 'sqlalchemyxy' is close to the popular package 'sqlalchemy'"
lacks "typo: two edits from a short name (flask) is not flagged" "$out" "'flaxks'"
lacks "typo: a name on the list is not flagged" "$out" "PyPI package 'requests'"
lacks "typo: a name on the list is not flagged (django)" "$out" "PyPI package 'django'"
lacks "typo: a name that matches after normalization is not flagged" "$out" "'Python_Dateutil'"
lacks "typo: a run of separators is one separator (python__dateutil)" "$out" "'python__dateutil'"
lacks "typo: an unrelated name is not flagged" "$out" "'zzqx-helper'"

# A transposition of two adjacent letters is one edit (Damerau). "flaks" is two substitutions
# from "flask" without it, and the short name only allows one edit.
mkdir -p "$WORK/transpose"
echo "flaks==1.0" > "$WORK/transpose/requirements.txt"
out=$(scan "$WORK/transpose/case" "$WORK/transpose")
check "transposition: one finding" "$(echo "$out" | grep -c '^F TYPOSQUAT_SUSPECT')" "1"
has "transposition: names the closest package" "$out" "popular package 'flask'"

# npm dependencies are not checked for typosquats, and no PyPI dependency means no request.
mkdir -p "$WORK/npm-only"
cat > "$WORK/npm-only/package-lock.json" <<'EOF'
{"name":"app","lockfileVersion":3,"requires":true,"packages":{"":{"name":"app"},"node_modules/lodahs":{"version":"1.0.0"}}}
EOF
out=$(scan "$WORK/npm-only/case" "$WORK/npm-only")
check "no PyPI dependency: no request" "$(echo "$out" | sed -n 3p)" "CALLS=0"
check "no PyPI dependency: no findings" "$(echo "$out" | grep -c '^F ')" "0"

# A fresh cache is reused: the second scan makes no request.
out1=$(scan "$WORK/typo/cache-case" "$WORK/typo")
out2=$(scan "$WORK/typo/cache-case" "$WORK/typo")
check "cache: first scan fetches" "$(echo "$out1" | sed -n 3p)" "CALLS=1"
check "cache: second scan makes no request" "$(echo "$out2" | sed -n 3p)" "CALLS=1"
check "cache: second scan finds the same typosquats" "$(echo "$out2" | grep -c '^F TYPOSQUAT_SUSPECT')" "3"
check "cache: file holds the list, most downloaded first" "$(head -1 "$WORK/typo/cache-case/cache/repo-shield/pypi-top-1000.txt")" "numpy"

# An expired cache (older than 4 hours) is fetched again.
touch -t 202001010000 "$WORK/typo/cache-case/cache/repo-shield/pypi-top-1000.txt"
out3=$(scan "$WORK/typo/cache-case" "$WORK/typo")
check "expired cache: fetched again" "$(echo "$out3" | sed -n 3p)" "CALLS=2"

# Offline with a fresh cache uses the cache, with no request.
out=$(TEST_OFFLINE=1 scan "$WORK/typo/cache-case" "$WORK/typo")
check "offline with fresh cache: no new request" "$(echo "$out" | sed -n 3p)" "CALLS=2"
check "offline with fresh cache: typosquats still found" "$(echo "$out" | grep -c '^F TYPOSQUAT_SUSPECT')" "3"

# Offline with no cache: no request, a warning, and no typosquat findings.
out=$(TEST_OFFLINE=1 scan "$WORK/typo/offline-case" "$WORK/typo")
check "offline without cache: exit 0" "$(echo "$out" | sed -n 1p)" "RC=0"
check "offline without cache: no request" "$(echo "$out" | sed -n 3p)" "CALLS=0"
has "offline without cache: warning names the skipped check" "$out" "W typosquat check skipped: --offline, and no list cached"
check "offline without cache: no typosquat findings" "$(echo "$out" | grep -c '^F TYPOSQUAT_SUSPECT')" "0"

# A failed fetch with no cache skips the typosquat check, with a warning. Other checks still run.
mkdir -p "$WORK/fail/case" && : > "$WORK/fail/case/pfail"
out=$(TEST_PREFIXES="flask" scan "$WORK/fail/case" "$WORK/typo")
check "fetch failure: exit 0" "$(echo "$out" | sed -n 1p)" "RC=0"
has "fetch failure: warning names the cause" "$out" "W typosquat check skipped: the popular-package list could not be fetched"
check "fetch failure: no typosquat findings" "$(echo "$out" | grep -c '^F TYPOSQUAT_SUSPECT')" "0"
check "fetch failure: dependency confusion still runs" "$(echo "$out" | grep -c '^F DEPENDENCY_CONFUSION_RISK')" "1"

# Only the top N names are used: with N=3 the list is numpy, requests, and django, so flask is
# not a reference name and flasks is not flagged.
out=$(TEST_TOPN=3 scan "$WORK/typo/topn-case" "$WORK/typo")
check "top N: list file holds N names" "$(wc -l < "$WORK/typo/topn-case/cache/repo-shield/pypi-top-3.txt" | tr -d ' ')" "3"
lacks "top N: a name outside the top N is not a reference" "$out" "'flasks'"
has "top N: a name inside the top N is still a reference" "$out" "'requets' is close to the popular package 'requests'"

# Dependency confusion. The prefix matches after normalization. Scoped npm names are never flagged.
mkdir -p "$WORK/confusion"
cat > "$WORK/confusion/requirements.txt" <<'EOF'
acme-utils==1.0
Acme-Core==2.0
other-pkg==1.0
EOF
cat > "$WORK/confusion/package-lock.json" <<'EOF'
{"name":"app","lockfileVersion":3,"requires":true,"packages":{"":{"name":"app"},"node_modules/acme-tools":{"version":"1.0.0"},"node_modules/@acme/utils":{"version":"1.0.0"}}}
EOF

# "@acme" is given as a prefix too, so the scoped name would match it without the scope rule.
out=$(TEST_PREFIXES="acme- @acme" scan "$WORK/confusion/case" "$WORK/confusion")
check "confusion: exit 0" "$(echo "$out" | sed -n 1p)" "RC=0"
check "confusion: three findings" "$(echo "$out" | grep -c '^F DEPENDENCY_CONFUSION_RISK HIGH')" "3"
has "confusion: unscoped requirement is flagged" "$out" "'acme-utils' starts with the internal prefix 'acme-' and is not scoped"
has "confusion: normalized name is flagged" "$out" "'Acme-Core' starts with the internal prefix"
has "confusion: unscoped npm name is flagged" "$out" "'acme-tools' starts with the internal prefix"
lacks "confusion: scoped npm name is not flagged" "$out" "'@acme/utils'"
lacks "confusion: other name is not flagged" "$out" "'other-pkg'"

# Without --internal-prefix the check does not run.
out=$(scan "$WORK/confusion/noprefix" "$WORK/confusion")
check "confusion: no prefix, no findings" "$(echo "$out" | grep -c '^F DEPENDENCY_CONFUSION_RISK')" "0"

# The check works offline, so with --offline it still runs (spec 4.3).
out=$(TEST_OFFLINE=1 TEST_PREFIXES="acme-" scan "$WORK/confusion/offline" "$WORK/confusion")
check "confusion offline: findings still reported" "$(echo "$out" | grep -c '^F DEPENDENCY_CONFUSION_RISK')" "3"
check "confusion offline: no request" "$(echo "$out" | sed -n 3p)" "CALLS=0"

# Maven: the prefix is matched against the groupId.
mkdir -p "$WORK/maven"
cat > "$WORK/maven/pom.xml" <<'EOF'
<project>
  <dependencies>
    <dependency>
      <groupId>com.acme</groupId>
      <artifactId>lib</artifactId>
      <version>1.0</version>
    </dependency>
    <dependency>
      <groupId>org.example</groupId>
      <artifactId>acme-lib</artifactId>
      <version>1.0</version>
    </dependency>
  </dependencies>
</project>
EOF
out=$(TEST_PREFIXES="com.acme" scan "$WORK/maven/case" "$WORK/maven")
check "maven: one finding for the groupId match" "$(echo "$out" | grep -c '^F DEPENDENCY_CONFUSION_RISK')" "1"
has "maven: names the coordinate" "$out" "'com.acme:lib' starts with the internal prefix 'com.acme'"
lacks "maven: artifactId does not count as a groupId match" "$out" "acme-lib"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
