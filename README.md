# RepoShield

RepoShield is a local security scanner for cloned repositories. It is a modular Bash CLI (`repo-shield`) that checks a directory for:

- vulnerable dependencies (SCA),
- malicious code patterns (SAST),
- secrets, and
- dangerous install and build hooks (lifecycle scripts).

It targets macOS and Linux, needs only POSIX tools, `jq`, and `curl`, and runs on the macOS default Bash 3.2. `yara` and `semgrep` are optional and are used when present.

> **Status:** early development. The scan pipeline is not wired up yet. The entry point stops after argument and target checks, so no scan results are reported yet.

## Usage

```sh
bin/repo-shield [options] <path>...
```

The full CLI reference (flags, output formats, and exit codes) is in [`docs/technical_specifications.md`](docs/technical_specifications.md), Sections 8 and 7.

## Supported manifests

| Ecosystem               | Files                                       |
| ----------------------- | ------------------------------------------- |
| JavaScript / TypeScript | `package.json`, `package-lock.json`         |
| Java / JVM              | `pom.xml`                                   |
| Python                  | `Pipfile.lock`, `requirements.txt`          |

Details of what each parser reads and skips are in spec Section 4.1.

## Repository layout

```
bin/repo-shield          entry point
lib/                     modules: cli, target, traverse, classify, sca, report, severity
tests/                   acceptance checks, one script per module, plus fixtures/
docs/                    specification, progress log, and task files
```

## Running the tests

Run each suite under `/bin/bash` so the Bash 3.2 requirement is tested:

```sh
for t in cli traverse classify report severity sca; do /bin/bash tests/${t}_test.sh; done
```

There is no build step.

## Open Issues

### `pom.xml` parser reads only some direct dependencies (TASK_07)

The Maven parser (`lib/sca.sh`, spec item 16A) reads only the direct `<dependency>` elements under `<project><dependencies>`. This is a limitation of the current implementation, not a decided behavior.

- **Ignored sections:** dependencies inside `<dependencyManagement>`, `<profiles>`, `<build>`, `<plugins>`, and `<exclusions>` are not reported. A dependency declared only in one of these sections is missed.
- **Unresolved properties:** a version written as a property (`${...}`) is not resolved from `<project><properties>`. The dependency is skipped with a warning, so its version is not checked.
- **Versions from a parent or BOM:** a dependency with no `<version>` (managed by a parent POM or BOM) is skipped with a warning. The parser does not follow `<parent>` or import BOMs.

Effect: a vulnerable Maven dependency can go unreported. Skipped entries are shown as warnings.

Tracking: spec items 56 (Maven variants) and 63 (`dependency:list` exports) are still open. The current behavior follows the working assumptions in spec Section 9.10. Resolving properties is not yet in the spec.

## Documentation

- [`docs/technical_specifications.md`](docs/technical_specifications.md): the source of truth for behavior, CLI, and output.
- [`docs/progress.md`](docs/progress.md): task status, blockers, and lessons learnt.
- [`docs/tasks/`](docs/tasks/): implementation tasks.
- [`RepoShield.md`](RepoShield.md): the original Technical Requirement Document.
