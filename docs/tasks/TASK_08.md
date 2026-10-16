# TASK_08: OSV batch query and advisory findings

- **Status:** Done (with follow-ups). Item 64 is decided as CVSS bands. Open: advisories with no CVSS v3 score, the cache (item 61), and the timeouts and batch size placeholders. See progress.md.
- **Phase:** 2 (Multi-ecosystem SCA)
- **Spec sections:** 2.4, 4.2, 4.3 (missing lock files), 8.2 (`--offline`), 2.2
- **Depends on:** TASK_07, TASK_06

## Goal

Send the collected package tuples to the OSV batch endpoint, convert matched advisories to `VULNERABLE_DEPENDENCY` findings, and handle failures per the spec.

## Acceptance criteria

- [~] Sends batches to `https://api.osv.dev/v1/querybatch` with `curl`. Batch size respects OSV's documented limit (item 15). Sent in batches of 100 (placeholder). The documented limit is not verified.
- [x] Sends only package names, versions, and ecosystems. Nothing else leaves the machine (item 11).
- [~] Parses the response with `jq`. Each matched advisory becomes one finding. Parsing and paging are done. Matches fail the scan until item 64 is decided.
- [x] `--offline` skips this task completely. No network call is made (item 5).
- [x] If OSV is unreachable, times out, or is rate-limited, the scan fails with exit `1`. No partial SCA result is reported as complete (item 1).
- [x] Missing lock files produce a `MISSING_LOCKFILE` finding with `LOW` severity (Section 7.4). `package.json` only (see spec 4.2).
- [~] Each finding description includes the package, version, and advisory ID. Built, not emitted until item 64 is decided.

## Blockers

- Item 49: request and total timeouts. Use a placeholder value and record it in progress.md.
- Item 61: cache TTL. Implement the cache only after the TTL is chosen. Mark the cache as not done until then.
- Item 53: advisory ID in the description (inferred; confirm).
- Item 64: OSV severity mapping. Required for each `VULNERABLE_DEPENDENCY` severity. Blocks completion of this task.

## Notes

- Test with a recorded response file, not a live call. Live calls belong in a separate, optional test.
- OSV can return several pages of results per query. Check whether the batch response needs follow-up queries.
