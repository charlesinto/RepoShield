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
| [TASK_06](tasks/TASK_06.md) | Severity and exit-code aggregation | 1 | Not started | 27, 59, 62, 64 |
| [TASK_07](tasks/TASK_07.md) | SCA manifest parsers | 2 | Not started | 56, 57, 63 |
| [TASK_08](tasks/TASK_08.md) | OSV batch query and advisory findings | 2 | Not started | 49, 53, 61, 64 |
| [TASK_09](tasks/TASK_09.md) | Supply chain anomaly detection | 2 | Blocked | 22, 23, 62 |
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

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Item 27 (YARA and Semgrep mapping), item 64 (OSV severity mapping), item 62 (category names).
- **Lessons learnt:** _None yet._
- **Things to consider:** Four categories have no decided default severity. They are temporarily `HIGH`. Record each temporary value here.

### TASK_07: SCA manifest parsers

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Items 56, 57, 63.
- **Lessons learnt:** _None yet._
- **Things to consider:** Choose the `pom.xml` parsing approach before writing code. `grep` and `sed` are fragile for XML, and `${property}` placeholders need a rule.

### TASK_08: OSV batch query and advisory findings

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Items 49 (timeouts), 53 (advisory ID, inferred), 61 (cache TTL), 64 (severity mapping).
- **Lessons learnt:** _None yet._
- **Things to consider:** Test against recorded responses, not live calls. Check whether OSV batch responses need follow-up queries.

### TASK_09: Supply chain anomaly detection

- **Status:** Blocked
- **Outcome:** _None yet._
- **Blockers identified:** Items 22 (method and popular-package list), 23 (internal-name rule), 62 (category names).
- **Lessons learnt:** _None yet._
- **Things to consider:** The popular-package list is a data dependency. Decide its source and update rule first.

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
