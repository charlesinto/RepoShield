#!/bin/bash
# Severity defaults, engine severity mapping, and the scan exit code (spec 7.4 and 8.3).
# Sourced by bin/repo-shield. Finding producers get a severity from severity_default or
# severity_from_engine, then store the finding with finding_add (lib/report.sh).

# severity_default <category> [condition]: sets _SEVERITY to the default severity for the
# category (spec 7.4). A category with more than one row needs a condition: MALICIOUS_BUILD_HOOK
# takes pipe-to-shell or network. Returns 1 when there is no decided default: VULNERABLE_DEPENDENCY
# (item 64), or an unknown category or condition.
severity_default() {
  _SEVERITY=""
  case $1 in
    MALICIOUS_BUILD_HOOK)
      case ${2:-} in
        pipe-to-shell) _SEVERITY=CRITICAL ;;
        network) _SEVERITY=HIGH ;;
      esac
      ;;
    REVERSE_SHELL) _SEVERITY=CRITICAL ;;
    OBFUSCATED_EXECUTION) _SEVERITY=HIGH ;;
    MISSING_LOCKFILE) _SEVERITY=LOW ;;
    # Provisional: no default is decided yet (spec 7.4). HIGH until items 21 and 62 are resolved.
    SECRET_EXPOSED | TYPOSQUAT_SUSPECT | DEPENDENCY_CONFUSION_RISK | PATH_TRAVERSAL_HOOK)
      _SEVERITY=HIGH
      ;;
  esac
  if [ -z "$_SEVERITY" ]; then
    echo "repo-shield: no default severity for category '$1' '${2:-}'" >&2
    return 1
  fi
}

# severity_from_engine <engine> <native>: sets _SEVERITY to the four-level value for an engine's
# native severity. Each engine has its own branch here, so one mapping can change without touching
# the others or the aggregator. An empty native severity means the rule has no severity: MEDIUM
# (item 27 working default). The four level names are accepted in any case. Returns 1 for a native
# value with no mapping, and for an engine with no mapping yet (osv waits on item 64).
severity_from_engine() {
  local native=$2
  _SEVERITY=""
  case $1 in
    yara | semgrep) ;;
    *)
      echo "repo-shield: no severity mapping for engine '$1'" >&2
      return 1
      ;;
  esac

  if [ -z "$native" ]; then
    _SEVERITY=MEDIUM
    return 0
  fi

  # nocasematch is set only for the match and cleared after it, as in lib/classify.sh.
  shopt -s nocasematch
  case $native in
    CRITICAL) _SEVERITY=CRITICAL ;;
    HIGH) _SEVERITY=HIGH ;;
    MEDIUM) _SEVERITY=MEDIUM ;;
    LOW) _SEVERITY=LOW ;;
  esac
  shopt -u nocasematch

  if [ -z "$_SEVERITY" ]; then
    echo "repo-shield: no severity mapping for $1 severity '$native'" >&2
    return 1
  fi
}

# severity_count <level>: sets _COUNT to the number of findings with exactly that severity.
severity_count() {
  local i
  _COUNT=0
  for ((i = 0; i < ${#FINDING_SEVERITY[@]}; i++)); do
    if [ "${FINDING_SEVERITY[i]}" = "$1" ]; then
      _COUNT=$((_COUNT + 1))
    fi
  done
}

# severity_scan_exit_code: sets _EXIT_CODE to the scan result (spec 8.3). It is 1 only when
# --fail-on-critical is set and at least one CRITICAL finding exists. Without the flag, findings of
# any severity give 0. Errors are not handled here (item 59).
severity_scan_exit_code() {
  _EXIT_CODE=0
  if [ "${CLI_FAIL_ON_CRITICAL:-0}" -eq 1 ]; then
    severity_count CRITICAL
    if [ "$_COUNT" -gt 0 ]; then
      _EXIT_CODE=1
    fi
  fi
}

# severity_from_cvss_score <score>: sets _SEVERITY from a CVSS base score (spec 7.4, item 64):
# 9.0 to 10.0 is CRITICAL, 7.0 to 8.9 is HIGH, 4.0 to 6.9 is MEDIUM, and 0.1 to 3.9 is LOW.
# The score has one decimal place, as CVSS scores do. Returns 1 for anything else (0.0, a value
# above 10, or text that is not a number). Bash integer arithmetic on tenths avoids float errors.
severity_from_cvss_score() {
  local whole frac tenths
  _SEVERITY=""
  case $1 in
    [0-9] | [0-9][0-9] | [0-9].[0-9] | [0-9][0-9].[0-9]) ;;
    *) return 1 ;;
  esac
  whole=${1%%.*}
  frac=0
  case $1 in
    *.*) frac=${1#*.} ;;
  esac
  tenths=$((whole * 10 + frac))
  if [ "$tenths" -ge 90 ] && [ "$tenths" -le 100 ]; then
    _SEVERITY=CRITICAL
  elif [ "$tenths" -ge 70 ] && [ "$tenths" -le 89 ]; then
    _SEVERITY=HIGH
  elif [ "$tenths" -ge 40 ] && [ "$tenths" -le 69 ]; then
    _SEVERITY=MEDIUM
  elif [ "$tenths" -ge 1 ] && [ "$tenths" -le 39 ]; then
    _SEVERITY=LOW
  else
    return 1
  fi
  return 0
}

# cvss3_base_score <vector>: prints the CVSS v3.0 or v3.1 base score for a vector such as
# CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H, rounded up to one decimal as CVSS defines it.
# Prints nothing and returns 1 for CVSS v2, v4, or any malformed or incomplete vector. The
# temporal and environmental metrics are not used, because the base score is what maps to a
# severity.
cvss3_base_score() {
  local score
  score=$(awk -v v="$1" '
    function roundup(x,   i) {
      i = int(x * 100000 + 0.5)
      if (i % 10000 == 0) return i / 100000
      return (int(i / 10000) + 1) / 10
    }
    BEGIN {
      n = split(v, p, "/")
      if (n != 9 || (p[1] != "CVSS:3.0" && p[1] != "CVSS:3.1")) exit 1
      for (k = 2; k <= n; k++) {
        if (split(p[k], kv, ":") != 2) exit 1
        m[kv[1]] = kv[2]
      }
      for (key in m) ok[key] = 1
      split("AV AC PR UI S C I A", need, " ")
      for (k = 1; k <= 8; k++) if (!(need[k] in m)) exit 1
      if (m["AV"] == "N") av = 0.85; else if (m["AV"] == "A") av = 0.62
      else if (m["AV"] == "L") av = 0.55; else if (m["AV"] == "P") av = 0.2; else exit 1
      if (m["AC"] == "L") ac = 0.77; else if (m["AC"] == "H") ac = 0.44; else exit 1
      if (m["S"] != "U" && m["S"] != "C") exit 1
      changed = (m["S"] == "C")
      if (m["PR"] == "N") pr = 0.85
      else if (m["PR"] == "L") pr = changed ? 0.68 : 0.62
      else if (m["PR"] == "H") pr = changed ? 0.5 : 0.27
      else exit 1
      if (m["UI"] == "N") ui = 0.85; else if (m["UI"] == "R") ui = 0.62; else exit 1
      cia["H"] = 0.56; cia["L"] = 0.22; cia["N"] = 0
      if (!(m["C"] in cia) || !(m["I"] in cia) || !(m["A"] in cia)) exit 1
      iss = 1 - (1 - cia[m["C"]]) * (1 - cia[m["I"]]) * (1 - cia[m["A"]])
      if (changed) imp = 7.52 * (iss - 0.029) - 3.25 * (iss - 0.02) ^ 15
      else imp = 6.42 * iss
      expl = 8.22 * av * ac * pr * ui
      if (imp <= 0) { printf "%.1f\n", 0; exit 0 }
      if (changed) base = roundup(1.08 * (imp + expl) < 10 ? 1.08 * (imp + expl) : 10)
      else base = roundup(imp + expl < 10 ? imp + expl : 10)
      printf "%.1f\n", base
    }') || return 1
  printf '%s\n' "$score"
}
