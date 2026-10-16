# TASK_07: SCA manifest parsers

- **Status:** Done (with follow-ups)
- **Phase:** 2 (Multi-ecosystem SCA)
- **Spec sections:** 4.1
- **Depends on:** TASK_04, TASK_05

## Goal

Extract `(ecosystem, package name, version)` tuples from every supported manifest and lock file, using `jq` and POSIX tools only.

## Acceptance criteria

- [x] `package-lock.json`: extracts pinned versions for every supported npm lockfile version (see blocker). Provisional: v1, v2, and v3 (item 56).
- [x] `package.json`: extracts pinned versions where present. Version ranges are resolved from the lock file when one exists (item 14B).
- [x] `pom.xml`: parses dependencies directly, including the version element (item 16A).
- [x] `Pipfile.lock`: extracts pinned versions from the `default` and `develop` sections.
- [x] `requirements.txt`: extracts `name==version` pins. Lines with ranges or no version are handled per the blocker. Provisional: skipped with a warning (item 57).
- [x] Each tuple records the ecosystem name used by OSV (`npm`, `Maven`, `PyPI`) (item 15).
- [x] Malformed manifests produce a warning and are skipped, per Section 2.4.
- [x] Parsers are tested against fixtures for each supported format version (`tests/sca_test.sh`, `tests/fixtures/sca/`).

## Blockers

- Item 56: the concrete list of npm lockfile versions, Pipfile.lock formats, and pom.xml variants. "All versions" is not specific enough to build against. **Still Open.** Working assumption recorded in spec 9.10.
- Item 57: ranges in `requirements.txt` with no lock file. Options: report as skipped with a `LOW` note, or other. **Still Open.** Working assumption: skipped with a warning. The `LOW` note is not built.
- Item 63: confirm that Maven `dependency:list` exports are not read. **Still Open.** Working assumption recorded in spec 9.10.

## Notes

- Parsing `pom.xml` with `grep` and `sed` is fragile. Decide early whether to use `xmllint` (not a hard dependency) or a restricted XML approach. This is a design decision, so record it in progress.md before writing the parser. **Decided:** restricted awk parser, recorded in progress.md.
- Property placeholders such as `${version}` in `pom.xml` need handling or a skip rule. **Decided:** skip with a warning.
