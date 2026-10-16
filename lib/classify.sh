#!/bin/bash
# File classification for repo-shield (spec Section 2). Sourced by bin/repo-shield.
# Each file goes to at most one category. Matching uses the file name only, never the content,
# so no file is opened or run here.
#
# classify_target fills these arrays from SCAN_FILES (see traverse.sh):
#   CLASSIFIED_MANIFEST   manifests and lock files
#   CLASSIFIED_SOURCE     source code
#   CLASSIFIED_LIFECYCLE  lifecycle and build scripts
# A file that matches no rule is left out of all three and is not scanned.

# Exact base names, matched at any depth (spec 4.1, 6.1).
CLASSIFY_MANIFEST_NAMES=(package.json package-lock.json pom.xml Pipfile.lock requirements.txt)
CLASSIFY_LIFECYCLE_NAMES=(setup.py setup.cfg build.rs Makefile)

# Source code extensions, without the dot (spec item 19). Matched case-insensitively, so
# "PY" and "Py" match "py". Shell scripts count as source.
CLASSIFY_SOURCE_EXTS=(
  js mjs cjs jsx ts tsx
  java kt kts groovy scala
  py
  rs
  c h cc cpp cxx hpp hh
  sh bash
)

CLASSIFIED_MANIFEST=()
CLASSIFIED_SOURCE=()
CLASSIFIED_LIFECYCLE=()

# classify_path <relative path>: sets CLASSIFY_RESULT to manifest, lifecycle, source, or "".
# Name rules run before the extension rule, so a lifecycle name wins over a source extension
# (setup.py is lifecycle, not source). Manifest names come first for the same reason.
# No forks, so a large tree is classified in one pass.
classify_path() {
  local base=${1##*/} n e was_nc hit=0

  CLASSIFY_RESULT=""
  for n in "${CLASSIFY_MANIFEST_NAMES[@]}"; do
    if [ "$base" = "$n" ]; then
      CLASSIFY_RESULT=manifest
      return 0
    fi
  done
  for n in "${CLASSIFY_LIFECYCLE_NAMES[@]}"; do
    if [ "$base" = "$n" ]; then
      CLASSIFY_RESULT=lifecycle
      return 0
    fi
  done

  # A name with no dot has no extension. Without this guard "py" would match the extension "py".
  case $base in
    *.*) ;;
    *) return 0 ;;
  esac
  e=${base##*.}

  # nocasematch makes the case compare ignore case (Bash 3.1 and later). The previous setting
  # is restored after the loop, so the caller's shell options are unchanged.
  shopt -q nocasematch && was_nc=1 || was_nc=0
  shopt -s nocasematch
  for n in "${CLASSIFY_SOURCE_EXTS[@]}"; do
    case $e in
      "$n") hit=1; break ;;
    esac
  done
  [ "$was_nc" -eq 1 ] || shopt -u nocasematch

  if [ "$hit" -eq 1 ]; then
    CLASSIFY_RESULT=source
  fi
  return 0
}

# classify_target: fills the CLASSIFIED_* arrays from SCAN_FILES. Call after traverse_target.
classify_target() {
  local rel

  CLASSIFIED_MANIFEST=()
  CLASSIFIED_SOURCE=()
  CLASSIFIED_LIFECYCLE=()
  for rel in "${SCAN_FILES[@]}"; do
    classify_path "$rel"
    case $CLASSIFY_RESULT in
      manifest) CLASSIFIED_MANIFEST[${#CLASSIFIED_MANIFEST[@]}]=$rel ;;
      source) CLASSIFIED_SOURCE[${#CLASSIFIED_SOURCE[@]}]=$rel ;;
      lifecycle) CLASSIFIED_LIFECYCLE[${#CLASSIFIED_LIFECYCLE[@]}]=$rel ;;
    esac
  done
}
