#!/bin/bash
# Acceptance checks for TASK_04 (file classification, spec Section 2).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/classify_test.sh

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# category <extensions> <relative path>: prints the category for one path in a fresh shell.
# <extensions> is a space-separated list for CLASSIFY_SOURCE_EXTS. It may be empty.
category() {
  /bin/bash -c '. "$1/lib/classify.sh"; CLASSIFY_SOURCE_EXTS=($2); classify_path "$3"; printf %s "$CLASSIFY_RESULT"' \
    _ "$ROOT" "$1" "$2"
}

# classify <dir> <extensions>: runs traverse_target and classify_target in a fresh shell.
# Prints one line per classified file, sorted. Names are printed with %q.
classify() {
  /bin/bash -c '. "$1/lib/traverse.sh"; . "$1/lib/classify.sh"; CLASSIFY_SOURCE_EXTS=($3)
    traverse_target "$2"; classify_target
    for f in "${CLASSIFIED_MANIFEST[@]}"; do printf "manifest %q\n" "$f"; done
    for f in "${CLASSIFIED_SOURCE[@]}"; do printf "source %q\n" "$f"; done
    for f in "${CLASSIFIED_LIFECYCLE[@]}"; do printf "lifecycle %q\n" "$f"; done' _ "$ROOT" "$1" "$2" | sort
}

# check <name> <got> <want>
check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    echo "    got:  [$2]"
    echo "    want: [$3]"
  fi
}

# Manifests and lock files are classified by exact name, at any depth (spec 4.1).
for p in package.json package-lock.json pom.xml Pipfile.lock requirements.txt \
  services/api/package.json "deep/er/pom.xml"; do
  check "manifest by name: $p" "$(category "" "$p")" "manifest"
done

# Lifecycle files are classified by exact name, at any depth (spec 6.1).
for p in setup.py setup.cfg build.rs Makefile tools/Makefile; do
  check "lifecycle by name: $p" "$(category "" "$p")" "lifecycle"
done

# Near-miss names are not classified (exact match only).
for p in package.json.bak my-package.json requirements-dev.txt makefile Makefile.bak \
  pom.xml.orig setup.py.disabled "my setup.py" py; do
  check "near-miss name is unclassified: $p" "$(category "" "$p")" ""
done

# Item 19 is open, so the source extension list is empty. Source files are not classified yet.
check "source file is unclassified while item 19 is open" "$(category "" "main.py")" ""
check "source file with no list is unclassified" "$(category "" "app.js")" ""

# With extensions set, a source file is classified by its extension.
check "source by extension" "$(category "py js" "lib/main.py")" "source"
check "extension match is exact" "$(category "py" "main.pyc")" ""

# Precedence: name rules win over the extension rule, so each file is in one category only.
check "setup.py is lifecycle, not source" "$(category "py" "setup.py")" "lifecycle"
check "package.json is manifest, not source" "$(category "json" "package.json")" "manifest"

# A name with no dot is not treated as an extension.
check "dotless name is not an extension match" "$(category "py" "py")" ""

# Each file is in at most one category, and unmatched files are left out. Fixture tree.
F="$WORK/fixtures"
mkdir -p "$F/app/src" "$F/app/tools" "$F/docs"
touch "$F/app/package.json" "$F/app/package-lock.json" "$F/app/src/index.js" \
  "$F/app/src/setup.py" "$F/app/setup.py" "$F/app/Makefile" "$F/app/tools/build.rs" \
  "$F/docs/readme.md" "$F/app/package.json.bak"
check "fixture tree: one category per file, unmatched files left out" \
  "$(classify "$F" "js py")" \
  "$(printf '%s\n' \
    "lifecycle app/Makefile" \
    "lifecycle app/setup.py" \
    "lifecycle app/tools/build.rs" \
    "lifecycle app/src/setup.py" \
    "manifest app/package-lock.json" \
    "manifest app/package.json" \
    "source app/src/index.js" | sort)"

# With the list empty (item 19 open), only names are classified.
check "fixture tree with empty source list" \
  "$(classify "$F" "")" \
  "$(printf '%s\n' \
    "lifecycle app/Makefile" \
    "lifecycle app/setup.py" \
    "lifecycle app/tools/build.rs" \
    "lifecycle app/src/setup.py" \
    "manifest app/package-lock.json" \
    "manifest app/package.json" | sort)"

# Classification reads names only. A Makefile in the tree must not run (spec 2.3).
X="$WORK/noexec"
mkdir -p "$X"
printf 'touch "%s/executed-marker"\n' "$WORK" > "$X/Makefile"
printf 'touch "%s/sourced-marker"\n' "$WORK" > "$X/setup.py"
classify "$X" "py" >/dev/null
if [ -e "$WORK/executed-marker" ] || [ -e "$WORK/sourced-marker" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: a classified file was executed or sourced"
else
  PASS=$((PASS + 1))
fi

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
