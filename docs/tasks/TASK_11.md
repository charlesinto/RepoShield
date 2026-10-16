# TASK_11: Optional YARA and Semgrep engines

- **Status:** Blocked
- **Phase:** 3 (Static code and build hook analysis)
- **Spec sections:** 2.2, 5.2
- **Depends on:** TASK_04, TASK_06, TASK_10

## Goal

If the `yara` or `semgrep` binary is on `PATH`, run the configured rules against source files and normalize their findings. If either is absent, skip it without failing.

## Acceptance criteria

- [ ] Detects `yara` and `semgrep` on `PATH` at startup. Absence is not an error (Section 2.2).
- [ ] Runs YARA against source files when present. Normalizes each match into the finding schema.
- [ ] Runs Semgrep against source files when present. Normalizes each result into the finding schema.
- [ ] Engine severities are mapped through the single mapping function in TASK_06.
- [ ] Engine errors are handled per Section 2.4: skip, warn, and continue.
- [ ] Works with neither tool installed (tested).

## Blockers

- Item 27: severity mapping for YARA and Semgrep. Blocks completion.
- Which YARA rule set and Semgrep configuration are used. Not in the spec. Add it as a new item before implementation.

## Notes

- Run these tools with their arguments as an array, not a string, so file names are never interpreted.
- Do not let an engine run any code from the target repository. Confirm each tool's configuration does not fetch remote rules at scan time.
