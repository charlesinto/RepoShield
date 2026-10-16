# TASK_10: Built-in SAST checks

- **Status:** Not started
- **Phase:** 3 (Static code and build hook analysis)
- **Spec sections:** 5.1, 7.4
- **Depends on:** TASK_04, TASK_06

## Goal

Detect obfuscated payloads used with execution sinks, reverse shells, and secrets, using regex and entropy checks. No external tools.

## Acceptance criteria

- [ ] Flags Base64 or hex content together with an execution sink (`eval()`, `Function()`, `exec()`, `vm.runInNewContext()`) as `OBFUSCATED_EXECUTION` (`HIGH`).
- [ ] Flags socket connections that launch `/bin/sh`, `/bin/bash`, `cmd.exe`, or `powershell.exe` bound to a remote host as `REVERSE_SHELL` (`CRITICAL`).
- [ ] Flags private SSH key headers and the fixed credential patterns as `SECRET_EXPOSED`.
- [ ] Flags high-entropy strings above the threshold as `SECRET_EXPOSED`.
- [ ] Each finding has the file path and a description. Line numbers are included only if item 29 says so.
- [ ] Checks run only on classified source files (TASK_04).
- [ ] Each check has a fixture that triggers it and a clean fixture that does not.

## Blockers

- Item 24: entropy threshold and minimum string length.
- Item 25: the exact credential pattern list.
- Item 62: category names (`SECRET_EXPOSED`, `OBFUSCATED_EXECUTION`, `REVERSE_SHELL`).
- Item 29: whether `line` is in the schema. Affects how the match is reported.

## Notes

- Regex-only detection of "socket connected to a shell" is weak. Write down what the regex can and cannot catch, in progress.md, so the limits are visible.
- Keep the patterns in data files, one per check, so they can be reviewed separately.
