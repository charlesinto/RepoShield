# TASK_05: Finding model and output renderers

- **Status:** Done (with follow-ups)
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 7.1, 7.2, 7.3, 8.2 (`-o`, `-f`)
- **Depends on:** TASK_01, TASK_02

## Goal

Define one internal finding record and render it as an ANSI table, JSON, or SARIF 2.1.0. Write to stdout or to the `-o` file.

## Acceptance criteria

- [x] Every finding has `category`, `severity`, `file`, and `description` (Section 7.1).
- [x] JSON matches the schema and example in Section 7.2: `target_directory`, `total_findings`, `critical_findings`, `findings`.
- [x] `-f table` is the default. `-f json` and `-f sarif` work. _(The renderers work. The default is set in the CLI (TASK_01). The entry point does not render yet; it still exits at the scan stub.)_
- [x] `-o <file>` writes the report to the file. Stdout is empty in that case.
- [x] Zero findings still produces valid JSON with an empty `findings` array, and SARIF with empty `rules` and `results`.
- [x] The SARIF output validates against the SARIF 2.1.0 schema. _(Checked with the official schema. The test runs only when `REPO_SHIELD_SARIF_SCHEMA` names the schema file and `jsonschema` is installed. It is skipped otherwise.)_

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
