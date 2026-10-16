# RepoShield Progress Log

**Read this file before starting any task. Update it after finishing any task.**

Each task has one entry below. Record every change to a task's status here, even when the task is not done.

**Status values:** `Not started`, `In progress`, `Blocked`, `Done`, `Done (with follow-ups)`

---

## Summary

| Task | Title | Phase | Status | Blockers (spec items) |
| --- | --- | --- | --- | --- |
| [TASK_01](tasks/TASK_01.md) | CLI skeleton and exit codes | 1 | Done | 59 |
| [TASK_02](tasks/TASK_02.md) | Target path resolution | 1 | Done (with follow-ups) | 52, 58 |
| [TASK_03](tasks/TASK_03.md) | Ignore rules and safe traversal | 1 | Done (with follow-ups) | 55, 60 |
| [TASK_04](tasks/TASK_04.md) | File classification (dispatcher) | 1 | Done | 19 (resolved) |
| [TASK_05](tasks/TASK_05.md) | Finding model and output renderers | 1 | Done (with follow-ups) | 29 (partly), 31, 32, 33, 34, 36, 54, 58 |
| [TASK_06](tasks/TASK_06.md) | Severity and exit-code aggregation | 1 | Done (with follow-ups) | 27, 59, 62, 64 |
| [TASK_07](tasks/TASK_07.md) | SCA manifest parsers | 2 | Done (with follow-ups) | 56, 57, 63 (provisional) |
| [TASK_08](tasks/TASK_08.md) | OSV batch query and advisory findings | 2 | Done (with follow-ups) | 61 (cache not built); 49, 15 (placeholders); 64 (partly: no CVSS v3 score) |
| [TASK_09](tasks/TASK_09.md) | Supply chain anomaly detection | 2 | Done (with follow-ups) | 22 (npm and Maven lists, item 67); 67 to 70 (working assumptions) |
| [TASK_10](tasks/TASK_10.md) | Built-in SAST checks | 3 | Not started | 24, 25, 29, 62 |
| [TASK_11](tasks/TASK_11.md) | Optional YARA and Semgrep engines | 3 | Blocked | 27 |
| [TASK_12](tasks/TASK_12.md) | Lifecycle hook analysis | 3 | Not started | 26, 62 |
| [TASK_13](tasks/TASK_13.md) | Finding suppression | 3 | Blocked | 29, 66 |
| [TASK_14](tasks/TASK_14.md) | Acceptance fixtures and benchmark | Cross-cutting | Blocked | 46, 47 |
| [TASK_15](tasks/TASK_15.md) | Homebrew packaging and release | 4 | Blocked | 50, 51 |

---

## Task entries

### TASK_01: CLI skeleton and exit codes

- **Status:** Done
- **Outcome:** Entry point `bin/repo-shield` (holds `REPO_SHIELD_VERSION`, resolves symlinks to find `lib/`) and parser `lib/cli.sh`. Parses all Section 8.2 options into `CLI_*` variables and `CLI_TARGETS`. `--help`, `--version`, usage errors, and the `jq`/`curl` check are in place. Tests in `tests/cli_test.sh` (23 checks, run under `/bin/bash` 3.2.57). After a valid parse the entry point exits `1` with "scanning is not implemented yet". This is deliberate, so an unfinished scan never reports clean. Path existence is not checked yet (TASK_02).
- **Blockers identified:** Item 59 (shared exit code). Kept exit `1` for both findings and errors. Still **Open** in the spec.
- **Lessons learnt:** Bash 3.2 has no `${var,,}`, associative arrays, or `readlink -f` on older macOS. The entry point resolves symlinks with a `readlink` loop instead. `${arr[@]}` on an empty array is safe without `set -u`, so the scripts do not use `set -u`. Dependency check runs after parsing, so `--help` and `--version` work without `jq`/`curl`.
- **Things to consider:** Path validation and `--output` file writing need to be added in TASK_02 and TASK_05. TASK_15 must install `lib/` next to the entry point: the source layout is `bin/repo-shield` plus `lib/`, and the installed layout must match it because the symlink resolution depends on it.

### TASK_02: Target path resolution

- **Status:** Done (with follow-ups)
- **Outcome:** New module `lib/target.sh`, sourced by `bin/repo-shield` after the dependency check. `target_resolve_all` turns each entry in `CLI_TARGETS` into an absolute physical path in `TARGET_DIRS`, in command-line order. `cd -P` resolves symlinks, so a chained symlink is resolved once to its real path. Every invalid path is reported, then the CLI exits `1`, before any scan starts. Scanning is still the TASK_01 stub, so a valid run still exits `1` with "scanning is not implemented yet". Tests: 41 checks in `tests/cli_test.sh`, passing under `/bin/bash` 3.2.57. Two TASK_01 checks now use real fixture directories, because a nonexistent path fails validation first. Spec 3.1 and `CLAUDE.md` layout updated.
- **Blockers identified:** Item 52 (existing-directory rule, still Open) and item 58 (multi-path reporting, still Open). Both are built as specified. Item 58 only affects output, so it is handled in TASK_05. Item 52 needs confirmation before release.
- **Lessons learnt:** With `CDPATH` set, `cd` resolves a relative path against `CDPATH` entries, so a relative target could resolve to the wrong directory. The resolver clears `CDPATH` for that `cd`. A mutation check (removing the guard) makes the CDPATH test fail, so the test covers the bug. macOS temp directories are under `/var`, which is a symlink to `/private/var`, so tests compare against `pwd -P`, not the raw path.
- **Things to consider:** "Each is scanned separately" is only met in resolution so far. Per-path scanning comes with the scan pipeline (TASK_03 onward). Confirm item 52 before release. TASK_03 can read `TARGET_DIRS` directly.

### TASK_03: Ignore rules and safe traversal

- **Status:** Done (with follow-ups)
- **Outcome:** New module `lib/traverse.sh`, sourced by `bin/repo-shield`. `traverse_target <dir>` walks the target with `find -print0` and fills `SCAN_FILES` (regular files) and `SCAN_SKIPPED` (symlinks and special files), both relative to `SCAN_ROOT`. Built-in directories are pruned inside `find`, so their contents are never listed. `.repo-shield-ignore` is parsed as data and compiled to ERE. Patterns are applied in order, and the last match wins. `.gitignore` is never read for exclusion. The entry point still exits `1` with the scanning stub. Tests: `tests/traverse_test.sh`, 10 checks, passing under `/bin/bash` 3.2.57. A mutation check (following symlinks; making `.gitignore` exclude) makes the tests fail. A 23,000-file tree, of which 20,000 are under `node_modules`, traverses in 0.56s.
- **Decisions made:**
  - `.repo-shield-ignore` syntax: gitignore-style globs (working assumption, recorded in spec 3.3). Supported: `#` comments, `!` re-include, trailing `/` for directories, anchoring by an inner `/`, `*`, `?`, `[...]`, and `**`.
  - `.gitignore` handling is one function, `traverse_gitignore_excludes`, which returns "not excluded" for every path (item 60, current decision).
  - Binary files are scanned as text (item 55, current decision). No size limit.
  - Special files (FIFOs, sockets, devices) are skipped and recorded with symlinks in `SCAN_SKIPPED`. The spec does not mention them; this is an added rule.
  - A symlinked `.repo-shield-ignore` is not read.
- **Blockers identified:** Item 60 (`.gitignore` conflict with the TRD) and item 55 (binary files). Both are still **Open** in the spec. The build follows the current decision for each.
- **Lessons learnt:** `find -prune` must come before `-print0`, and the built-in names apply only to directories (`-type d`). A file named `dist` must still be scanned. The `find` walk lists a directory before its children, so an ignored directory can be remembered as a prefix and skipped without a per-file pattern check. Bash 3.2 has no `${s:-1}` negative substring, so the glob translator guards index `-1`. Using `printf %q` in the test output keeps a name with a newline on one line.
- **Things to consider:**
  - Spec 3.3 says the scanner reads `.gitignore`, but nothing reads it yet. This is consistent with item 60 (it never excludes). Decide whether the report needs it, and if so, read it in `traverse_gitignore_excludes`.
  - The glob translator is hand-written. Patterns with a `[` class that is not closed, or a `]` as the first class character, are not fully handled. Check before TASK_07 relies on these patterns.
  - Trailing whitespace in ignore lines is kept as part of the pattern, not trimmed. Confirm the rule.
  - Unreadable directories make `find` write warnings to stderr and carry on. TASK_05 should record them as warnings, per spec 2.4.
  - Symlinked directories are recorded, not descended, and symlinked ignore files are ignored. Confirm that this is the intended scope for item 9.

### TASK_04: File classification (dispatcher)

- **Status:** Done
- **Outcome:** New module `lib/classify.sh`, sourced by `bin/repo-shield`. `classify_target` fills `CLASSIFIED_MANIFEST`, `CLASSIFIED_SOURCE`, and `CLASSIFIED_LIFECYCLE` from `SCAN_FILES`. `classify_path` matches the base name exactly against `CLASSIFY_MANIFEST_NAMES` and `CLASSIFY_LIFECYCLE_NAMES`, then the extension against `CLASSIFY_SOURCE_EXTS`. The source list is decided (spec item 19). Tests: `tests/classify_test.sh`, 70 checks, passing under `/bin/bash` 3.2.57. Mutation checks: removing the dotless-name guard fails 1 check; moving the extension rule ahead of the name rules fails 3; disabling `nocasematch` fails 7. The entry point still exits `1` with the scanning stub. Spec Section 2 and item 19 record the rules.
- **Decisions made:**
  - `setup.py` is lifecycle, not source. Name rules run before the extension rule, so a lifecycle or manifest name always wins. This matches the acceptance criteria, which list `setup.py` as lifecycle.
  - Names match the base name at any depth, exactly and case-sensitively. `makefile`, `Makefile.bak`, and `requirements-dev.txt` are not classified.
  - Source extensions (item 19, decided by the user): `js mjs cjs jsx ts tsx java kt kts groovy scala py rs c h cc cpp cxx hpp hh sh bash`. Matched case-insensitively. Shell scripts are source. Go is not listed.
  - Lifecycle names: `setup.py`, `setup.cfg`, `build.rs`, `Makefile`. Manifest names: the five in the acceptance criteria.
- **Blockers identified:** None. Item 19 is resolved.
- **Lessons learnt:** A mutation that only inserts a check before existing checks does not change behavior when the later checks overwrite the result. Use an early `return` in the mutant. Pure-Bash suffix matching (`${base##*.}`) with a dot guard avoids a fork per file. Case-insensitive matching uses `shopt -s nocasematch` (Bash 3.1 and later), set only around the extension loop and restored afterwards, so there is no `tr` fork per file.
- **Things to consider:**
  - Go (`.go`) is not in the list. Add it if Go repositories should get SAST.
  - Confirm that `makefile` (lowercase) and `GNUmakefile` should stay unclassified.
  - TASK_10 (SAST) can now read `CLASSIFIED_SOURCE`.

### TASK_05: Finding model and output renderers

- **Status:** Done (with follow-ups)
- **Outcome:** New module `lib/report.sh`, sourced by `bin/repo-shield`. `finding_add <category> <severity> <file> <description> [line]` stores a finding in parallel arrays. Severity is checked against the four levels. `report_emit <format> <output file or empty> <target>` renders `table`, `json`, or `sarif` to stdout, or to the `-o` file with stdout left empty. An unwritable `-o` path exits `1`. JSON follows spec 7.2, plus an optional `line`. SARIF 2.1.0 follows the item 30 mapping in spec 7.3, with snippets read from the target file. Strings are escaped for quotes, backslashes, and control characters. Tests: `tests/report_test.sh`, 27 checks under `/bin/bash` 3.2.57, plus 1 SARIF schema check that is skipped unless `REPO_SHIELD_SARIF_SCHEMA` and `jsonschema` are present. With the official 2.1.0 schema and `jsonschema` installed, all 28 pass. Mutation checks: removing the backslash escape fails 1 check; removing the `-o` stderr suppression fails 1 check; an invalid SARIF level fails the schema check. The entry point still exits `1` at the scan stub, so the renderers are not reachable from the CLI yet.
- **Decisions made:**
  - Item 30 (SARIF, confirmed by the user): `id` is the rule id (category), `messages` is the description, the level comes from severity, `security_metadata` is `security-severity` (CRITICAL 9.0, HIGH 7.0, MEDIUM 4.0, LOW 1.0) with `tags: ["security"]`, and code snippets come from the line. Each rule's security severity is the highest among its findings.
  - Item 29 (confirmed by the user): `line` is added as an optional field. It is included in JSON only when set, so the spec 7.2 example is unchanged. `rule_id`, `advisory_id`, `fingerprint`, and `schema_version` are still open.
  - `rules[].shortDescription.text` is the category name until item 20 gives real category descriptions.
  - SARIF `uri` is percent-encoded, because a name with a space is not a valid URI reference.
  - Findings are kept as parallel arrays, not a tab-separated record. Bash cannot hold a NUL byte, and names can contain tabs and newlines. Rendering happens only after the scan.
  - Item 35 (zero findings): JSON and SARIF give empty arrays, as the schema requires. Still Open.
  - Item 34 (ordering and deduplication): output is in the order findings were added. No sorting and no deduplication. Still Open.
  - Item 32 (color): the table has no color codes. Still Open.
  - Item 33 (`table` with `-o`): the file gets the same plain table as stdout. Still Open.
  - Item 36 (summary counts): only `total` and `critical` appear. Still Open.
  - Item 54 (`file` relative to the target): the renderer uses whatever path the engine passes. Still Open.
- **Blockers identified:** Still Open: item 29 (`rule_id`, `advisory_id`, `fingerprint`, `schema_version`), 31 (stream split; nothing else writes to stdout yet), 32, 33, 34, 36, 54, and 58 (how multiple paths are reported; not built, since the entry point has no multi-path output).
- **Lessons learnt:** Bash 3.2's `printf %*s` works for table widths, and `local LC_ALL=C` makes a per-byte escape loop safe for UTF-8. Using `printf -v` avoids a fork per control character. Command substitution per field would fork for every finding, so the JSON writer sets `_JSON_STR` instead. A redirect failure on a function call prints a bash message to stderr, so the code wraps the call in a group with `2>/dev/null` and prints its own message. Two bugs were caught by the tests: a trailing comma after `rules` in the SARIF output, and a wrong index in one of my own tests. The schema check caught an invalid level when injected on purpose. A user edit to the spec was overwritten by a save during my edit, so the spec was re-read before the final edit.
- **Things to consider:**
  - Item 20 decides the category descriptions for `rules[].shortDescription`.
  - Decide items 31 to 34 and 36 before the entry point renders, since they set where output goes and what it shows.
  - Item 58 decides whether `target_directory` stays single-valued per report.
  - The SARIF schema is not bundled. Decide whether to add it to the repo, or keep the check optional as now.
- **Decisions made (provisional, not yet decided in the spec):**
  - Findings are stored in parallel arrays, not a tab-separated record. Bash cannot hold a NUL byte, and names can contain tabs and newlines. Rendering happens only after the scan.
  - Item 35 (zero findings): output is valid JSON with `"findings": []`, which the 7.1 schema requires. The item itself is still Open.
  - Item 34 (ordering and deduplication): findings are output in the order they were added. There is no sorting and no deduplication. Still Open.
  - Item 32 (color): the table has no color codes. This is the conservative choice, and it is still Open. Control characters in table cells are replaced with `?`.
  - Item 33 (`table` with `-o`): the file gets the same plain table as stdout. Still Open.
  - Item 36 (summary counts): only `total` and `critical` are shown, which are the JSON fields. Still Open.
  - Item 54 (`file` relative to target): the renderer uses whatever the engine passes. The 7.1 wording says relative. Still Open.
- **Blockers identified:** Still Open: items 29 (extra fields, not built), 30 (SARIF mapping, blocks `-f sarif`), 31 (stream split; nothing else writes to stdout yet), 32, 33, 34, 36, 54, 58 (how multiple paths are reported; not built, since the entry point has no multi-path output). The SARIF acceptance criteria are not met.
- **Lessons learnt:** Bash 3.2's `printf %*s` works for table widths, and `local LC_ALL=C` makes a per-byte escape loop safe for UTF-8. Using `printf -v` avoids a fork per control character. Command substitution per field would fork for every finding, so the JSON writer sets `_JSON_STR` instead. A redirect failure on a function call prints a bash message to stderr. Wrapping the call in a group with `2>/dev/null` lets the code print its own message.
- **Things to consider:**
  - Decide item 30 (SARIF mapping) before building the SARIF renderer. The renderer must not be written against an assumed mapping.
  - Decide items 31 to 34 and 36 before the entry point starts rendering, since they set where output goes and what it shows.
  - Item 58 decides whether `target_directory` stays single-valued per report. The current JSON has one target per report, which fits option (b) (one report per path). That is an inference from the schema, not a decision.

### TASK_06: Severity and exit-code aggregation

- **Status:** Done (with follow-ups)
- **Outcome:** New module `lib/severity.sh`, sourced by `bin/repo-shield`. `severity_default <category> [condition]` applies the spec 7.4 table: `MALICIOUS_BUILD_HOOK` takes `pipe-to-shell` (CRITICAL) or `network` (HIGH). `REVERSE_SHELL` is CRITICAL, `OBFUSCATED_EXECUTION` HIGH, `MISSING_LOCKFILE` LOW. `severity_from_engine <engine> <native>` is the one mapping point for engine severities, with one branch per engine (yara and semgrep so far). `severity_count <level>` counts exactly one level. `severity_scan_exit_code` sets `_EXIT_CODE` to `1` only with `--fail-on-critical` and at least one `CRITICAL` finding. Tests: `tests/severity_test.sh`, 11 checks under `/bin/bash` 3.2.57. Mutation checks: pipe-to-shell set to HIGH, flag ignored, nocasematch not restored, empty engine not MEDIUM, and count not exact all fail a check. The other suites still pass (cli 41, traverse 10, classify 70, report 27). The entry point still exits `1` at the scan stub, so the exit code is not yet wired to a real scan.
- **Decisions made:**
  - Provisional `HIGH` for `SECRET_EXPOSED`, `TYPOSQUAT_SUSPECT`, `DEPENDENCY_CONFUSION_RISK`, and `PATH_TRAVERSAL_HOOK`. Spec 7.4 now says so. Item 21 says these are Open.
  - Item 27 working default (from the task file): a rule with no native severity is `MEDIUM`. Other native values with no mapping return an error. The spec 7.4 note says this is not yet decided.
  - Category names (item 62) are used as they appear in spec 7.4. Still Open.
  - `severity_default` returns 1 for `VULNERABLE_DEPENDENCY`. The OSV mapping is not invented (item 64). TASK_08 cannot set this severity until item 64 is decided.
  - `severity_from_engine` returns 1 for `osv`, for the same reason.
  - `report.sh` still counts `CRITICAL` inline. It was not changed to call `severity_count`, so the report tests do not need `severity.sh` loaded.
- **Blockers identified:** Item 64 (OSV mapping; blocks TASK_08's `VULNERABLE_DEPENDENCY` severity). Item 27 (YARA and Semgrep mapping; the working default is used, the other native values are not mapped). Item 62 (category names; used as written). Item 59 (exit code `1` shared with errors; not handled here).
- **Lessons learnt:** `cli_parse_args` does not reset `CLI_FAIL_ON_CRITICAL` between calls, so a test that checks "flag off" after a "flag on" parse must run in a fresh shell. A usage error inside `cli_parse_args` calls `exit`, which ends the whole test shell, so it must not appear in a snippet that has later checks. The first version of the test made both mistakes and was caught by reading it back, not by a failure.
- **Things to consider:**
  - Decide item 64 before TASK_08. It is the only way `VULNERABLE_DEPENDENCY` gets a severity.
  - Decide item 27 for the real YARA and Semgrep rule formats before TASK_11. Semgrep uses names like `ERROR` and `WARNING` in its output, which are not mapped yet.
  - Decide items 21 and 62 for the four provisional categories. They must be `HIGH` only until then.
  - When TASK_08 onward calls `severity_default`, check the category and condition names against the spec 7.4 table.
  - Item 59 is still Open. The exit code uses `1` for both findings and errors.

### TASK_07: SCA manifest parsers

- **Status:** Done (with follow-ups)
- **Outcome:** New module `lib/sca.sh`, sourced by `bin/repo-shield`. `sca_parse_target` parses every file in `CLASSIFIED_MANIFEST` and fills `SCA_ECOSYSTEM`, `SCA_NAME`, `SCA_VERSION`, and `SCA_FILE` (one tuple per package, ecosystem `npm`, `Maven`, or `PyPI`). Each skipped entry and each malformed file adds a row to `SCA_WARN_FILE` and `SCA_WARN_MSG` (spec 2.4). Parsers: `package-lock.json` (jq, lockfile v1, v2, and v3), `package.json` (jq; ranges resolved from a sibling lock file), `Pipfile.lock` (jq), `pom.xml` (awk), and `requirements.txt` (shell). Tests: `tests/sca_test.sh`, 11 checks against committed fixtures in `tests/fixtures/sca/`, under `/bin/bash` 3.2.57. The other suites still pass (cli 41, traverse 10, classify 70, report 27, severity 11). The entry point still exits `1` at the scan stub. Nothing calls the parsers yet.
- **Decisions made:**
  - **pom.xml approach (decided before writing the parser):** a restricted awk parser, not `xmllint`. `xmllint` is not a hard dependency (CLAUDE.md), so a scan would give different results on hosts that do and do not have it. The parser removes comments, puts each tag on its own line, and reads only direct `<dependency>` elements under `<project><dependencies>`. Mismatched or unclosed tags make the file malformed.
  - **Property versions** (`${...}`) are skipped with a warning, not resolved from `<properties>`. A dependency with no version (managed by a BOM) is skipped with a warning. Both are provisional.
  - **Item 56 (working assumption):** npm lockfile v1, v2, and v3 are all read. Pipfile.lock is the single Pipenv format. Recorded in spec 9.10.
  - **Item 57 (working assumption):** a range with no lock file is skipped with a warning. The `LOW` note in option (a) is not built, because it needs a finding category (item 62). Recorded in spec 9.10.
  - **Item 63 (working assumption):** `dependency:list` exports are not read. Recorded in spec 9.10.
  - **package.json with a sibling lock:** exact pins are used as written. Ranges use the lock's version. A lock that does not parse falls back to the no-lock rules, so pins are not lost.
  - **Duplicates are kept.** A package can appear in `package.json` and in `package-lock.json`, and a Pipfile name can appear in both sections. TASK_08 removes duplicates before the OSV query. The tuple is `(ecosystem, name, version)`, and `SCA_FILE` says where it came from.
  - **Symlinks** (spec 2.3): a `package-lock.json` that is a symlink is not read, so a range in `package.json` is then unresolved. The test covers this.
- **Blockers identified:** Items 56, 57, and 63 are still **Open** in the spec. The parsers follow the working assumptions above. Confirm them before release.
- **Lessons learnt:**
  - The first version of the test checked a path that was never created. The symlink test passed with the guard removed, because the link pointed at a missing file. A mutation check (removing the `-L` guard) caught it. A mutation check is only useful if the fixture under test really exists, so check the setup when a mutation survives.
  - Bash 3.2 does not allow a pipe into `while` if the loop must fill arrays, because the loop runs in a subshell. `sca_take` reads from a heredoc instead.
  - `@tsv` in jq rejects objects, so the package.json filter converts a non-string spec with `tostring`.
  - Requirements continuation lines (`pkg==1.0 \` followed by `--hash=...`) are handled by stripping the trailing `\` and then skipping option lines. Trailing spaces must be trimmed first.
- **Things to consider:**
  - Confirm items 56, 57, and 63. If the npm v1 lockfile is out of scope, drop that branch from `_SCA_LOCK_JQ`.
  - Item 57: decide whether the `LOW` note should be a finding. That needs a category name (item 62), so it stays a warning for now.
  - Property placeholders in `pom.xml` could be resolved from the same file's `<properties>`. That would find more versions, but the rule is not in the spec yet.
  - The requirements parser does not follow `-r` includes. A project that splits its pins across files gets a warning for each include, not the pins themselves.
  - TASK_08 must deduplicate tuples before the OSV query and use `SCA_NAME` with the OSV ecosystem names.

### TASK_08: OSV batch query and advisory findings

- **Status:** Done (with follow-ups). Item 64 is decided as CVSS bands, and the cache, placeholders, and no-CVSS case are open.
- **Outcome:** New module `lib/osv.sh`, sourced by `bin/repo-shield`. `osv_scan` runs the lookup on the tuples in the `SCA_*` arrays. It dedupes tuples, POSTs batches to `https://api.osv.dev/v1/querybatch` with `curl`, follows `next_page_token`, and parses the response with `jq`. The request body holds only ecosystem, name, version, and page token. `--offline` returns before any request. Any unreachable, timed-out, rate-limited (429), other non-200, or unparseable response returns `1` with `OSV_ERROR` set, and no partial result is kept. A `package.json` with no regular `package-lock.json` beside it gets a `MISSING_LOCKFILE` `LOW` finding. Tests: `tests/osv_test.sh`, 24 checks under `/bin/bash` 3.2.57, with the HTTP call replaced by a fake that reads recorded responses in `tests/fixtures/osv/`. No test makes a network call. Mutation checks: removing the offline guard fails 2 checks; dropping the page token fails 1. The other suites still pass (cli 41, traverse 10, classify 70, report 27, severity 11, sca 11).
- **Severity (item 64, decided by the user):** CVSS v3 base score bands: 9.0 to 10.0 `CRITICAL`, 7.0 to 8.9 `HIGH`, 4.0 to 6.9 `MEDIUM`, 0.1 to 3.9 `LOW`. OSV returns the CVSS vector, not the score, so the score is computed from the vector (`cvss3_base_score`, CVSS v3.0 and v3.1), then mapped by `severity_from_cvss_score` (both in `lib/severity.sh`). The advisory is fetched from `GET /v1/vulns/{id}` once per scan. Band edges and known NVD scores are tested in `tests/severity_test.sh`, with 12 checks against a mutated edge.
- **Not done:**
  - **Advisories with no CVSS v3 score (open):** an advisory with only a CVSS v4 vector, or none, cannot be mapped under the decided rule. The scan fails for it with exit `1` and names the advisory. This is the one follow-up that needs a decision. Many real advisories may have no v3 score, so this matters before release. CVSS v4 is not computed.
  - **Cache (item 61):** not built. The TTL is not chosen.
  - **Timeouts (item 49):** placeholders only (connect 10 s, total 60 s).
  - **Batch size (item 15):** placeholder 100. I could not verify OSV's documented per-request limit. Web search returned nothing on it. Check the OSV API docs before release.
- **Decisions made:**
  - `--offline` skips the missing-lock check too, because the task says "skips this task completely".
  - The missing-lock check covers `package.json` only. `requirements.txt` and `pom.xml` have no lock convention in the spec, so they are not checked. Recorded in spec 4.2.
  - Item 53 (working assumption): the description includes package, version, ecosystem, and advisory ID. It is built but not emitted yet.
  - A failure at any batch or page fails the whole lookup, not just that batch.
- **Blockers identified:** Item 61 (cache not built). Items 49 and 15 are placeholders. Item 64 is partly open: no mapping for an advisory with no CVSS v3 score.
- **Lessons learnt:**
  - Variables set with a command prefix (`VAR=x fn`) are not exported to a child `bash -c`. The test passes options as arguments instead, and a first version that did not do this made the offline test pass for the wrong reason.
  - The HTTP call is one function (`osv_http_post`), so tests replace it with recorded responses. Nothing else in the module calls `curl`.
  - Paging keeps request order by index: `split` makes batch files, and the response index is mapped back to the unique-list line through the batch file's line order.
- **Things to consider:**
  - Decide what happens to an advisory with no CVSS v3 score (item 64). Options: fail the scan (current), skip it with a warning, or fall back to OSV's own severity label. Only the CVSS bands are decided.
  - Verify the OSV batch limit and set `OSV_BATCH_SIZE`.
  - Decide item 61 and build the cache. A cache in a user directory must not store anything from the scanned repository (spec 2.3).
  - The entry point still exits `1` at the scan stub. Nothing calls `sca_parse_target` or `osv_scan` yet.

### TASK_09: Supply chain anomaly detection

- **Status:** Done (with follow-ups)
- **Outcome:** New modules `lib/popular.sh` (reference list fetch and cache) and `lib/anomaly.sh` (`anomaly_scan`), sourced by `bin/repo-shield`. `anomaly_scan` reads the `SCA_*` arrays and emits `TYPOSQUAT_SUSPECT` (PyPI only) and `DEPENDENCY_CONFUSION_RISK` (all ecosystems, when `--internal-prefix` is given). `--internal-prefix=<prefix>` is repeatable and was added to `lib/cli.sh` (spec 8.2). Tests: `tests/anomaly_test.sh`, 47 checks under `/bin/bash` 3.2.57. No test makes a network call; the fetch is replaced by a fake that reads `tests/fixtures/popular/top-sample.json`. The other suites still pass (cli 46, traverse 10, classify 70, report 27, severity 13, sca 11, osv 31). Spec 2.3, 2.4, 4.3, 8.2, and 9 were updated in the same change. The entry point still exits `1` at the scan stub, and nothing calls `anomaly_scan` yet.
- **Decisions made:**
  - **Items 22, 23, and 62 (user):** edit distance with normalization; PyPI list fetched at scan time with a 4-hour cache; a fetch failure with no cache skips the typosquat check and warns; dependency confusion uses user-configured prefixes; category names confirmed.
  - **Working assumptions, recorded as spec 9.10 items 67 to 70:** the PyPI list is the public `top-pypi-packages-30-days.json` dataset, top 1,000 by `download_count`. It is a third-party source. I checked that it returns a live response (`last_update` 2026-10-01) but did not verify its long-term availability. The cache is at `$XDG_CACHE_HOME/repo-shield/`. `--offline` runs the anomaly checks, and the typosquat check uses only a fresh cache. An expired cache is not used when the fetch fails.
  - **Scope:** npm and Maven have no list, so no typosquat check runs for them. Typosquat severity stays `HIGH` (provisional, spec 7.4).
  - **Spec conflict fixed:** spec 2.3 said the only network traffic was OSV. It now also covers the list GET.
  - **Scope of prefix matching:** the prefix is normalized and matched at the start of the name. npm scoped names are never flagged. For Maven it is matched against the `groupId`.
  - **Algorithm in awk, not Bash.** Bash 3.2 is too slow for the edit-distance comparisons. Damerau (optimal string alignment) distance with an early exit when a row exceeds the limit.
- **Blockers identified:** None blocking. Open: items 67 (npm and Maven lists), 68 (cache location), 69 (offline semantics), and 70 (prefix matching) are working assumptions that need confirmation.
- **Lessons learnt:**
  - The first version of the distance code took 11.6 s for 303 dependencies against the 1,000-name list, far too slow. Precomputing each name's characters and stopping early once a row exceeds the limit brought it to 2.6 s. Check the cost against real list sizes early.
  - A cross-check against a Python reference (three random seeds, 71 to 88 flagged names each) matched the awk output exactly. This confirmed the early-exit change.
  - Mutation checks found three surviving mutations: no transposition, scoped npm names not skipped, and separator runs not collapsed. Each needed a test that the first version did not have. A transposition test needs a short name, because for a long name two substitutions also pass the distance-2 limit. The scope rule is only observable when the user gives a prefix such as `@acme`.
  - The expiry check uses `find -mmin` on a real cache file, and the test sets the file's age with `touch -t`. Both BSD and GNU `find` accept `-mmin`.
- **Things to consider:**
  - Confirm items 67 to 70. Items 67 and 69 change behavior the user may not expect (a third-party source; anomaly checks under `--offline`).
  - The popular-list request has no retry and no size limit beyond the timeout. It is about 900 KB, which is acceptable. Watch the timeouts (item 49).
  - `SCA_WARN_*` has no renderer yet. The typosquat warning is recorded but not shown. Add it when the report is wired.
  - Nothing calls `anomaly_scan` yet. The entry point wiring is part of the later scan task.
  - TASK_14 should add known-bad and clean fixtures for these checks beyond the synthetic ones here.

### TASK_10: Built-in SAST checks

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Items 24 (entropy), 25 (credential pattern list), 29 (line field), 62 (category names).
- **Lessons learnt:** _None yet._
- **Things to consider:** Record what the regex checks cannot detect, so the limits are visible.

### TASK_11: Optional YARA and Semgrep engines

- **Status:** Blocked
- **Outcome:** _None yet._
- **Blockers identified:** Item 27 (severity mapping). Not in the spec: which YARA rule set and Semgrep configuration to use. Add as a new spec item.
- **Lessons learnt:** _None yet._
- **Things to consider:** Confirm neither tool fetches remote rules at scan time.

### TASK_12: Lifecycle hook analysis

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Items 26 (traversal boundary), 62 (category names).
- **Lessons learnt:** _None yet._
- **Things to consider:** Hooks that hide their command in a separate script will be missed. Record this limit.

### TASK_13: Finding suppression

- **Status:** Blocked
- **Outcome:** _None yet._
- **Blockers identified:** Items 66 (entry format and counting), 29 (stable key).
- **Lessons learnt:** _None yet._
- **Things to consider:** A key based only on file and description breaks when the description changes.

### TASK_14: Acceptance fixtures and benchmark

- **Status:** Blocked
- **Outcome:** _None yet._
- **Blockers identified:** Items 46 (fixture owner), 47 (reference machine and benchmark repository).
- **Lessons learnt:** _None yet._
- **Things to consider:** Fixtures must stay inert. Use obviously fake secret values.

### TASK_15: Homebrew packaging and release

- **Status:** Blocked
- **Outcome:** _None yet._
- **Blockers identified:** Items 50 (owner, checksum, test string), 51 (roadmap phase).
- **Lessons learnt:** _None yet._
- **Things to consider:** The formula `url` placeholder must change together with the owner decision.
