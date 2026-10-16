# TASK_06: Severity normalization and exit-code aggregation

- **Status:** Not started
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 7.4, 8.2 (`--fail-on-critical`), 8.3
- **Depends on:** TASK_05

## Goal

Make every finding carry one of four severities. Compute the final exit code from the findings and the `--fail-on-critical` flag.

## Acceptance criteria

- [ ] The default severity for each category in the Section 7.4 table is applied.
- [ ] `critical_findings` counts only `CRITICAL` findings.
- [ ] With `--fail-on-critical` and at least one `CRITICAL` finding, the exit code is `1`.
- [ ] Without `--fail-on-critical`, findings of any severity exit `0`.
- [ ] Engine-native severities are mapped through one function, so each engine's mapping can change without touching the aggregator.

## Blockers

- Item 27: YARA and Semgrep severity mapping. Use the default `MEDIUM` when a rule has no severity (the option A default) and record the mapping in progress.md.
- Item 64: OSV severity mapping to the four levels. Required for `VULNERABLE_DEPENDENCY` severities. Blocks TASK_08 as well.
- Item 62: category names used in the default table.
- Item 59: exit code for errors. Not needed here, but affects this task if the decision changes.

## Notes

- The Section 7.4 table covers six categories. Defaults for `SECRET_EXPOSED`, `TYPOSQUAT_SUSPECT`, `DEPENDENCY_CONFUSION_RISK`, and `PATH_TRAVERSAL_HOOK` are still open. Leave them as `HIGH` temporarily and record that in progress.md.
