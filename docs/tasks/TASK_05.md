# TASK_05: Finding model and output renderers

- **Status:** Not started
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 7.1, 7.2, 7.3, 8.2 (`-o`, `-f`)
- **Depends on:** TASK_01, TASK_02

## Goal

Define one internal finding record and render it as an ANSI table, JSON, or SARIF 2.1.0. Write to stdout or to the `-o` file.

## Acceptance criteria

- [ ] Every finding has `category`, `severity`, `file`, and `description` (Section 7.1).
- [ ] JSON matches the schema and example in Section 7.2: `target_directory`, `total_findings`, `critical_findings`, `findings`.
- [ ] `-f table` is the default. `-f json` and `-f sarif` work.
- [ ] `-o <file>` writes the report to the file. Stdout is empty in that case.
- [ ] Zero findings still produces valid JSON and valid SARIF, with empty arrays (item 35, if option A).
- [ ] The SARIF output validates against the SARIF 2.1.0 schema.

## Blockers

- Item 29: extra fields (`line`, `rule_id`, `advisory_id`, `fingerprint`, `schema_version`). Build with the four required fields only. Add the rest once decided.
- Item 30: SARIF field mapping. Blocks a complete SARIF output.
- Item 31: stream split (report on stdout, progress on stderr).
- Item 32: color handling (TTY and `NO_COLOR`).
- Item 33: plain text or ANSI for `table` with `-o`.
- Item 34: ordering and deduplication.
- Item 36: summary counts beyond `critical_findings`.
- Item 58: how multiple paths are reported.
- Item 54: `file` relative to the target (inferred; confirm).

## Notes

- Build the record as a single tab-separated or NUL-separated internal format, and render from that. Do not render during the scan.
- Escape JSON strings correctly. File names and descriptions can contain quotes and backslashes. Test that path.
