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
