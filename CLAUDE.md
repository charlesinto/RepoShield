# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

RepoShield is a local security scanner for cloned repositories. It is a modular Bash CLI (`repo-shield`) that checks a directory for vulnerable dependencies, malicious code patterns, secrets, and dangerous install/build hooks. Target platforms are macOS and Linux. It is distributed through a Homebrew tap.

## Source of truth

- **`docs/technical_specifications.md`** is the knowledge base for what the CLI does: behavior, CLI flags, exit codes, finding schema, and scope. Read it before making behavior changes.
- **`RepoShield.md`** is the original Technical Requirement Document. The specification in `docs/` was derived from it. Treat `RepoShield.md` as the historical input and `docs/` as authoritative.

When behavior changes, update `docs/technical_specifications.md` in the same change. When the spec and the code disagree, flag it rather than silently picking one.

Items listed in Section 9 ("Open Questions & Gaps") of the spec that are still `Open` are undecided. Do not assume an answer. Ask, or record the decision in the spec first.

## Tasks and progress (mandatory)

- Implementation is split into tasks in `docs/tasks/TASK_<NN>.md`. Each task lists its goal, acceptance criteria, spec sections, dependencies, and blockers.
- **Read `docs/progress.md` before implementing any task.** Check the task's status, blockers, lessons learnt, and things to consider. Do not start a task that is `Blocked` without first confirming with the user that its blockers are resolved.
- **Update `docs/progress.md` after implementing a task.** Update the summary row and the task's entry: status, outcome, blockers identified, lessons learnt, and things to consider. Do this even when the task is not finished.
- Update the task file's status line when the status changes.

## Constraints

- **Dependencies are fixed.** The only hard requirements are POSIX utilities, `jq`, and `curl`. `yara` and `semgrep` are optional and must be detected at runtime. Do not add other required dependencies without updating the spec.
- **Exit codes are part of the interface.** `0` for a clean scan, `1` for `--fail-on-critical` with critical findings, and `1` for invalid arguments.
- **Performance target:** repositories under 100 MB in under 10 seconds.
- **Built-in exclusions** (`.git/`, `node_modules/`, `.venv/`, `vendor/`, `target/`, `dist/`) are always skipped.

## Layout

```
RepoShield/
├── CLAUDE.md                          # this file
├── RepoShield.md                      # original TRD (input)
└── docs/
    ├── technical_specifications.md    # knowledge base / source of truth
    ├── progress.md                    # task status, blockers, lessons (read before, update after each task)
    └── tasks/
        └── TASK_01.md ... TASK_15.md  # implementation tasks derived from the spec
```

CLI source (TASK_01 onward):

- `bin/repo-shield`: entry point. Holds `REPO_SHIELD_VERSION` and resolves its own `lib/` through symlinks.
- `lib/cli.sh`: argument parser, usage, and dependency check. Parsed options live in `CLI_*` variables.
- `lib/target.sh`: target path resolution. Resolved absolute directories live in `TARGET_DIRS`.
- `lib/traverse.sh`: file traversal and ignore rules. `traverse_target` fills `SCAN_FILES` and `SCAN_SKIPPED`. `.gitignore` handling lives only in `traverse_gitignore_excludes`.
- `lib/classify.sh`: file classification. `classify_target` fills `CLASSIFIED_MANIFEST`, `CLASSIFIED_SOURCE`, and `CLASSIFIED_LIFECYCLE` from `SCAN_FILES`. Source extensions (`CLASSIFY_SOURCE_EXTS`, spec item 19) are matched case-insensitively.
- `tests/cli_test.sh`: acceptance checks. Run with `/bin/bash tests/cli_test.sh`. Use `/bin/bash` (3.2 on macOS) so the Bash 3.2 requirement is tested. No build step.
- `tests/traverse_test.sh`: traversal and ignore-rule acceptance checks. Run with `/bin/bash tests/traverse_test.sh`.
- `tests/classify_test.sh`: classification acceptance checks. Run with `/bin/bash tests/classify_test.sh`.

## Working conventions

- Match the style of the existing code once it exists. Until then, keep docs concise and use the same section numbering as the spec.
- Keep the finding schema stable. Changes to JSON field names are breaking changes for downstream CI users.
- Commit messages follow Conventional Commits.
