#!/bin/bash
# Software composition analysis manifest parsers for repo-shield (spec Section 4.1).
# Sourced by bin/repo-shield. Manifests are read as data only, with jq, awk, and the shell.
# Nothing in the scanned tree is executed, sourced, or evaluated.
#
# sca_parse_target parses every manifest in CLASSIFIED_MANIFEST (see classify.sh) and fills:
#   SCA_ECOSYSTEM  OSV ecosystem name: npm, Maven, or PyPI (item 15)
#   SCA_NAME       package name (Maven: groupId:artifactId)
#   SCA_VERSION    version, as pinned in the file
#   SCA_FILE       the manifest that gave the tuple, relative to SCAN_ROOT
#   SCA_WARN_FILE  and SCA_WARN_MSG: one warning per skipped entry or malformed file (spec 2.4)
# A tuple can repeat across files (for example package.json and package-lock.json). Removing
# duplicates is the caller's job, before the OSV query.
#
# Parsing rules and open items are in spec 4.1 and Section 9.10 (items 56, 57, 63).

SCA_ECOSYSTEM=()
SCA_NAME=()
SCA_VERSION=()
SCA_FILE=()
SCA_WARN_FILE=()
SCA_WARN_MSG=()

# sca_reset: clears every SCA_* array. sca_parse_target calls it first.
sca_reset() {
  SCA_ECOSYSTEM=()
  SCA_NAME=()
  SCA_VERSION=()
  SCA_FILE=()
  SCA_WARN_FILE=()
  SCA_WARN_MSG=()
}

# sca_add <ecosystem> <name> <version> <relative file>
sca_add() {
  SCA_ECOSYSTEM[${#SCA_ECOSYSTEM[@]}]=$1
  SCA_NAME[${#SCA_NAME[@]}]=$2
  SCA_VERSION[${#SCA_VERSION[@]}]=$3
  SCA_FILE[${#SCA_FILE[@]}]=$4
}

# sca_warn <relative file> <message>
sca_warn() {
  SCA_WARN_FILE[${#SCA_WARN_FILE[@]}]=$1
  SCA_WARN_MSG[${#SCA_WARN_MSG[@]}]=$2
}

# sca_regular <absolute path>: true for a regular file that is not a symlink (spec 2.3).
sca_regular() {
  [ -f "$1" ] && [ ! -L "$1" ]
}

# sca_take <ecosystem> <relative file>: reads "kind<TAB>name<TAB>value" lines on stdin.
# kind "ok" adds a tuple. kind "skip" records a warning with the reason in value.
sca_take() {
  local eco=$1 rel=$2 kind name val
  while IFS=$'\t' read -r kind name val; do
    case $kind in
      ok) sca_add "$eco" "$name" "$val" "$rel" ;;
      skip) sca_warn "$rel" "$name: $val" ;;
    esac
  done
}

# sca_parse_target: parses every manifest in CLASSIFIED_MANIFEST. Call after classify_target.
sca_parse_target() {
  local rel
  sca_reset
  for rel in "${CLASSIFIED_MANIFEST[@]}"; do
    sca_parse_file "$rel"
  done
}

# sca_parse_file <relative path>: dispatches by base name (spec 4.1).
sca_parse_file() {
  case ${1##*/} in
    package.json) sca_parse_package_json "$1" ;;
    package-lock.json) sca_parse_package_lock "$1" ;;
    pom.xml) sca_parse_pom "$1" ;;
    Pipfile.lock) sca_parse_pipfile_lock "$1" ;;
    requirements.txt) sca_parse_requirements "$1" ;;
  esac
}

# npm lock files. lockfileVersion 2 and 3 use "packages" (keyed by install path). Version 1 uses
# a nested "dependencies" tree. Both are read, so every version is covered (item 56, working
# assumption). The root entry (key "") and link entries are not installed packages and are
# skipped. Entries with no string version are skipped silently for the same reason.
_SCA_LOCK_JQ='
  def wlk:
    to_entries[]?
    | (if (.value.version | type) == "string"
       then ["ok", .key, .value.version] else empty end),
      (.value.dependencies | objects | wlk);
  if type != "object" then error("lock file is not a JSON object") else . end
  | if (.packages | type) == "object" then
      .packages | to_entries[]
      | select(.key != "" and .value.link != true and (.value.version | type) == "string")
      | ["ok", (.key | sub("^.*node_modules/"; "")), .value.version]
    else
      (.dependencies | objects | wlk)
    end
  | @tsv'

# sca_parse_package_lock <relative path>
sca_parse_package_lock() {
  local rel=$1 out
  if ! out=$(jq -r "$_SCA_LOCK_JQ" "$SCAN_ROOT/$rel" 2>/dev/null); then
    sca_warn "$rel" "malformed npm lock file, skipped"
    return 0
  fi
  sca_take npm "$rel" <<EOF
$out
EOF
}

# package.json, one file. An exact version (1.2.3, optionally with a pre-release or build tag)
# is a pin and is used as written. A range (^1.2.3, ~1, >=1, a tag, a URL) is resolved from a
# package-lock.json in the same directory when one exists and parses (item 14, option B).
# A range with no lock file is skipped with a warning (item 57, working assumption).
# The filter receives $lock as [object] when the lock is used, or null when it is not.
_SCA_PKG_JQ='
  def exact: type == "string"
    and test("^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.+-]*)?$");
  def locked($n):
    if $lock == null then null
    elif ($lock[0].packages | type) == "object" then $lock[0].packages["node_modules/" + $n].version
    elif ($lock[0].dependencies | type) == "object" then $lock[0].dependencies[$n].version
    else null end;
  if type != "object" then error("package.json is not a JSON object") else . end
  | [.dependencies, .devDependencies, .optionalDependencies][]
  | select(type == "object") | to_entries[]
  | if (.value | exact) then ["ok", .key, .value]
    elif (locked(.key) | type) == "string" then ["ok", .key, locked(.key)]
    else ["skip", .key, ("version range \(.value | tostring) with no lock file")] end
  | @tsv'

# sca_parse_package_json <relative path>
sca_parse_package_json() {
  local rel=$1 dir lock out
  case $rel in
    */*) dir=${rel%/*}/ ;;
    *) dir= ;;
  esac
  lock=$SCAN_ROOT/${dir}package-lock.json

  if sca_regular "$lock" && jq -e 'type == "object"' "$lock" >/dev/null 2>&1; then
    out=$(jq -r --slurpfile lock "$lock" "$_SCA_PKG_JQ" "$SCAN_ROOT/$rel" 2>/dev/null)
  else
    out=$(jq -r --argjson lock null "$_SCA_PKG_JQ" "$SCAN_ROOT/$rel" 2>/dev/null)
  fi
  if [ $? -ne 0 ]; then
    sca_warn "$rel" "malformed package.json, skipped"
    return 0
  fi
  sca_take npm "$rel" <<EOF
$out
EOF
}

# Pipfile.lock (item 56, working assumption): the single format Pipenv writes. The "default" and
# "develop" sections are both read. An entry counts only when its version is an exact pin ("==").
# Git, path, and editable entries have no version and are skipped with a warning.
_SCA_PIPFILE_JQ='
  if type != "object" then error("Pipfile.lock is not a JSON object") else . end
  | ((.default // {}) + (.develop // {})) | to_entries[]
  | (.value | if type == "object" then .version else null end) as $v
  | if ($v | type) == "string" and ($v | startswith("=="))
    then ["ok", .key, ($v | ltrimstr("=="))]
    else ["skip", .key, "no pinned version"] end
  | @tsv'

# sca_parse_pipfile_lock <relative path>
sca_parse_pipfile_lock() {
  local rel=$1 out
  if ! out=$(jq -r "$_SCA_PIPFILE_JQ" "$SCAN_ROOT/$rel" 2>/dev/null); then
    sca_warn "$rel" "malformed Pipfile.lock, skipped"
    return 0
  fi
  sca_take PyPI "$rel" <<EOF
$out
EOF
}

# sca_trim <value>: sets _SCA_TRIMMED to the value without leading or trailing whitespace.
sca_trim() {
  _SCA_TRIMMED=$1
  _SCA_TRIMMED=${_SCA_TRIMMED#"${_SCA_TRIMMED%%[![:space:]]*}"}
  _SCA_TRIMMED=${_SCA_TRIMMED%"${_SCA_TRIMMED##*[![:space:]]}"}
}

# requirements.txt (item 57, working assumption). Only "name==version" pins are used. Extras
# and environment markers are dropped. Ranges, bare names, URLs, and paths are skipped with a
# warning. Other option lines ("--index-url", "--hash") are skipped silently. "-r" and "-e"
# can add dependencies that are not read, so they get a warning.
# Trailing "\" continuations are handled by the same rules.
sca_parse_requirements() {
  local rel=$1 line re
  re='^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^]]*\])?[[:space:]]*==[[:space:]]*([^[:space:],*]+)$'

  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case $line in
      \#*) continue ;;
    esac
    line=${line%%[[:space:]]#*}
    line=${line%%;*}
    sca_trim "$line"; line=$_SCA_TRIMMED
    case $line in
      *\\) line=${line%\\}; sca_trim "$line"; line=$_SCA_TRIMMED ;;
    esac
    [ -n "$line" ] || continue
    case $line in
      -r*|--requirement*|-e*|--editable*)
        sca_warn "$rel" "not read, skipped: $line"
        continue ;;
      -*) continue ;;
    esac
    if [[ $line =~ $re ]]; then
      sca_add PyPI "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "$rel"
    else
      sca_warn "$rel" "no exact pin, skipped: $line"
    fi
  done < "$SCAN_ROOT/$rel"
}

# pom.xml (item 16A, parsed directly). A restricted parser: it reads only the direct
# <dependency> elements under <project><dependencies>. Dependencies inside
# <dependencyManagement>, <profiles>, <build>, <plugins>, and <exclusions> are not direct, so
# they are ignored. Comments are removed. Each tag is put on its own line, so text is read
# from the line after an opening tag. A version with "${" (a property) or no version is skipped
# with a warning (working assumption, not resolved from <properties>). A file that is not
# well-formed by these rules (unbalanced or mismatched tags, no <project>, unclosed comment)
# exits 1, so the caller drops all of its tuples and warns.
_SCA_POM_AWK='
  function trim(x) { sub(/^[ \t\r\n]+/, "", x); sub(/[ \t\r\n]+$/, "", x); return x }
  { s = s $0 "\n" }
  END {
    bad = 0
    while ((i = index(s, "<!--")) > 0) {
      rest = substr(s, i + 4)
      j = index(rest, "-->")
      if (j == 0) { bad = 1; break }
      s = substr(s, 1, i - 1) " " substr(rest, j + 3)
    }
    gsub(/</, "\n<", s)
    gsub(/>/, ">\n", s)
    n = split(s, lines, "\n")
    depth = 0; seen = 0; depDepth = 0; direct = 0; g = ""; a = ""; v = ""
    for (k = 1; k <= n && !bad; k++) {
      line = trim(lines[k])
      if (line == "") continue
      if (substr(line, 1, 1) != "<") {
        if (depDepth > 0 && depth == depDepth + 1) {
          if (el[depth] == "groupId") g = line
          else if (el[depth] == "artifactId") a = line
          else if (el[depth] == "version") v = line
        }
        continue
      }
      if (substr(line, 1, 2) == "<?" || substr(line, 1, 2) == "<!") continue
      if (substr(line, length(line) - 1, 2) == "/>") continue
      if (substr(line, 2, 1) == "/") {
        name = substr(line, 3)
        sub(/>$/, "", name)
        name = trim(name)
        if (depth == 0 || el[depth] != name) { bad = 1; break }
        if (name == "dependency" && depDepth == depth) {
          if (direct) {
            if (g == "" || a == "") printf "skip\t%s:%s\tno groupId or artifactId\n", g, a
            else if (v == "") printf "skip\t%s:%s\tno literal version\n", g, a
            else if (index(v, "${") > 0) printf "skip\t%s:%s\tversion is a property\n", g, a
            else printf "ok\t%s:%s\t%s\n", g, a, v
          }
          depDepth = 0; direct = 0; g = ""; a = ""; v = ""
        }
        depth--
        continue
      }
      name = substr(line, 2)
      sub(/>$/, "", name)
      sub(/[ \t].*$/, "", name)
      depth++
      el[depth] = name
      if (depth == 1 && name == "project") seen = 1
      if (name == "dependency") {
        direct = (depth >= 3 && el[depth - 1] == "dependencies" && el[depth - 2] == "project")
        depDepth = depth
        g = ""; a = ""; v = ""
      }
    }
    if (bad || depth != 0 || !seen) exit 1
  }'

# sca_parse_pom <relative path>
sca_parse_pom() {
  local rel=$1 out
  if ! out=$(awk "$_SCA_POM_AWK" "$SCAN_ROOT/$rel" 2>/dev/null); then
    sca_warn "$rel" "malformed pom.xml, skipped"
    return 0
  fi
  sca_take Maven "$rel" <<EOF
$out
EOF
}
