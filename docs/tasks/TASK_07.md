# TASK_07: SCA manifest parsers

- **Status:** Not started
- **Phase:** 2 (Multi-ecosystem SCA)
- **Spec sections:** 4.1
- **Depends on:** TASK_04, TASK_05

## Goal

Extract `(ecosystem, package name, version)` tuples from every supported manifest and lock file, using `jq` and POSIX tools only.

## Acceptance criteria

- [ ] `package-lock.json`: extracts pinned versions for every supported npm lockfile version (see blocker).
- [ ] `package.json`: extracts pinned versions where present. Version ranges are resolved from the lock file when one exists (item 14B).
- [ ] `pom.xml`: parses dependencies directly, including the version element (item 16A).
- [ ] `Pipfile.lock`: extracts pinned versions from the `default` and `develop` sections.
- [ ] `requirements.txt`: extracts `name==version` pins. Lines with ranges or no version are handled per the blocker.
- [ ] Each tuple records the ecosystem name used by OSV (`npm`, `Maven`, `PyPI`) (item 15).
- [ ] Malformed manifests produce a warning and are skipped, per Section 2.4.
- [ ] Parsers are tested against fixtures for each supported format version.

## Blockers

- Item 56: the concrete list of npm lockfile versions, Pipfile.lock formats, and pom.xml variants. "All versions" is not specific enough to build against.
- Item 57: ranges in `requirements.txt` with no lock file. Options: report as skipped with a `LOW` note, or other.
- Item 63: confirm that Maven `dependency:list` exports are not read.

## Notes

- Parsing `pom.xml` with `grep` and `sed` is fragile. Decide early whether to use `xmllint` (not a hard dependency) or a restricted XML approach. This is a design decision, so record it in progress.md before writing the parser.
- Property placeholders such as `${version}` in `pom.xml` need handling or a skip rule.
