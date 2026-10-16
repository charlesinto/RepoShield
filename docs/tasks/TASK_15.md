# TASK_15: Homebrew packaging and release automation

- **Status:** Blocked
- **Phase:** 4 (Packaging)
- **Spec sections:** 5 (Homebrew model in TRD), 10 (Packaging, Versioning, Distribution), 11
- **Depends on:** TASK_01 through TASK_12 (a working tool to package), TASK_14

## Goal

Package the CLI as a Homebrew formula in a tap, and automate releases with GitHub Actions.

## Acceptance criteria

- [ ] The formula installs modules under `libexec` and links the entry point into `bin` (item 44B).
- [ ] The formula declares `jq` and `curl` as dependencies. `yara` and `semgrep` are optional (Section 2.2).
- [ ] The formula `test` block passes, and checks for `RepoShield Security Scanner` in `--help` output (item 50).
- [ ] The `sha256` is the checksum of the real release tarball, not the empty-file hash (item 50).
- [ ] A tagged release on GitHub triggers an action that builds the tarball and reports its checksum.
- [ ] The version in the script matches the git tag (item 45B).
- [ ] Installs and runs on macOS Intel, macOS Apple Silicon, and Linux (Section 10).

## Blockers

- Item 50: canonical GitHub owner (`your-org` or `charlesinto`), checksum confirmation, and the formula test string. The tap cannot be published until the owner is fixed.
- Item 51: current roadmap phase. Needed to confirm the packaging phase is the right time to start.

## Notes

- The formula's `url` placeholder (`your-org/repo-shield`) must be updated together with the owner decision.
- Test the formula locally with `brew install --build-from-source` before publishing the tap.
