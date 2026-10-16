# TASK_12: Lifecycle hook analysis

- **Status:** Not started
- **Phase:** 3 (Static code and build hook analysis)
- **Spec sections:** 6.1, 6.2, 7.2, 7.4
- **Depends on:** TASK_04, TASK_05, TASK_06

## Goal

Extract lifecycle hooks from package config files and flag hooks that make network calls, run shells, or traverse the filesystem.

## Acceptance criteria

- [ ] Reads `preinstall`, `postinstall`, and `prepare` from `package.json` (Node.js).
- [ ] Finds known executing calls in `setup.py` and `setup.cfg` by static matching, such as `os.system` and `subprocess` (item 17).
- [ ] Checks `build.rs` and Makefiles for the same network and shell list as Section 6.2 (item 18).
- [ ] Flags network calls (`curl`, `wget`, `fetch`, `nc`) as `MALICIOUS_BUILD_HOOK`, `HIGH`.
- [ ] Flags a network call piped to a shell as `MALICIOUS_BUILD_HOOK`, `CRITICAL`. The example in Section 7.2 is a fixture.
- [ ] Flags shell binaries (`/bin/sh` and similar) in hooks.
- [ ] Filesystem traversal is flagged only when the boundary rule is decided (item 26).

## Blockers

- Item 26: filesystem traversal boundary rule.
- Item 62: category names. The Section 7.2 example uses `MALICIOUS_BUILD_HOOK`, which is already accepted.

## Notes

- A flagged hook must show the command text in the description. Trim long commands to a reasonable length, and record the trimming rule in progress.md.
- The heuristic matches command text, so a hook that hides its command in a separate script will be missed. Record this limit.
