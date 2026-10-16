#!/bin/bash
# Argument parsing, usage text, and the dependency check for repo-shield.
# Sourced by bin/repo-shield. Parsed values are stored in the CLI_* variables
# below. Later tasks read them after cli_parse_args returns.

# Defaults (spec Section 8.2).
CLI_FORMAT="table"
CLI_OUTPUT=""
CLI_FAIL_ON_CRITICAL=0
CLI_OFFLINE=0
CLI_QUIET=0
CLI_VERBOSE=0
CLI_SHOW_HELP=0
CLI_SHOW_VERSION=0
CLI_TARGETS=()

cli_usage() {
  cat <<'EOF'
Usage: repo-shield [OPTIONS] <path-to-repository> [<path-to-repository>...]

Options:
  -f, --format=FORMAT     Output format: table, json, sarif (default: table)
  -o, --output=FILE       Write findings to FILE instead of stdout
      --fail-on-critical  Exit 1 if any CRITICAL finding is present
      --offline           Skip SCA (no OSV queries); SAST and lifecycle checks still run
  -q, --quiet             Suppress non-essential output
      --verbose           Print additional progress detail
  -h, --help              Print this help and exit
  -v, --version           Print the version and exit

Use -- to end option parsing, so a path that starts with '-' can be given.
EOF
}

cli_help() {
  echo "RepoShield Security Scanner: local security scanner for cloned repositories."
  echo
  cli_usage
}

# Prints the error and the usage text to stderr, then exits 1 (spec Section 8.3).
cli_usage_error() {
  echo "repo-shield: $1" >&2
  echo >&2
  cli_usage >&2
  exit 1
}

cli_set_format() {
  case $1 in
    table|json|sarif) CLI_FORMAT=$1 ;;
    *) cli_usage_error "invalid --format value '$1' (valid values: table, json, sarif)" ;;
  esac
}

cli_set_output() {
  [ -n "$1" ] || cli_usage_error "option '--output' requires a file name"
  CLI_OUTPUT=$1
}

# Parses every option into the CLI_* variables. Paths go into CLI_TARGETS.
# Path existence is checked by the target resolution stage, not here.
cli_parse_args() {
  local arg flags c value
  local end_of_options=0

  while [ $# -gt 0 ]; do
    arg=$1
    shift

    if [ "$end_of_options" -eq 1 ]; then
      CLI_TARGETS[${#CLI_TARGETS[@]}]=$arg
      continue
    fi

    case $arg in
      --)
        end_of_options=1
        ;;
      --format|--output)
        [ $# -gt 0 ] || cli_usage_error "option '$arg' requires a value"
        if [ "$arg" = --format ]; then
          cli_set_format "$1"
        else
          cli_set_output "$1"
        fi
        shift
        ;;
      --format=*) cli_set_format "${arg#--format=}" ;;
      --output=*) cli_set_output "${arg#--output=}" ;;
      --fail-on-critical) CLI_FAIL_ON_CRITICAL=1 ;;
      --offline) CLI_OFFLINE=1 ;;
      --quiet) CLI_QUIET=1 ;;
      --verbose) CLI_VERBOSE=1 ;;
      --help) CLI_SHOW_HELP=1 ;;
      --version) CLI_SHOW_VERSION=1 ;;
      --fail-on-critical=*|--offline=*|--quiet=*|--verbose=*|--help=*|--version=*)
        cli_usage_error "option '${arg%%=*}' does not take a value"
        ;;
      --*) cli_usage_error "unknown option '$arg'" ;;
      -?*)
        # Combined short flags, such as -qfjson or -qf json.
        flags=${arg#-}
        while [ -n "$flags" ]; do
          c=${flags:0:1}
          flags=${flags:1}
          case $c in
            f|o)
              if [ -n "$flags" ]; then
                value=$flags
                flags=
              elif [ $# -gt 0 ]; then
                value=$1
                shift
              else
                cli_usage_error "option '-$c' requires a value"
              fi
              if [ "$c" = f ]; then
                cli_set_format "$value"
              else
                cli_set_output "$value"
              fi
              ;;
            q) CLI_QUIET=1 ;;
            h) CLI_SHOW_HELP=1 ;;
            v) CLI_SHOW_VERSION=1 ;;
            *) cli_usage_error "unknown option '-$c'" ;;
          esac
        done
        ;;
      *) CLI_TARGETS[${#CLI_TARGETS[@]}]=$arg ;;
    esac
  done

  if [ "$CLI_SHOW_HELP" -eq 1 ]; then
    cli_help
    exit 0
  fi
  if [ "$CLI_SHOW_VERSION" -eq 1 ]; then
    echo "repo-shield $REPO_SHIELD_VERSION"
    exit 0
  fi
  if [ ${#CLI_TARGETS[@]} -eq 0 ]; then
    cli_usage_error "missing path to repository"
  fi
}

# Fails fast when a required tool is missing (spec Section 2.2).
cli_check_dependencies() {
  local tool missing=""
  for tool in jq curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing="${missing:+$missing }$tool"
    fi
  done
  if [ -n "$missing" ]; then
    echo "repo-shield: required tool(s) not found: $missing. Install them and try again." >&2
    exit 1
  fi
}
