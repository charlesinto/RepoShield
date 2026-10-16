#!/bin/bash
# Acceptance checks for TASK_03 (ignore rules and safe traversal, spec 2.3, 3.2, 3.3).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/traverse_test.sh

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# scan <dir>: runs traverse_target in a fresh shell and prints one line per entry.
# Names are printed with %q, so a name with a newline still takes one line.
scan() {
  /bin/bash -c '. "$1/lib/traverse.sh"; traverse_target "$2"
    for f in "${SCAN_FILES[@]}"; do printf "F %q\n" "$f"; done
    for f in "${SCAN_SKIPPED[@]}"; do printf "S %q\n" "$f"; done' _ "$ROOT" "$1" | sort
}

# want <kind> <name>...: the scan lines expected for files (F) or skipped entries (S).
want() {
  local kind=$1 name
  shift
  for name in "$@"; do printf '%s %q\n' "$kind" "$name"; done | sort
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

# Built-in exclusions (spec 3.2). Excluded at any depth, but only when they are directories.
B="$WORK/builtin"
mkdir -p "$B/node_modules/p" "$B/.git" "$B/.venv" "$B/vendor" "$B/target" "$B/dist" "$B/pkg/vendor" "$B/src"
touch "$B/node_modules/p/x.js" "$B/.git/config" "$B/.venv/a.py" "$B/vendor/v.go" "$B/target/t.rs" \
  "$B/dist/d.js" "$B/pkg/vendor/p.go" "$B/src/dist-notes.txt" "$B/src/target.txt" "$B/src/vendor.txt"
check "built-in directories are skipped at any depth" \
  "$(scan "$B")" "$(want F src/dist-notes.txt src/target.txt src/vendor.txt)"

# A regular file named like a built-in directory is still scanned.
N="$WORK/named-files"
mkdir -p "$N/src"
touch "$N/dist" "$N/src/node_modules"
check "files named like built-in directories are scanned" \
  "$(scan "$N")" "$(want F dist src/node_modules)"

# The target itself may be named like a built-in directory.
mkdir -p "$WORK/root-named/dist"
touch "$WORK/root-named/dist/a.js"
check "target directory named dist is scanned" \
  "$(scan "$WORK/root-named/dist")" "$(want F a.js)"

# .repo-shield-ignore (spec 3.3). Working syntax: gitignore-style globs.
I="$WORK/ignored"
mkdir -p "$I/secret" "$I/docs/deep" "$I/a/b/cache" "$I/src"
touch "$I/secret/a.txt" "$I/app.log" "$I/keep.log" "$I/top.txt" "$I/sub.top.txt" \
  "$I/docs/a.md" "$I/docs/deep/b.md" "$I/a/b/cache/c" "$I/src/a.md"
printf '%s\n' "# comment line" "" "secret/" "*.log" "/top.txt" "!keep.log" "docs/*.md" "**/cache" > "$I/.repo-shield-ignore"
check "ignore file excludes directories, globs, anchored paths, and re-includes" \
  "$(scan "$I")" "$(want F .repo-shield-ignore keep.log sub.top.txt docs/deep/b.md src/a.md)"

# .gitignore never excludes a file (spec 3.3, item 60). Git-ignored files are still scanned.
G="$WORK/gitignored"
mkdir -p "$G/build"
touch "$G/ignored.txt" "$G/build/out.js"
printf '%s\n' "ignored.txt" "build/" > "$G/.gitignore"
check "git-ignored files are still scanned" \
  "$(scan "$G")" "$(want F .gitignore build/out.js ignored.txt)"

# Symlinks are recorded as skipped and never followed (spec 2.3, item 9).
mkdir -p "$WORK/outside/sub" "$WORK/sym/repo/dir"
touch "$WORK/outside/secret.txt" "$WORK/outside/sub/s.txt" "$WORK/sym/repo/real.txt"
ln -s "$WORK/outside" "$WORK/sym/repo/link-dir"
ln -s "$WORK/outside/secret.txt" "$WORK/sym/repo/link-file"
ln -s "../../../outside" "$WORK/sym/repo/dir/link-in-dir"
check "symlinks are skipped and their targets are not walked" \
  "$(scan "$WORK/sym/repo")" "$({ want F real.txt; want S link-dir link-file dir/link-in-dir; } | sort)"

# A symlinked .repo-shield-ignore is not read.
mkdir -p "$WORK/ignlink"
printf '%s\n' "*.txt" > "$WORK/outside/ign"
ln -s "$WORK/outside/ign" "$WORK/ignlink/.repo-shield-ignore"
touch "$WORK/ignlink/a.txt"
check "symlinked ignore file is not read" \
  "$(scan "$WORK/ignlink")" "$({ want F a.txt; want S .repo-shield-ignore; } | sort)"

# Hostile names are listed exactly. Each name is one NUL-delimited record, so a newline
# or a quote cannot split or end it (spec 2.3, item 8).
H="$WORK/hostile"
mkdir -p "$H/cwd"
touch "$H/a b.txt" "$H/-rf.js" "$H/it's \"q\".js" "$H/\$(touch ran-subst).sh" "$H/\`touch ran-tick\`.js"
touch "$H/back\\slash.js" "$H/"$'new\nline.js'
check "hostile file names are listed exactly" \
  "$(scan "$H")" "$(want F 'a b.txt' -rf.js "it's \"q\".js" '$(touch ran-subst).sh' '`touch ran-tick`.js' 'back\slash.js' $'new\nline.js')"

# No file is executed, sourced, or evaluated (spec 2.3, item 7). Scripts and hostile names
# in the tree must leave no trace. The scan runs from an empty directory, so a command
# substitution in a name would create a file there.
X="$WORK/noexec"
mkdir -p "$X" "$WORK/cwd-noexec"
printf '#!/bin/sh\ntouch "%s/executed-marker"\n' "$WORK" > "$X/run.sh"
chmod +x "$X/run.sh"
printf 'touch "%s/sourced-marker"\n' "$WORK" > "$X/load.sh"
touch "$X/\$(touch ran-subst).sh"
(cd "$WORK/cwd-noexec" && scan "$X" >/dev/null)
if [ -e "$WORK/executed-marker" ] || [ -e "$WORK/sourced-marker" ] || [ -n "$(ls -A "$WORK/cwd-noexec")" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: a file in the tree was executed or sourced"
else
  PASS=$((PASS + 1))
fi

# Files are not skipped by size, and binary files are scanned as text (spec 2.3, items 12, 55).
Z="$WORK/large"
mkdir -p "$Z"
head -c 6000000 /dev/zero > "$Z/big.bin"
printf 'a\0b\n' > "$Z/bin.dat"
check "large and binary files are listed" \
  "$(scan "$Z")" "$(want F big.bin bin.dat)"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
