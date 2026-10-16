# TASK_09: Supply chain anomaly detection

- **Status:** Blocked
- **Phase:** 2 (Multi-ecosystem SCA)
- **Spec sections:** 4.3
- **Depends on:** TASK_07, TASK_08

## Goal

Flag typosquatting indicators and dependency confusion risks. Missing lock files are handled in TASK_08.

## Acceptance criteria

- [ ] Typosquatting detection uses the method chosen in item 22, against the list chosen in item 22.
- [ ] Dependency confusion detection uses the rule chosen in item 23.
- [ ] Each flagged package produces `TYPOSQUAT_SUSPECT` or `DEPENDENCY_CONFUSION_RISK` findings, with the categories confirmed in item 62.
- [ ] The detection method and data source are documented in the spec, not just in code.

## Blockers

- Item 22: similarity method, and source of the top-N popular-package list. The list is a data dependency, so decide its source and update rule before implementation.
- Item 23: which names count as "internal."
- Item 62: category names for the two findings.

## Notes

- Keep the popular-package list in a versioned data file, so it can be updated without a code change.
- Expect false positives. Test with both known-bad and clean fixtures (TASK_14).
