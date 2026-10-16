# TASK_13: Finding suppression

- **Status:** Blocked
- **Phase:** 3 (Static code and build hook analysis)
- **Spec sections:** 7.5, 3.3
- **Depends on:** TASK_05, TASK_06, TASK_10

## Goal

Let a user suppress a single finding with a recorded reason, through `.repo-shield-ignore`.

## Acceptance criteria

- [ ] Each suppression entry requires a reason. An entry without one is rejected with a warning.
- [ ] A suppressed finding is matched by a stable key, not by position in the output.
- [ ] A suppressed finding does not appear in the report.
- [ ] The number of suppressed findings is reported according to item 66.
- [ ] Path-level exclusions in `.repo-shield-ignore` (TASK_03) still work and are not affected.

## Blockers

- Item 66: the entry format and whether suppressed findings are counted. The task cannot be built until the format is fixed.
- Item 29: the stable key depends on `fingerprint` or `rule_id`, which are not yet decided.

## Notes

- A stable key based only on file and description breaks when the description changes. Decide the key before writing the matcher.
