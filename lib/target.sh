#!/bin/bash
# Target path resolution for repo-shield (spec Section 3.1).
# Sourced by bin/repo-shield after cli_parse_args. Resolved absolute paths are
# stored in TARGET_DIRS, in the order given on the command line.

TARGET_DIRS=()

# Resolves every path in CLI_TARGETS. Every bad path is reported before the
# script exits 1, so no path is scanned when any path is invalid.
target_resolve_all() {
  local path resolved failed=0
  TARGET_DIRS=()
  for path in "${CLI_TARGETS[@]}"; do
    if resolved=$(target_resolve "$path"); then
      TARGET_DIRS[${#TARGET_DIRS[@]}]=$resolved
    else
      echo "repo-shield: target path '$path' does not exist or is not a directory" >&2
      failed=1
    fi
  done
  [ "$failed" -eq 0 ] || exit 1
}

# Prints the absolute physical path of a directory and returns 1 if the path is
# not a directory. cd -P resolves every symlink, so a symlinked target is
# reported at its real location. CDPATH is cleared so a relative path is always
# resolved from the current directory.
target_resolve() {
  [ -d "$1" ] || return 1
  (CDPATH= cd -P -- "$1" && pwd -P)
}
