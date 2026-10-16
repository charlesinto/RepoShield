#!/bin/bash
# Popular-package reference list for the typosquat check (spec Section 4.3, items 22, 67, and 68).
# Sourced by bin/repo-shield, before anomaly.sh. Only PyPI has a list in this version.
#
# popular_load <destination> writes the list to the destination, one name per line, most
# downloaded first. It uses the cache when the cache is less than POPULAR_TTL_MIN minutes old.
# Otherwise, it fetches the list (unless --offline) and refreshes the cache. It returns 1 with
# POPULAR_ERROR set when there is no usable list. The caller then skips the typosquat check.
#
# A list is fetched only when a scan has a PyPI dependency (see anomaly.sh), so a scan with no
# PyPI dependencies makes no request.

POPULAR_PYPI_URL=https://hugovk.dev/top-pypi-packages/top-pypi-packages-30-days.json
POPULAR_TOP_N=1000
POPULAR_TTL_MIN=240
POPULAR_CONNECT_TIMEOUT=10
POPULAR_MAX_TIME=60
POPULAR_ERROR=""
POPULAR_HTTP_CODE=""

# popular_cache_file: prints the cache file for the PyPI list. The cache lives under
# $XDG_CACHE_HOME, or ~/.cache when that is not set (spec 4.3).
popular_cache_file() {
  printf '%s/repo-shield/pypi-top-%s.txt\n' "${XDG_CACHE_HOME:-$HOME/.cache}" "$POPULAR_TOP_N"
}

# popular_http_get <url> <response file>: GETs the list and sets POPULAR_HTTP_CODE. Returns 1
# when curl itself fails. Tests replace this function, so no test makes a network call.
popular_http_get() {
  if ! POPULAR_HTTP_CODE=$(curl -sSL --proto '=https' --proto-redir '=https' --max-redirs 3 \
    --connect-timeout "$POPULAR_CONNECT_TIMEOUT" --max-time "$POPULAR_MAX_TIME" \
    -o "$2" -w '%{http_code}' "$1" 2>/dev/null); then
    return 1
  fi
  return 0
}

# popular_fresh <file>: true when the file exists, is not empty, and is less than
# POPULAR_TTL_MIN minutes old.
popular_fresh() {
  [ -s "$1" ] && [ -n "$(find "$1" -mmin "-$POPULAR_TTL_MIN" 2>/dev/null)" ]
}

# popular_fetch <destination>: fetches the PyPI list, keeps the POPULAR_TOP_N most downloaded
# names that are plain package names, and stores them at the destination. Then it refreshes the
# cache. A cache that cannot be written does not fail the scan.
popular_fetch() {
  local dest=$1 raw=$1.json names=$1.names cache dir
  POPULAR_ERROR=""

  if ! popular_http_get "$POPULAR_PYPI_URL" "$raw"; then
    POPULAR_ERROR="the popular-package list could not be fetched (unreachable or timed out)"
    return 1
  fi
  if [ "$POPULAR_HTTP_CODE" != 200 ]; then
    POPULAR_ERROR="the popular-package list returned HTTP $POPULAR_HTTP_CODE"
    return 1
  fi
  if ! jq -r --argjson n "$POPULAR_TOP_N" '
      if (.rows | type) != "array" then error("no rows array") else . end
      | .rows | sort_by(-.download_count) | .[:$n][] | .project | select(type == "string")
    ' "$raw" > "$names" 2>/dev/null; then
    POPULAR_ERROR="the popular-package list could not be parsed"
    return 1
  fi
  awk '/^[A-Za-z0-9._-]+$/' "$names" > "$dest"
  if [ ! -s "$dest" ]; then
    POPULAR_ERROR="the popular-package list contained no package names"
    return 1
  fi

  cache=$(popular_cache_file)
  dir=${cache%/*}
  if mkdir -p "$dir" 2>/dev/null && cp "$dest" "$cache.$$" 2>/dev/null; then
    mv -f "$cache.$$" "$cache" 2>/dev/null || rm -f "$cache.$$"
  fi
  return 0
}

# popular_load <destination>: see the top of this file. Returns 1 with POPULAR_ERROR set when
# there is no usable list.
popular_load() {
  local dest=$1 cache
  POPULAR_ERROR=""
  cache=$(popular_cache_file)

  if popular_fresh "$cache" && cp "$cache" "$dest" 2>/dev/null; then
    return 0
  fi
  if [ "${CLI_OFFLINE:-0}" -eq 1 ]; then
    POPULAR_ERROR="--offline, and no list cached in the last $POPULAR_TTL_MIN minutes"
    return 1
  fi
  popular_fetch "$dest"
}
