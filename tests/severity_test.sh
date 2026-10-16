#!/bin/bash
# Acceptance checks for TASK_06 (severity defaults, engine mapping, and exit code, spec 7.4 and 8.3).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/severity_test.sh

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# run <bash snippet>: runs the snippet in a fresh shell with the modules loaded. The CLI parser is
# loaded so the exit code can be checked against real --fail-on-critical parsing.
# Stdout and stderr go to $WORK/out and $WORK/err.
run() {
  /bin/bash -c '. "$1/lib/cli.sh"; . "$1/lib/report.sh"; . "$1/lib/severity.sh"; '"$1" _ "$ROOT" >"$WORK/out" 2>"$WORK/err"
}

# check <name> <got> <want>
check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    echo "    got:"
    printf '%s\n' "$2" | sed 's/^/      /'
    echo "    want:"
    printf '%s\n' "$3" | sed 's/^/      /'
  fi
}

# Each row of the spec 7.4 table, and the provisional HIGH categories.
run 'for spec in "MALICIOUS_BUILD_HOOK pipe-to-shell" "MALICIOUS_BUILD_HOOK network" "REVERSE_SHELL" "OBFUSCATED_EXECUTION" "MISSING_LOCKFILE" "SECRET_EXPOSED" "TYPOSQUAT_SUSPECT" "DEPENDENCY_CONFUSION_RISK" "PATH_TRAVERSAL_HOOK"; do
  set -- $spec
  severity_default "$@"
  echo "$spec=$_SEVERITY"
done'
check "default severity for each 7.4 row" \
  "$(cat "$WORK/out")" \
  "MALICIOUS_BUILD_HOOK pipe-to-shell=CRITICAL
MALICIOUS_BUILD_HOOK network=HIGH
REVERSE_SHELL=CRITICAL
OBFUSCATED_EXECUTION=HIGH
MISSING_LOCKFILE=LOW
SECRET_EXPOSED=HIGH
TYPOSQUAT_SUSPECT=HIGH
DEPENDENCY_CONFUSION_RISK=HIGH
PATH_TRAVERSAL_HOOK=HIGH"

# No decided default: VULNERABLE_DEPENDENCY (item 64), an unknown category, and a hook with no
# condition. Each returns 1 and sets nothing.
run 'severity_default VULNERABLE_DEPENDENCY; echo "a=$? [$_SEVERITY]"; severity_default NOT_A_CATEGORY; echo "b=$? [$_SEVERITY]"; severity_default MALICIOUS_BUILD_HOOK; echo "c=$? [$_SEVERITY]"'
check "severity_default fails when no default is decided" \
  "$(cat "$WORK/out")" \
  "a=1 []
b=1 []
c=1 []"
check "severity_default prints a message on failure" \
  "$(wc -l < "$WORK/err" | tr -d ' ')" \
  "3"

# Engine mapping: no native severity gives MEDIUM. Level names map in any case.
run 'severity_from_engine yara ""; echo "empty=$_SEVERITY"; severity_from_engine semgrep ""; echo "empty2=$_SEVERITY"; severity_from_engine yara CRITICAL; echo "upper=$_SEVERITY"; severity_from_engine semgrep high; echo "lower=$_SEVERITY"; shopt -q nocasematch; echo "nocase=$?"'
check "engine mapping: default MEDIUM, level names in any case, nocasematch restored" \
  "$(cat "$WORK/out")" \
  "empty=MEDIUM
empty2=MEDIUM
upper=CRITICAL
lower=HIGH
nocase=1"

# Engine native values with no mapping fail. osv has no mapping yet (item 64) and an unknown
# engine is refused.
run 'severity_from_engine semgrep ERROR; echo "a=$? [$_SEVERITY]"; severity_from_engine osv HIGH; echo "b=$? [$_SEVERITY]"; severity_from_engine nope HIGH; echo "c=$? [$_SEVERITY]"'
check "engine mapping refuses unmapped values, osv, and unknown engines" \
  "$(cat "$WORK/out")" \
  "a=1 []
b=1 []
c=1 []"

# severity_count counts only the exact level. A HIGH finding is not a CRITICAL one.
run '
finding_add MALICIOUS_BUILD_HOOK CRITICAL package.json "pipe"
finding_add VULNERABLE_DEPENDENCY HIGH package-lock.json "advisory"
finding_add MISSING_LOCKFILE LOW requirements.txt "no lock"
severity_count CRITICAL; echo "critical=$_COUNT"
severity_count HIGH; echo "high=$_COUNT"
severity_count MEDIUM; echo "medium=$_COUNT"'
check "severity_count counts only the requested level" \
  "$(cat "$WORK/out")" \
  "critical=1
high=1
medium=0"

# Exit code: 1 only with --fail-on-critical and a CRITICAL finding. Parsed through cli_parse_args.
run '
finding_add MALICIOUS_BUILD_HOOK CRITICAL package.json "pipe"
cli_parse_args --fail-on-critical .
severity_scan_exit_code; echo "flag_critical=$_EXIT_CODE"'
check "--fail-on-critical with a CRITICAL finding exits 1" \
  "$(cat "$WORK/out")" \
  "flag_critical=1"

run '
finding_add VULNERABLE_DEPENDENCY HIGH package-lock.json "advisory"
finding_add MISSING_LOCKFILE LOW requirements.txt "no lock"
cli_parse_args --fail-on-critical .
severity_scan_exit_code; echo "flag_no_critical=$_EXIT_CODE"'
check "--fail-on-critical without a CRITICAL finding exits 0" \
  "$(cat "$WORK/out")" \
  "flag_no_critical=0"
run '
finding_add VULNERABLE_DEPENDENCY HIGH package-lock.json "advisory"
finding_add MISSING_LOCKFILE LOW requirements.txt "no lock"
cli_parse_args -q .
severity_scan_exit_code; echo "noflag_no_critical=$_EXIT_CODE"'
check "without a CRITICAL finding the exit code is 0" \
  "$(cat "$WORK/out")" \
  "noflag_no_critical=0"

run '
finding_add MALICIOUS_BUILD_HOOK CRITICAL package.json "pipe"
cli_parse_args .
severity_scan_exit_code; echo "noflag_critical=$_EXIT_CODE"'
check "without --fail-on-critical a CRITICAL finding still exits 0" \
  "$(cat "$WORK/out")" \
  "noflag_critical=0"

run '
cli_parse_args --fail-on-critical .
severity_scan_exit_code; echo "empty=$_EXIT_CODE"'
check "--fail-on-critical with no findings exits 0" \
  "$(cat "$WORK/out")" \
  "empty=0"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
