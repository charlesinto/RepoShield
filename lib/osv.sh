#!/bin/bash
# OSV advisory lookup and missing lock file checks for repo-shield (spec Sections 4.2 and 4.3).
# Sourced by bin/repo-shield, after sca.sh and report.sh. Only package names, versions, and
# ecosystems are sent (spec 2.3). File paths and file contents never leave the machine.
#
# osv_scan runs the whole SCA lookup. It returns 1 and sets OSV_ERROR on any failure, so the
# caller exits 1 and never reports the SCA result as complete (spec 2.4). With --offline it does
# nothing and makes no network call.
#
# Severity of a matched advisory: the CVSS v3 base score from the advisory's vector, mapped to
# the four levels (spec 7.4, item 64): 9.0 to 10.0 CRITICAL, 7.0 to 8.9 HIGH, 4.0 to 6.9 MEDIUM,
# and 0.1 to 3.9 LOW. See severity_from_cvss_score and cvss3_base_score (lib/severity.sh).
#
# Still open (see progress.md):
#   - Item 61: the result cache is not built.
#   - Item 49: the timeouts below are placeholders.
#   - Item 15: OSV_BATCH_SIZE is a placeholder. The documented limit is not verified.
#   - An advisory with no CVSS v3 score (CVSS v4 only, or none) cannot be mapped. The scan fails
#     for it until the spec says what to do.

OSV_QUERY_URL=https://api.osv.dev/v1/querybatch
OSV_VULN_URL=https://api.osv.dev/v1/vulns
OSV_BATCH_SIZE=100
OSV_CONNECT_TIMEOUT=10
OSV_MAX_TIME=60
OSV_MAX_ROUNDS=100
OSV_ERROR=""
OSV_HTTP_CODE=""
OSV_VECTOR=""

# osv_http_post <request body file> <response file>: POSTs the body to OSV and sets OSV_HTTP_CODE.
# Returns 1 when curl itself fails (unreachable, timeout). Tests replace this function, so the
# parsing and failure paths run without a network call.
osv_http_post() {
  if ! OSV_HTTP_CODE=$(curl -sS --proto '=https' --proto-redir '=https' \
    --connect-timeout "$OSV_CONNECT_TIMEOUT" --max-time "$OSV_MAX_TIME" \
    -H 'Content-Type: application/json' --data-binary "@$1" \
    -o "$2" -w '%{http_code}' "$OSV_QUERY_URL" 2>/dev/null); then
    return 1
  fi
  return 0
}

# osv_http_get <url> <response file>: GETs an advisory and sets OSV_HTTP_CODE. Same rules as
# osv_http_post.
osv_http_get() {
  if ! OSV_HTTP_CODE=$(curl -sS --proto '=https' --proto-redir '=https' \
    --connect-timeout "$OSV_CONNECT_TIMEOUT" --max-time "$OSV_MAX_TIME" \
    -o "$2" -w '%{http_code}' "$1" 2>/dev/null); then
    return 1
  fi
  return 0
}

# osv_fail <message>: sets OSV_ERROR and returns 1.
osv_fail() {
  OSV_ERROR=$1
  return 1
}

# osv_check_code: returns 0 for HTTP 200. Otherwise sets OSV_ERROR and returns 1 (spec 2.4).
osv_check_code() {
  case $OSV_HTTP_CODE in
    200) return 0 ;;
    429) osv_fail "OSV rate-limited the request (HTTP 429)" ;;
    *) osv_fail "OSV returned HTTP $OSV_HTTP_CODE" ;;
  esac
}

# osv_advisory_vector <advisory ID>: sets OSV_VECTOR to the advisory's CVSS v3 vector, or to
# nothing when it has none. The advisory is fetched once per scan and kept in OSV_WORK. The ID
# goes into the URL, so it is checked against a safe character set first.
osv_advisory_vector() {
  local id=$1 file
  OSV_VECTOR=""
  case $id in
    "" | *[!A-Za-z0-9._-]*) osv_fail "advisory ID is not valid: '$id'"; return 1 ;;
  esac
  file=$OSV_WORK/vuln.$id.json
  if [ ! -f "$file" ]; then
    if ! osv_http_get "$OSV_VULN_URL/$id" "$file"; then
      osv_fail "OSV is unreachable or timed out"
      return 1
    fi
    osv_check_code || return 1
  fi
  if ! OSV_VECTOR=$(jq -r '[.severity[]? | select(.type == "CVSS_V3") | .score] | .[0] // empty' "$file" 2>/dev/null); then
    osv_fail "OSV advisory could not be parsed: $id"
    return 1
  fi
  return 0
}

# osv_query_all <unique file> <matches file>: queries every unique "ecosystem<TAB>name<TAB>version"
# line, in batches of OSV_BATCH_SIZE. Pages with next_page_token are queried again with that
# token. Writes "index<TAB>advisory ID" to the matches file, where index is the 1-based line in
# the unique file. Any failure returns 1 with OSV_ERROR set, and no partial result is kept.
osv_query_all() {
  local uniq=$1 matches=$2 pending round rdir chunk count status

  pending=$OSV_WORK/pending.tsv
  awk '{ print NR "\t" }' "$uniq" > "$pending"
  : > "$matches"

  round=0
  while [ -s "$pending" ]; do
    round=$((round + 1))
    if [ "$round" -gt "$OSV_MAX_ROUNDS" ]; then
      osv_fail "OSV paging did not finish after $OSV_MAX_ROUNDS rounds"
      return 1
    fi
    rdir=$OSV_WORK/round$round
    mkdir "$rdir" || return 1
    split -l "$OSV_BATCH_SIZE" "$pending" "$rdir/c" || return 1
    : > "$OSV_WORK/next.tsv"

    for chunk in "$rdir"/c*; do
      count=$(awk 'END { print NR }' "$chunk")
      # Request lines: ecosystem, name, version, page token (empty on the first page).
      awk -F'\t' 'FNR == NR { u[FNR] = $0; next } { print u[$1] "\t" $2 }' "$uniq" "$chunk" > "$chunk.req" || return 1
      jq -Rn '{queries: [inputs | split("\t")
        | {package: {name: .[1], ecosystem: .[0]}, version: .[2]}
          + (if .[3] == "" then {} else {page_token: .[3]} end)]}' "$chunk.req" > "$chunk.body" || return 1

      if ! osv_http_post "$chunk.body" "$chunk.resp"; then
        osv_fail "OSV is unreachable or timed out"
        return 1
      fi
      osv_check_code || return 1

      # One line per advisory ("M") and per next page ("N"), indexed by result position.
      if ! jq -r --argjson n "$count" '
        if (.results | type) != "array" or (.results | length) != $n
        then error("result count does not match the query count") else . end
        | .results | to_entries[] | . as $e
        | ( ($e.value.vulns // [])[]
            | "M\t\($e.key)\t\(.id | if type == "string" then . else error("advisory has no id") end)" ),
          ( $e.value.next_page_token // empty | "N\t\($e.key)\t\(.)" )
      ' "$chunk.resp" > "$chunk.parsed" 2>/dev/null; then
        osv_fail "OSV response could not be parsed"
        return 1
      fi

      # Map result positions back to unique-file indexes, using the chunk's line order.
      awk -F'\t' -v m="$matches" -v n="$OSV_WORK/next.tsv" '
        FNR == NR { c[FNR - 1] = $1; next }
        $1 == "M" { print c[$2] "\t" $3 >> m }
        $1 == "N" { print c[$2] "\t" $3 >> n }
      ' "$chunk" "$chunk.parsed" || return 1
    done
    pending=$OSV_WORK/next.tsv
  done
  sort -u "$matches" -o "$matches"
  return 0
}

# osv_collect <unique file> <occurrences file>: builds the unique and occurrence lists from the
# SCA_* arrays. Occurrences keep the file each tuple came from.
osv_collect() {
  local i
  : > "$2"
  for i in "${!SCA_NAME[@]}"; do
    printf '%s\t%s\t%s\t%s\n' "${SCA_ECOSYSTEM[$i]}" "${SCA_NAME[$i]}" "${SCA_VERSION[$i]}" "${SCA_FILE[$i]}"
  done > "$2"
  cut -f1-3 "$2" | sort -u > "$1"
}

# osv_report_matches <unique file> <matches file> <occurrences file>: one VULNERABLE_DEPENDENCY
# finding per advisory and per file that has the package. Severity comes from the advisory's CVSS
# v3 base score (item 64). Returns 1 with OSV_ERROR set when the advisory cannot be fetched,
# has no CVSS v3 vector, or its vector cannot be scored.
osv_report_matches() {
  local keyed=$OSV_WORK/keyed.tsv hits=$OSV_WORK/hits.tsv eco name ver file id score

  [ -s "$2" ] || return 0
  awk -F'\t' 'FNR == NR { k[FNR] = $0; next } { print k[$1] "\t" $2 }' "$1" "$2" > "$keyed"
  awk -F'\t' '
    FNR == NR { key = $1 "\t" $2 "\t" $3; cnt[key]++; m[key, cnt[key]] = $4; next }
    { key = $1 "\t" $2 "\t" $3; for (j = 1; j <= cnt[key]; j++) print $0 "\t" m[key, j] }
  ' "$keyed" "$3" > "$hits"

  while IFS=$'\t' read -r eco name ver file id; do
    osv_advisory_vector "$id" || return 1
    if [ -z "$OSV_VECTOR" ]; then
      osv_fail "advisory $id has no CVSS v3 score, so its severity cannot be mapped (item 64)"
      return 1
    fi
    if ! score=$(cvss3_base_score "$OSV_VECTOR") || ! severity_from_cvss_score "$score"; then
      osv_fail "advisory $id has a CVSS vector that cannot be scored (only CVSS v3.0 and v3.1 are supported): $OSV_VECTOR"
      return 1
    fi
    finding_add VULNERABLE_DEPENDENCY "$_SEVERITY" "$file" "$name $ver ($eco) is affected by advisory $id (CVSS $score)" || return 1
  done < "$hits"
  return 0
}

# osv_missing_lockfiles: a package.json with no package-lock.json beside it gets a
# MISSING_LOCKFILE finding (spec 4.3, LOW). requirements.txt and pom.xml are not checked yet.
osv_missing_lockfiles() {
  local rel dir lock
  for rel in "${CLASSIFIED_MANIFEST[@]}"; do
    [ "${rel##*/}" = package.json ] || continue
    case $rel in
      */*) dir=${rel%/*}/ ;;
      *) dir= ;;
    esac
    lock=$SCAN_ROOT/${dir}package-lock.json
    if ! sca_regular "$lock"; then
      severity_default MISSING_LOCKFILE
      finding_add MISSING_LOCKFILE "$_SEVERITY" "$rel" "package.json has no package-lock.json beside it, so its dependency versions are not pinned"
    fi
  done
}

# osv_scan_run: the body of osv_scan. Uses OSV_WORK for temporary files.
osv_scan_run() {
  local uniq=$OSV_WORK/unique.tsv occ=$OSV_WORK/occurrences.tsv matches=$OSV_WORK/matches.tsv

  osv_missing_lockfiles
  osv_collect "$uniq" "$occ"
  [ -s "$uniq" ] || return 0
  osv_query_all "$uniq" "$matches" || return 1
  osv_report_matches "$uniq" "$matches" "$occ" || return 1
  return 0
}

# osv_scan: runs the SCA lookup on the tuples in the SCA_* arrays (call sca_parse_target first).
# Skipped entirely with --offline (spec 8.2). Returns 1 with OSV_ERROR set on failure.
osv_scan() {
  local rc
  OSV_ERROR=""
  [ "${CLI_OFFLINE:-0}" -eq 1 ] && return 0

  OSV_WORK=$(mktemp -d) || return 1
  osv_scan_run
  rc=$?
  rm -rf "$OSV_WORK"
  return $rc
}
