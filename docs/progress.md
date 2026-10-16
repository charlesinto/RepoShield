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
| [TASK_04](tasks/TASK_04.md) | File classification (dispatcher) | 1 | Not started | 19 |
| [TASK_05](tasks/TASK_05.md) | Finding model and output renderers | 1 | Not started | 29, 30, 31, 32, 33, 34, 36, 54, 58 |
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

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Item 19 (source extension list).
- **Lessons learnt:** _None yet._
- **Things to consider:** Decide whether `setup.py` is classed as source or lifecycle. Record the decision here.

### TASK_05: Finding model and output renderers

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Items 29, 30, 31, 32, 33, 34, 36, 54, 58.
- **Lessons learnt:** _None yet._
- **Things to consider:** Build with the four required fields first. Test JSON escaping with quotes and backslashes in file names.

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
