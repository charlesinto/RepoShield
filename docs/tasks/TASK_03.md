# TASK_03: Ignore rules and safe traversal

- **Status:** Done (with follow-ups)
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 2.3, 3.2, 3.3
- **Depends on:** TASK_02

## Goal

Walk the target directory and build the file list. Apply the built-in exclusions and `.repo-shield-ignore`. Handle hostile filenames and symlinks safely.

## Acceptance criteria

- [x] Always skips `.git/`, `node_modules/`, `.venv/`, `vendor/`, `target/`, `dist/` (Section 3.2).
- [x] Applies patterns from `.repo-shield-ignore` at the repo root. Those paths are excluded from the scan (Section 3.3).
- [x] Does **not** exclude files because `.gitignore` matches them (Section 3.3). Scanning a git-ignored file is covered by a test.
- [x] Symlinks are not followed. A symlink is recorded as skipped, not dereferenced (item 9).
- [x] File lists are NUL-delimited. Names with spaces, newlines, quotes, and a leading `-` are processed correctly (item 8).
- [x] No file is executed, sourced, or evaluated (item 7). Add a test that a file named like a script is not run.
- [x] Files are not skipped by size (item 12).

## Blockers

- Item 60: the `.gitignore` behavior conflicts with the TRD's "Respect Local Ignores." Build the current decision, and keep the `.gitignore` handling in one function so it can change in one place.
- Item 55: binary-file handling. Until decided, scan binary files as if they were text, and record the choice here.

## Notes

- Use `find` with `-print0` and `while IFS= read -r -d ''` for the NUL-delimited loop. This is the portable form that works on Bash 3.2.
- The `.repo-shield-ignore` syntax is not defined. Use `.gitignore`-style globs as the working assumption, and record it in progress.md.
