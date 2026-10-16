# TASK_02: Target path resolution

- **Status:** Done (with follow-ups)
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 3.1, 8.1
- **Depends on:** TASK_01

## Goal

Resolve each target path given on the command line to an absolute, validated directory, and reject anything else.

## Acceptance criteria

- [x] Accepts `.`, `./relative/path`, and `/absolute/path`.
- [x] Converts every accepted path to an absolute path. This absolute path is what `target_directory` reports (Section 7.1).
- [x] A path that does not exist or is not a directory exits `1` with a message (Section 3.1).
- [x] Accepts one or more paths. Each is scanned separately (item 38).
- [x] Paths containing spaces, quotes, or a leading `-` (after `--`) work.
- [x] Symlinked target directories are resolved once, and the resolved path is reported.

## Blockers

- Item 52: "must be an existing directory" is inferred, not confirmed. Build it as specified and confirm before release.
- Item 58: how multiple results are reported. Scan each path now; the report format is handled in TASK_05.

## Notes

- Symlink rules for files inside the target are in TASK_03. This task only covers the top-level target.
