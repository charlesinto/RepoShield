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

# Source code extensions, without the dot. PENDING spec item 19: the list is not decided,
# so it is empty and no file is classified as source. Fill it in once item 19 is decided.
CLASSIFY_SOURCE_EXTS=()

CLASSIFIED_MANIFEST=()
CLASSIFIED_SOURCE=()
CLASSIFIED_LIFECYCLE=()

# classify_path <relative path>: sets CLASSIFY_RESULT to manifest, lifecycle, source, or "".
# Name rules run before the extension rule, so a lifecycle name wins over a source extension
# (setup.py is lifecycle, not source). Manifest names come first for the same reason.
# No forks, so a large tree is classified in one pass.
classify_path() {
  local base=${1##*/} n e

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
  for n in "${CLASSIFY_SOURCE_EXTS[@]}"; do
    if [ "$e" = "$n" ]; then
      CLASSIFY_RESULT=source
      return 0
    fi
  done
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
