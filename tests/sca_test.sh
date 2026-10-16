#!/bin/bash
# Acceptance checks for TASK_07 (SCA manifest parsers, spec Section 4.1).
# Run with /bin/bash so the Bash 3.2 requirement is tested: tests/sca_test.sh

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
FIXTURES=$ROOT/tests/fixtures/sca
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# parse <dir>: runs traverse, classify, and the SCA parsers in a fresh shell on one target.
# Prints one sorted line per tuple ("T ecosystem name version file") and per warning
# ("W file message"). Paths are relative to the target.
parse() {
  /bin/bash -c '. "$1/lib/traverse.sh"; . "$1/lib/classify.sh"; . "$1/lib/sca.sh"
    traverse_target "$2"; classify_target; sca_parse_target
    for i in "${!SCA_NAME[@]}"; do
      echo "T ${SCA_ECOSYSTEM[$i]} ${SCA_NAME[$i]} ${SCA_VERSION[$i]} ${SCA_FILE[$i]}"
    done
    for i in "${!SCA_WARN_MSG[@]}"; do
      echo "W ${SCA_WARN_FILE[$i]} ${SCA_WARN_MSG[$i]}"
    done' _ "$ROOT" "$1" | sort
}

# check <name> <got> <want>
check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    echo "    got:"
    echo "$2" | sed 's/^/      /'
    echo "    want:"
    echo "$3" | sed 's/^/      /'
  fi
}

# lock file versions: v1 (nested "dependencies"), v2 (both sections), v3 ("packages" only).
# package.json ranges are resolved from the lock. Entries with no version are skipped silently.
check "npm lockfile v1 and package.json" "$(parse "$FIXTURES/npm-lock-v1")" "$(sort <<'EOF'
T npm body-parser 1.20.1 package-lock.json
T npm express 4.18.2 package-lock.json
T npm express 4.18.2 package.json
T npm left-pad 1.3.0 package-lock.json
T npm left-pad 1.3.0 package.json
T npm lodash 4.17.20 package-lock.json
T npm lodash 4.17.20 package.json
EOF
)"

check "npm lockfile v2 (packages and dependencies)" "$(parse "$FIXTURES/npm-lock-v2")" "$(sort <<'EOF'
T npm @scope/pkg 2.0.0 package-lock.json
T npm b 0.5.0 package-lock.json
T npm left-pad 1.3.0 package-lock.json
EOF
)"

check "npm lockfile v3 and range resolved from it" "$(parse "$FIXTURES/npm-lock-v3")" "$(sort <<'EOF'
T npm @scope/pkg 2.1.0 package-lock.json
T npm @scope/pkg 2.1.0 package.json
EOF
)"

# No lock file: ranges and tags are skipped with a warning. Exact pins are used as written.
check "npm package.json with no lock file" "$(parse "$FIXTURES/npm-no-lock")" "$(sort <<'EOF'
T npm lodash 4.17.20 package.json
W package.json express: version range ^4.18.0 with no lock file
W package.json tagged: version range latest with no lock file
EOF
)"

# A lock file that does not parse is reported. package.json then falls back to the no-lock rules.
check "npm malformed lock file" "$(parse "$FIXTURES/npm-malformed-lock")" "$(sort <<'EOF'
T npm lodash 4.17.20 package.json
W package-lock.json malformed npm lock file, skipped
W package.json express: version range ^4.18.0 with no lock file
EOF
)"

# pom.xml: only direct dependencies with a literal version. Managed, profile, plugin, excluded,
# and property versions are not read. A property or missing version is skipped with a warning.
check "pom.xml direct dependencies" "$(parse "$FIXTURES/pom")" "$(sort <<'EOF'
T Maven junit:junit 4.13.2 pom.xml
T Maven org.apache.commons:commons-lang3 3.12.0 pom.xml
W pom.xml com.example:bom-managed: no literal version
W pom.xml org.springframework:spring-core: version is a property
EOF
)"

# A pom.xml with mismatched tags is malformed: no tuples from it, and one warning.
check "pom.xml malformed" "$(parse "$FIXTURES/pom-malformed")" "$(sort <<'EOF'
W pom.xml malformed pom.xml, skipped
EOF
)"

# Pipfile.lock: "default" and "develop" are read, and a name in both is kept once.
check "Pipfile.lock default and develop" "$(parse "$FIXTURES/pipfile")" "$(sort <<'EOF'
T PyPI pytest 7.4.0 Pipfile.lock
T PyPI requests 2.28.1 Pipfile.lock
W Pipfile.lock mylib: no pinned version
EOF
)"

# requirements.txt: only name==version pins. Extras, markers, comments, hashes, and "\"
# continuations are handled. Ranges, bare names, -r, and -e are skipped with a warning.
check "requirements.txt pins and skips" "$(parse "$FIXTURES/requirements")" "$(sort <<'EOF'
T PyPI Django 4.2.7 requirements.txt
T PyPI flask 2.3.2 requirements.txt
T PyPI pyyaml 6.0.1 requirements.txt
T PyPI requests 2.28.1 requirements.txt
W requirements.txt no exact pin, skipped: numpy>=1.24
W requirements.txt no exact pin, skipped: six
W requirements.txt not read, skipped: -e git+https://example.invalid/repo.git#egg=thing
W requirements.txt not read, skipped: -r base.txt
EOF
)"

# A symlinked lock file is not read (spec 2.3). The range in package.json is then unresolved.
X=$WORK/symlink-lock
mkdir -p "$X"
printf '%s\n' '{"dependencies":{"express":"^4.18.0"}}' > "$X/package.json"
ln -s "$FIXTURES/npm-lock-v1/package-lock.json" "$X/package-lock.json"
check "symlinked lock file is not read" "$(parse "$X")" "$(sort <<'EOF'
W package.json express: version range ^4.18.0 with no lock file
EOF
)"

# A name with a space stays one field, because the tab-separated lines are split on tabs only.
X=$WORK/odd-names
mkdir -p "$X"
printf '%s\n' '{"dependencies":{"@scope/with space":"1.0.0"}}' > "$X/package.json"
check "names with spaces are kept whole" "$(parse "$X")" "$(sort <<'EOF'
T npm @scope/with space 1.0.0 package.json
EOF
)"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
