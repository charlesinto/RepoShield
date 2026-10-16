# TASK_14: Acceptance fixtures and performance benchmark

- **Status:** Blocked
- **Phase:** Cross-cutting (feeds every phase)
- **Spec sections:** 9.8 (items 46, 47), 10 (Performance)
- **Depends on:** none. Start early, because every other task uses these fixtures.

## Goal

Create a set of fixture repositories with known findings, and a benchmark that checks the performance target.

## Acceptance criteria

- [ ] `tests/fixtures/` contains at least: a malicious repo (one of each category), a clean repo, and a mixed repo.
- [ ] Each fixture has a file listing the findings it must produce. A test compares the scan against this list.
- [ ] A test script runs the full suite and exits non-zero on any mismatch.
- [ ] A benchmark repository under 100 MB is documented, and the timing is recorded against the reference machine (item 47).
- [ ] The benchmark measures wall-clock time for a repository under 100 MB against the 10-second target.

## Blockers

- Item 46: fixture owner. Not yet assigned.
- Item 47: reference machine and benchmark repository. Not yet decided.

## Notes

- Fixtures must never execute. Keep malicious examples as inert text. Do not put live network calls in them.
- Do not commit real secrets, even fake-looking ones that match a real format. Use obviously fake values (for example `AKIA` followed by zeros) and note this in progress.md.
