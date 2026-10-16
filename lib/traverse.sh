#!/bin/bash
# File traversal and ignore rules for repo-shield (spec Sections 2.3, 3.2, 3.3).
# Sourced by bin/repo-shield. Nothing in the scanned tree is executed, sourced, or
# evaluated. Ignore files are read as data only.
#
# traverse_target fills these arrays for one target directory:
#   SCAN_ROOT     the target directory (absolute)
#   SCAN_FILES    regular files to scan, relative to SCAN_ROOT
#   SCAN_SKIPPED  symlinks and special files (FIFOs, sockets, devices), relative to SCAN_ROOT

SCAN_ROOT=""
SCAN_FILES=()
SCAN_SKIPPED=()

# .repo-shield-ignore patterns, one entry per pattern, in file order.
IGNORE_NEG=()
IGNORE_DIRONLY=()
IGNORE_ANCHORED=()
IGNORE_RE=()

# Walks one target directory and fills SCAN_FILES and SCAN_SKIPPED.
# Paths come from find with -print0 and are read the same way, so names with spaces,
# newlines, quotes, or a leading '-' are handled. Symlinks are never followed: find does not
# descend them, and each one is recorded in SCAN_SKIPPED.
traverse_target() {
  local dir=$1 full rel isdir excluded_dir=""

  SCAN_ROOT=$dir
  SCAN_FILES=()
  SCAN_SKIPPED=()
  traverse_load_ignore_patterns "$dir"

  # find lists parents before their children, so an ignored directory can be
  # recorded in excluded_dir and every entry under it skipped by prefix.
  while IFS= read -r -d '' full; do
    rel=${full#"$dir"/}

    if [ -n "$excluded_dir" ]; then
      case $rel in
        "$excluded_dir"/*) continue ;;
      esac
    fi

    if [ -L "$full" ]; then
      SCAN_SKIPPED[${#SCAN_SKIPPED[@]}]=$rel
      continue
    fi

    isdir=0
    [ -d "$full" ] && isdir=1

    if traverse_gitignore_excludes "$rel" "$isdir"; then
      continue
    fi
    if traverse_ignore_matches "$rel" "$isdir"; then
      [ "$isdir" -eq 1 ] && excluded_dir=$rel
      continue
    fi

    if [ "$isdir" -eq 1 ]; then
      continue
    elif [ -f "$full" ]; then
      SCAN_FILES[${#SCAN_FILES[@]}]=$rel
    else
      SCAN_SKIPPED[${#SCAN_SKIPPED[@]}]=$rel
    fi
  done < <(find "$dir" -mindepth 1 -type d \
    \( -name .git -o -name node_modules -o -name .venv -o -name vendor -o -name target -o -name dist \) \
    -prune -o -print0)
}

# Decides whether .gitignore excludes a path (spec 3.3, item 60). The current decision
# is that it never does, so a git-ignored file is still scanned. All .gitignore handling
# belongs in this function so the decision can change in one place.
# Arguments: relative path, 1 if it is a directory. Returns 0 if excluded.
traverse_gitignore_excludes() {
  return 1
}

# Reads .repo-shield-ignore from the target root. A symlinked ignore file is not
# read, because symlinks are not followed (spec 2.3). A missing file means no patterns.
traverse_load_ignore_patterns() {
  local file="$1/.repo-shield-ignore" line

  IGNORE_NEG=()
  IGNORE_DIRONLY=()
  IGNORE_ANCHORED=()
  IGNORE_RE=()

  [ -f "$file" ] && [ ! -L "$file" ] && [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    traverse_add_ignore_pattern "$line"
  done < "$file"
}

# Parses one gitignore-style line and stores it. Blank lines and '#' comments are
# skipped. Syntax (working assumption, spec 3.3 and progress.md TASK_03):
#   '!' prefix      re-includes a path matched by an earlier pattern
#   trailing '/'    matches directories only
#   '/' inside      anchors the pattern to the target root; otherwise the pattern
#                   matches the file or directory name at any depth
#   '*', '?', '[]', '**' globs. '*' and '?' do not cross '/'.
traverse_add_ignore_pattern() {
  local line=$1 neg=0 dironly=0 anchored=0

  line=${line%$'\r'}
  case $line in
    ''|'#'*) return 0 ;;
  esac
  if [ "${line:0:1}" = '!' ]; then
    neg=1
    line=${line:1}
  fi
  case $line in
    */)
      dironly=1
      line=${line%/}
      ;;
  esac
  case $line in
    */*) anchored=1 ;;
  esac
  line=${line#/}
  [ -n "$line" ] || return 0

  IGNORE_NEG[${#IGNORE_NEG[@]}]=$neg
  IGNORE_DIRONLY[${#IGNORE_DIRONLY[@]}]=$dironly
  IGNORE_ANCHORED[${#IGNORE_ANCHORED[@]}]=$anchored
  IGNORE_RE[${#IGNORE_RE[@]}]="^($(_traverse_glob_to_ere "$line"))\$"
}

# Returns 0 if a .repo-shield-ignore pattern excludes the path. Patterns are applied in
# order and the last match wins, so '!' can re-include a path.
# Arguments: relative path, 1 if it is a directory.
traverse_ignore_matches() {
  local rel=$1 isdir=$2 base target i=0 excluded=1

  base=${rel##*/}
  while [ "$i" -lt "${#IGNORE_RE[@]}" ]; do
    if [ "${IGNORE_DIRONLY[i]}" -eq 1 ] && [ "$isdir" -ne 1 ]; then
      i=$((i + 1))
      continue
    fi
    if [ "${IGNORE_ANCHORED[i]}" -eq 1 ]; then
      target=$rel
    else
      target=$base
    fi
    if [[ $target =~ ${IGNORE_RE[i]} ]]; then
      if [ "${IGNORE_NEG[i]}" -eq 1 ]; then
        excluded=1
      else
        excluded=0
      fi
    fi
    i=$((i + 1))
  done
  return "$excluded"
}

# Prints the POSIX ERE for one glob with the leading '!' and trailing '/' already removed.
# '*' and '?' do not match '/'. '**/' matches zero or more directories, and a trailing
# '/**' matches everything inside.
_traverse_glob_to_ere() {
  local glob=$1 out="" i=0 n=${#1} c rest body

  while [ "$i" -lt "$n" ]; do
    c=${glob:$i:1}
    case $c in
      '*')
        if [ "${glob:$((i + 1)):1}" = '*' ]; then
          if { [ "$i" -eq 0 ] || [ "${glob:$((i - 1)):1}" = / ]; } && [ "${glob:$((i + 2)):1}" = / ]; then
            out="$out(.*/)?"
            i=$((i + 3))
          else
            out="$out.*"
            i=$((i + 2))
          fi
          continue
        fi
        out="$out[^/]*"
        ;;
      '?') out="$out[^/]" ;;
      '[')
        rest=${glob:$((i + 1))}
        case $rest in
          *]*)
            body=${rest%%]*}
            case $body in
              !*) body="^${body#!}" ;;
            esac
            out="$out[$body]"
            i=$((i + ${#body} + 2))
            continue
            ;;
          *) out="$out\\[" ;;
        esac
        ;;
      '\')
        if [ $((i + 1)) -lt "$n" ]; then
          i=$((i + 1))
          out="$out$(_traverse_literal "${glob:$i:1}")"
        else
          out="$out\\\\"
        fi
        ;;
      *) out="$out$(_traverse_literal "$c")" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# Prints one character as a literal in a POSIX ERE.
_traverse_literal() {
  case $1 in
    '.'|'^'|'$'|'+'|'('|')'|'{'|'}'|'|'|'\'|'*'|'?'|'[') printf '\\%s' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}
