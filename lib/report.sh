#!/bin/bash
# Finding model and report renderers for repo-shield (spec Section 7). Sourced by bin/repo-shield.
# Findings are stored during the scan with finding_add and rendered once at the end with
# report_emit. Nothing is rendered during the scan.
#
# Each finding has the four fields in spec 7.1: category, severity, file, description.
# It may also have line (item 29), the line number in file. Findings are kept as parallel
# arrays, one entry per finding, because bash cannot hold a NUL byte and names can contain tabs
# or newlines.
#
# Renderers: table (plain text, see item 32), json (spec 7.1 and 7.2), and sarif (SARIF 2.1.0,
# item 30 mapping).

FINDING_CATEGORY=()
FINDING_SEVERITY=()
FINDING_FILE=()
FINDING_DESCRIPTION=()
FINDING_LINE=()

# Set by report_json_string. Used instead of $(...) so a large report does not fork per field.
_JSON_STR=""

# finding_add <category> <severity> <file> <description> [line]
# severity must be CRITICAL, HIGH, MEDIUM, or LOW. file is relative to the target directory
# (spec 7.1; item 54). line is optional: a line number in file, from 1 (item 29). Returns 1 and
# reports to stderr when the input is not valid.
finding_add() {
  case $2 in
    CRITICAL | HIGH | MEDIUM | LOW) ;;
    *)
      echo "repo-shield: invalid finding severity: '$2'" >&2
      return 1
      ;;
  esac
  if [ -z "$1" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "repo-shield: a finding needs a category, a file, and a description" >&2
    return 1
  fi
  case ${5:-} in
    '') ;;
    *[!0-9]* | 0*)
      echo "repo-shield: finding line must be a positive number: '$5'" >&2
      return 1
      ;;
  esac
  FINDING_CATEGORY[${#FINDING_CATEGORY[@]}]=$1
  FINDING_SEVERITY[${#FINDING_SEVERITY[@]}]=$2
  FINDING_FILE[${#FINDING_FILE[@]}]=$3
  FINDING_DESCRIPTION[${#FINDING_DESCRIPTION[@]}]=$4
  FINDING_LINE[${#FINDING_LINE[@]}]=${5:-}
}

# report_json_string <text>: sets _JSON_STR to the text as a quoted JSON string.
# Escapes quotes, backslashes, and control characters. Bytes above 0x7f pass through unchanged,
# so UTF-8 names stay valid.
report_json_string() {
  local s=$1 out="" i c hex
  local LC_ALL=C

  case $s in
    *[\"\\]* | *[[:cntrl:]]*) ;;
    *)
      _JSON_STR="\"$s\""
      return 0
      ;;
  esac

  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      '"') out="$out\\\"" ;;
      \\) out="$out\\\\" ;;
      $'\n') out="$out\\n" ;;
      $'\r') out="$out\\r" ;;
      $'\t') out="$out\\t" ;;
      $'\b') out="$out\\b" ;;
      $'\f') out="$out\\f" ;;
      *)
        case $c in
          [[:cntrl:]])
            printf -v hex '\\u%04x' "'$c"
            out="$out$hex"
            ;;
          *) out="$out$c" ;;
        esac
        ;;
    esac
  done
  _JSON_STR="\"$out\""
}

# report_json <target>: the report in spec 7.2 layout, on stdout.
report_json() {
  local target=$1 i total=${#FINDING_CATEGORY[@]} critical=0

  for ((i = 0; i < total; i++)); do
    if [ "${FINDING_SEVERITY[i]}" = CRITICAL ]; then
      critical=$((critical + 1))
    fi
  done

  report_json_string "$target"
  printf '{\n  "target_directory": %s,\n' "$_JSON_STR"
  printf '  "total_findings": %d,\n' "$total"
  printf '  "critical_findings": %d,\n' "$critical"
  if [ "$total" -eq 0 ]; then
    printf '  "findings": []\n}\n'
    return 0
  fi

  printf '  "findings": [\n'
  for ((i = 0; i < total; i++)); do
    printf '    {\n'
    report_json_string "${FINDING_CATEGORY[i]}"
    printf '      "category": %s,\n' "$_JSON_STR"
    printf '      "severity": "%s",\n' "${FINDING_SEVERITY[i]}"
    report_json_string "${FINDING_FILE[i]}"
    printf '      "file": %s,\n' "$_JSON_STR"
    if [ -n "${FINDING_LINE[i]}" ]; then
      printf '      "line": %s,\n' "${FINDING_LINE[i]}"
    fi
    report_json_string "${FINDING_DESCRIPTION[i]}"
    printf '      "description": %s\n' "$_JSON_STR"
    if [ $((i + 1)) -lt "$total" ]; then
      printf '    },\n'
    else
      printf '    }\n'
    fi
  done
  printf '  ]\n}\n'
}

# report_table_cell <text>: sets _TABLE_CELL. Control characters become '?' so a name with a
# newline cannot break a table row.
report_table_cell() {
  case $1 in
    *[[:cntrl:]]*) _TABLE_CELL=$(printf '%s' "$1" | tr '[:cntrl:]' '?') ;;
    *) _TABLE_CELL=$1 ;;
  esac
}

# report_table <target>: a plain-text table on stdout, with a summary line.
report_table() {
  local target=$1 i total=${#FINDING_CATEGORY[@]} critical=0
  local w_sev=8 w_cat=8 w_file=4 cat_cell file_cell desc_cell

  for ((i = 0; i < total; i++)); do
    [ "${FINDING_SEVERITY[i]}" = CRITICAL ] && critical=$((critical + 1))
    report_table_cell "${FINDING_CATEGORY[i]}"
    [ "${#_TABLE_CELL}" -gt "$w_cat" ] && w_cat=${#_TABLE_CELL}
    report_table_cell "${FINDING_FILE[i]}"
    [ "${#_TABLE_CELL}" -gt "$w_file" ] && w_file=${#_TABLE_CELL}
  done

  printf 'Target: %s\n\n' "$target"
  printf '%-*s  %-*s  %-*s  %s\n' "$w_sev" SEVERITY "$w_cat" CATEGORY "$w_file" FILE DESCRIPTION
  for ((i = 0; i < total; i++)); do
    report_table_cell "${FINDING_CATEGORY[i]}"
    cat_cell=$_TABLE_CELL
    report_table_cell "${FINDING_FILE[i]}"
    file_cell=$_TABLE_CELL
    report_table_cell "${FINDING_DESCRIPTION[i]}"
    desc_cell=$_TABLE_CELL
    printf '%-*s  %-*s  %-*s  %s\n' "$w_sev" "${FINDING_SEVERITY[i]}" "$w_cat" "$cat_cell" \
      "$w_file" "$file_cell" "$desc_cell"
  done
  printf '\nTotal findings: %d, critical: %d\n' "$total" "$critical"
}

# Severity mappings for SARIF (spec 7.4 scale, item 30 confirmed mapping).
# _report_rank: order for picking the highest severity. _report_sarif_level: SARIF level.
# _report_sarif_score: security-severity for a rule, the highest of its findings.
_report_rank() {
  case $1 in
    CRITICAL) _RANK=4 ;;
    HIGH) _RANK=3 ;;
    MEDIUM) _RANK=2 ;;
    *) _RANK=1 ;;
  esac
}

_report_sarif_level() {
  case $1 in
    CRITICAL | HIGH) _LEVEL=error ;;
    MEDIUM) _LEVEL=warning ;;
    *) _LEVEL=note ;;
  esac
}

_report_sarif_score() {
  case $1 in
    CRITICAL) _SCORE=9.0 ;;
    HIGH) _SCORE=7.0 ;;
    MEDIUM) _SCORE=4.0 ;;
    *) _SCORE=1.0 ;;
  esac
}

# report_uri_encode <path>: sets _URI to the path as a URI reference. Bytes outside the
# unreserved set and '/' are percent-encoded, so a name with a space is still a valid URI.
report_uri_encode() {
  local s=$1 out="" i c hex
  local LC_ALL=C

  case $s in
    *[!A-Za-z0-9._~/-]*) ;;
    *)
      _URI=$s
      return 0
      ;;
  esac
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~/-]) out="$out$c" ;;
      *)
        printf -v hex '%%%02X' "'$c"
        out="$out$hex"
        ;;
    esac
  done
  _URI=$out
}

# report_snippet <target> <file> <line>: sets _SNIPPET to that line of the file. Empty when the
# file cannot be read. The file is read as data only, never run.
report_snippet() {
  _SNIPPET=""
  [ -f "$1/$2" ] || return 0
  _SNIPPET=$(sed -n "$3p" < "$1/$2" 2>/dev/null)
}

# report_sarif <target>: a SARIF 2.1.0 log on stdout (spec 7.3, item 30 mapping).
# One rule per category. Each result has ruleId, level, message, and a location. A location has
# a region and snippet only when the finding has a line.
report_sarif() {
  local target=$1 i j r total=${#FINDING_CATEGORY[@]} nrules=0 uri_json msg_json snippet_json
  local -a rule_id=() rule_sev=()

  # One rule per category, in first-seen order. Its security severity is the highest severity
  # among its findings.
  for ((i = 0; i < total; i++)); do
    for ((j = 0; j < nrules; j++)); do
      [ "${rule_id[j]}" = "${FINDING_CATEGORY[i]}" ] && break
    done
    if [ "$j" -eq "$nrules" ]; then
      rule_id[nrules]=${FINDING_CATEGORY[i]}
      rule_sev[nrules]=${FINDING_SEVERITY[i]}
      nrules=$((nrules + 1))
    else
      _report_rank "${FINDING_SEVERITY[i]}"
      r=$_RANK
      _report_rank "${rule_sev[j]}"
      if [ "$r" -gt "$_RANK" ]; then
        rule_sev[j]=${FINDING_SEVERITY[i]}
      fi
    fi
  done

  printf '{\n'
  printf '  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",\n'
  printf '  "version": "2.1.0",\n'
  printf '  "runs": [\n    {\n'
  printf '      "tool": {\n        "driver": {\n'
  printf '          "name": "repo-shield",\n'
  if [ -n "${REPO_SHIELD_VERSION:-}" ]; then
    report_json_string "$REPO_SHIELD_VERSION"
    printf '          "version": %s,\n' "$_JSON_STR"
  fi
  if [ "$nrules" -eq 0 ]; then
    printf '          "rules": []\n'
  else
    printf '          "rules": [\n'
    for ((j = 0; j < nrules; j++)); do
      report_json_string "${rule_id[j]}"
      printf '            {\n              "id": %s,\n' "$_JSON_STR"
      printf '              "shortDescription": {"text": %s},\n' "$_JSON_STR"
      _report_sarif_score "${rule_sev[j]}"
      printf '              "properties": {"security-severity": "%s", "tags": ["security"]}\n' "$_SCORE"
      if [ $((j + 1)) -lt "$nrules" ]; then
        printf '            },\n'
      else
        printf '            }\n'
      fi
    done
    printf '          ]\n'
  fi
  printf '        }\n      },\n'

  printf '      "results": ['
  if [ "$total" -eq 0 ]; then
    printf ']\n'
  else
    printf '\n'
  fi
  for ((i = 0; i < total; i++)); do
    report_json_string "${FINDING_CATEGORY[i]}"
    printf '        {\n          "ruleId": %s,\n' "$_JSON_STR"
    _report_sarif_level "${FINDING_SEVERITY[i]}"
    printf '          "level": "%s",\n' "$_LEVEL"
    report_json_string "${FINDING_DESCRIPTION[i]}"
    printf '          "message": {"text": %s},\n' "$_JSON_STR"
    printf '          "locations": [\n            {\n              "physicalLocation": {\n'
    report_uri_encode "${FINDING_FILE[i]}"
    report_json_string "$_URI"
    printf '                "artifactLocation": {"uri": %s}' "$_JSON_STR"
    if [ -n "${FINDING_LINE[i]}" ]; then
      printf ',\n                "region": {"startLine": %s' "${FINDING_LINE[i]}"
      report_snippet "$target" "${FINDING_FILE[i]}" "${FINDING_LINE[i]}"
      if [ -n "$_SNIPPET" ]; then
        report_json_string "$_SNIPPET"
        printf ', "snippet": {"text": %s}' "$_JSON_STR"
      fi
      printf '}'
    fi
    printf '\n              }\n            }\n          ]\n        }'
    if [ $((i + 1)) -lt "$total" ]; then
      printf ',\n'
    else
      printf '\n'
    fi
  done
  if [ "$total" -gt 0 ]; then
    printf '      ]\n'
  fi
  printf '    }\n  ]\n}\n'
}

# report_emit <format> <output file, or empty> <target>
# Writes the report to stdout, or to the output file with stdout left empty (spec 8.2 -o).
# Returns 1 when the format is not implemented or the output file cannot be written (spec 2.4).
report_emit() {
  local format=$1 out=$2 target=$3 render

  case $format in
    table) render=report_table ;;
    json) render=report_json ;;
    sarif) render=report_sarif ;;
    *)
      echo "repo-shield: invalid format: '$format'" >&2
      return 1
      ;;
  esac

  if [ -z "$out" ]; then
    "$render" "$target"
    return $?
  fi
  # The group's stderr is discarded so bash does not print its own redirect error. The message
  # below replaces it.
  { "$render" "$target" > "$out"; } 2>/dev/null || {
    echo "repo-shield: cannot write output file: $out" >&2
    return 1
  }
}
