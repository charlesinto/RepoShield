# RepoShield Progress Log

**Read this file before starting any task. Update it after finishing any task.**

Each task has one entry below. Record every change to a task's status here, even when the task is not done.

**Status values:** `Not started`, `In progress`, `Blocked`, `Done`, `Done (with follow-ups)`

---

## Summary

| Task | Title | Phase | Status | Blockers (spec items) |
| --- | --- | --- | --- | --- |
| [TASK_01](tasks/TASK_01.md) | CLI skeleton and exit codes | 1 | Done | 59 |
| [TASK_02](tasks/TASK_02.md) | Target path resolution | 1 | Not started | 52, 58 |
| [TASK_03](tasks/TASK_03.md) | Ignore rules and safe traversal | 1 | Not started | 55, 60 |
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

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Item 52 (inferred rule), item 58 (multi-path reporting).
- **Lessons learnt:** _None yet._
- **Things to consider:** Resolve symlinked top-level targets once.

### TASK_03: Ignore rules and safe traversal

- **Status:** Not started
- **Outcome:** _None yet._
- **Blockers identified:** Item 60 (`.gitignore` conflict with the TRD), item 55 (binary files).
- **Lessons learnt:** _None yet._
- **Things to consider:** `.repo-shield-ignore` syntax is not specified. Working assumption: `.gitignore`-style globs. Confirm and record here.

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
