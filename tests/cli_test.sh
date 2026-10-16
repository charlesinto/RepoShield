#!/bin/bash
# Acceptance checks for TASK_01 (CLI skeleton and exit codes).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/cli_test.sh

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/repo-shield"
PASS=0
FAIL=0

# A PATH with every system tool except jq and curl, to test the dependency check.
NOTOOLS=$(mktemp -d)
trap 'rm -rf "$NOTOOLS"' EXIT
for d in /bin /usr/bin; do
  for f in "$d"/*; do
    n=${f##*/}
    case $n in
      jq|curl) ;;
      *) [ -e "$NOTOOLS/$n" ] || ln -s "$f" "$NOTOOLS/$n" ;;
    esac
  done
done

# expect <name> <exit code> <text that must appear in output> <command...>
expect() {
  local name=$1 want_rc=$2 want_text=$3 out rc
  shift 3
  out=$("$@" 2>&1)
  rc=$?
  if [ "$rc" -eq "$want_rc" ] && { [ -z "$want_text" ] || printf '%s\n' "$out" | grep -qF -- "$want_text"; }; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (exit $rc, want $want_rc; want text '$want_text')"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# Acceptance: --help contains the formula test string (item 50).
expect "help long" 0 "RepoShield Security Scanner" /bin/bash "$BIN" --help
expect "help short" 0 "RepoShield Security Scanner" /bin/bash "$BIN" -h
expect "help works without jq or curl" 0 "RepoShield Security Scanner" /usr/bin/env PATH="$NOTOOLS" /bin/bash "$BIN" --help

# Acceptance: --version prints the stored semantic version (item 45).
expect "version long" 0 "repo-shield 0.1.0" /bin/bash "$BIN" --version
expect "version short" 0 "repo-shield 0.1.0" /bin/bash "$BIN" -v

# Acceptance: invalid input exits 1 with a usage message that lists valid values (item 41).
expect "unknown long flag" 1 "unknown option '--bogus'" /bin/bash "$BIN" --bogus .
expect "unknown short flag" 1 "unknown option '-x'" /bin/bash "$BIN" -x .
expect "invalid format" 1 "valid values: table, json, sarif" /bin/bash "$BIN" --format=xml .
expect "invalid format short" 1 "valid values: table, json, sarif" /bin/bash "$BIN" -f xml .
expect "usage lists formats" 1 "Output format: table, json, sarif" /bin/bash "$BIN" --format=xml .
expect "format without value" 1 "requires a value" /bin/bash "$BIN" --format
expect "missing path" 1 "missing path to repository" /bin/bash "$BIN"
expect "missing path with flags" 1 "missing path to repository" /bin/bash "$BIN" --offline
expect "flag takes no value" 1 "does not take a value" /bin/bash "$BIN" --quiet=1 .

# Acceptance: missing jq or curl exits 1 with a clear message (item 2).
expect "missing jq and curl" 1 "not found: jq curl" /usr/bin/env PATH="$NOTOOLS" /bin/bash "$BIN" .

# Acceptance: every option parses. A valid parse reaches the not-implemented stub (exit 1).
STUB="scanning is not implemented yet"
expect "format with equals" 1 "$STUB" /bin/bash "$BIN" --format=json .
expect "format as separate arg" 1 "$STUB" /bin/bash "$BIN" --format json .
expect "combined short flags" 1 "$STUB" /bin/bash "$BIN" -qfjson .
expect "combined short flags with value" 1 "$STUB" /bin/bash "$BIN" -qf json .
expect "all long options" 1 "$STUB" /bin/bash "$BIN" --offline --fail-on-critical --verbose --output=out.txt --format=sarif .
expect "end of options" 1 "$STUB" /bin/bash "$BIN" -- -weird-dir
expect "help after end of options is a path" 1 "$STUB" /bin/bash "$BIN" -- --help

# Acceptance: parsed values are stored for later tasks (item 39).
# Runs the parser from the library in a subshell and prints the stored values.
stored=$(/bin/bash -c '. "$1"; cli_parse_args -qfsarif -o out.txt --offline --fail-on-critical --verbose -- a b
echo "$CLI_QUIET $CLI_FORMAT $CLI_OUTPUT $CLI_OFFLINE $CLI_FAIL_ON_CRITICAL $CLI_VERBOSE ${#CLI_TARGETS[@]} ${CLI_TARGETS[0]} ${CLI_TARGETS[1]}"' _ "$ROOT/lib/cli.sh")
if [ "$stored" = "1 sarif out.txt 1 1 1 2 a b" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: stored values (got '$stored')"
fi

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
