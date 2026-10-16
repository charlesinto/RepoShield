# TASK_01: CLI skeleton and exit codes

- **Status:** Not started
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 2.2, 2.4, 8.1, 8.2, 8.3
- **Depends on:** none

## Goal

Build the `repo-shield` entry point: argument parsing, `--help`, `--version`, and the exit-code contract. No scanning yet.

## Acceptance criteria

- [ ] Accepts every option in Section 8.2, including `--format=json`, combined short flags, and `--`.
- [ ] `--help` output contains the exact string `RepoShield Security Scanner` (formula test, item 50).
- [ ] `--version` prints the semantic version stored in the script (item 45).
- [ ] Unknown flags, invalid `--format` values, and missing paths exit `1` with a usage message that lists valid values (item 41).
- [ ] Missing `jq` or `curl` exits `1` with a clear message (item 2).
- [ ] Runs under Bash 3.2 (item 42). Checked on macOS `/bin/bash`.
- [ ] `--quiet` and `--verbose` are parsed and stored for later tasks (item 39).

## Blockers

- Item 59: exit `1` is shared between findings and errors. Implement the current decision (exit `1`) and keep the code path easy to change.

## Notes

- Keep the argument parser in one place. Later tasks read the parsed values from it.
- Path validation belongs to TASK_02, not here.
