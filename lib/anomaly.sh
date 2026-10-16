#!/bin/bash
# Supply chain anomaly checks for repo-shield (spec Section 4.3): typosquatting indicators
# (TYPOSQUAT_SUSPECT, items 22 and 62) and dependency confusion risks (DEPENDENCY_CONFUSION_RISK,
# items 23 and 62). Sourced by bin/repo-shield, after sca.sh, popular.sh, report.sh, and
# severity.sh.
#
# anomaly_scan reads the SCA_* arrays (call sca_parse_target first) and stores findings with
# finding_add. It returns 1 with ANOM_ERROR set only when its temporary directory cannot be
# made. A popular-package list that cannot be loaded skips only the typosquat check, and a
# warning is recorded in SCA_WARN_* (spec 2.4). The string comparisons run in awk, because
# Bash 3.2 is too slow for them.
#
# Names are compared after normalization: lowercase, and each run of "-", "_", or "." becomes
# one "-". This is the PEP 503 rule, applied to every ecosystem.

ANOM_ERROR=""
ANOM_WORK=""

# anomaly_deps <file>: writes the unique "ecosystem<TAB>name<TAB>file" tuples, sorted.
anomaly_deps() {
  local i
  for i in "${!SCA_NAME[@]}"; do
    printf '%s\t%s\t%s\n' "${SCA_ECOSYSTEM[$i]}" "${SCA_NAME[$i]}" "${SCA_FILE[$i]}"
  done | sort -u > "$1"
}

# anomaly_typosquat <deps file>: flags PyPI dependencies that are one edit away from a popular
# package (spec 4.3). A name on the list is never flagged. A list name of 8 or more characters
# also allows two edits. The closest name wins, and ties go to the more downloaded name.
# The list is loaded only when a PyPI dependency exists, so other scans make no request.
anomaly_typosquat() {
  local deps=$1 list=$ANOM_WORK/popular.txt out=$ANOM_WORK/typo.tsv file name best

  awk -F'\t' '$1 == "PyPI" { found = 1; exit } END { exit !found }' "$deps" || return 0

  if ! popular_load "$list"; then
    sca_warn "" "typosquat check skipped: $POPULAR_ERROR"
    return 0
  fi

  # The first file is the list, so it must not be empty (FNR == NR would match the second file).
  awk -F'\t' '
    function norm(s) { s = tolower(s); gsub(/[-_.]+/, "-", s); return s }
    # Damerau-Levenshtein distance with adjacent transpositions (optimal string alignment) between
    # the dependency name (characters in A, length la) and list name i (characters in pch, length
    # plen[i]). Three rows are kept. It stops early, returning LIM + 1, once a whole row is above
    # LIM, because the distance cannot come back down.
    function dist(i,    lb, j, k, c, m, rmin) {
      lb = plen[i]
      for (j = 0; j <= lb; j++) P[j] = j
      for (k = 1; k <= la; k++) {
        Q[0] = k; rmin = k
        for (j = 1; j <= lb; j++) {
          c = (A[k] == pch[i, j]) ? 0 : 1
          m = P[j] + 1
          if (Q[j - 1] + 1 < m) m = Q[j - 1] + 1
          if (P[j - 1] + c < m) m = P[j - 1] + c
          if (k > 1 && j > 1 && A[k] == pch[i, j - 1] && A[k - 1] == pch[i, j] && PP[j - 2] + 1 < m) m = PP[j - 2] + 1
          Q[j] = m
          if (m < rmin) rmin = m
        }
        if (rmin > LIM) return LIM + 1
        for (j = 0; j <= lb; j++) { PP[j] = P[j]; P[j] = Q[j] }
      }
      return P[lb]
    }
    FNR == NR {
      p = norm($0)
      if (!(p in listed)) {
        listed[p] = 1
        top[++np] = p
        plen[np] = length(p)
        for (k = 1; k <= plen[np]; k++) pch[np, k] = substr(p, k, 1)
      }
      next
    }
    $1 == "PyPI" {
      n = norm($2)
      if (n in listed) next
      la = length(n)
      for (k = 1; k <= la; k++) A[k] = substr(n, k, 1)
      best = ""; bestd = 99
      for (i = 1; i <= np; i++) {
        lim = (plen[i] >= 8) ? 2 : 1
        gap = plen[i] - la; if (gap < 0) gap = -gap
        if (gap > lim) continue
        LIM = lim
        d = dist(i)
        if (d <= lim && d < bestd) { bestd = d; best = top[i] }
      }
      if (best != "") print $3 "\t" $2 "\t" best
    }
  ' "$list" "$deps" > "$out" || return 1

  while IFS=$'\t' read -r file name best; do
    severity_default TYPOSQUAT_SUSPECT
    finding_add TYPOSQUAT_SUSPECT "$_SEVERITY" "$file" "PyPI package '$name' is close to the popular package '$best' (possible typosquat)" || return 1
  done < "$out"
  return 0
}

# anomaly_confusion <deps file>: flags unscoped dependencies whose name starts with an internal
# prefix from --internal-prefix (spec 4.3, item 23). npm names that start with "@" are scoped and
# never flagged. For Maven, the prefix is matched against the groupId. Runs offline. Without
# prefixes, nothing runs.
anomaly_confusion() {
  local deps=$1 prefixes=$ANOM_WORK/prefixes.txt out=$ANOM_WORK/confusion.tsv file name prefix

  [ "${#CLI_INTERNAL_PREFIXES[@]}" -gt 0 ] || return 0
  printf '%s\n' "${CLI_INTERNAL_PREFIXES[@]}" > "$prefixes"

  # The first file is the prefix list, so it must not be empty (see anomaly_typosquat).
  awk -F'\t' '
    function norm(s) { s = tolower(s); gsub(/[-_.]+/, "-", s); return s }
    FNR == NR { raw[++np] = $0; pre[np] = norm($0); next }
    $1 == "npm" && substr($2, 1, 1) == "@" { next }
    {
      key = $2
      if ($1 == "Maven") sub(/:.*/, "", key)
      key = norm(key)
      for (i = 1; i <= np; i++) {
        if (index(key, pre[i]) == 1) { print $3 "\t" $2 "\t" raw[i]; break }
      }
    }
  ' "$prefixes" "$deps" > "$out" || return 1

  while IFS=$'\t' read -r file name prefix; do
    severity_default DEPENDENCY_CONFUSION_RISK
    finding_add DEPENDENCY_CONFUSION_RISK "$_SEVERITY" "$file" "'$name' starts with the internal prefix '$prefix' and is not scoped, so it could resolve from a public registry (dependency confusion risk)" || return 1
  done < "$out"
  return 0
}

# anomaly_scan: runs the anomaly checks on the tuples in the SCA_* arrays.
anomaly_scan() {
  local rc=0
  ANOM_ERROR=""
  ANOM_WORK=$(mktemp -d) || { ANOM_ERROR="could not create a temporary directory"; return 1; }

  anomaly_deps "$ANOM_WORK/deps.tsv"
  anomaly_typosquat "$ANOM_WORK/deps.tsv" || rc=1
  anomaly_confusion "$ANOM_WORK/deps.tsv" || rc=1

  rm -rf "$ANOM_WORK"
  return $rc
}
