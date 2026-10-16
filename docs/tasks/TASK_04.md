# TASK_04: File classification (dispatcher)

- **Status:** In progress (source extension criterion waits on item 19)
- **Phase:** 1 (Core shell engine)
- **Spec sections:** 2 (Dispatcher / Classifier), 2.1
- **Depends on:** TASK_03

## Goal

Sort each file from the file list into one category: manifest, source code, or lifecycle script. Each engine receives only its category.

## Acceptance criteria

- [x] Every file is assigned to at most one category.
- [x] Manifests and lock files are classified by name: `package.json`, `package-lock.json`, `pom.xml`, `Pipfile.lock`, `requirements.txt`.
- [x] Lifecycle files are classified by name: `setup.py`, `setup.cfg`, `build.rs`, `Makefile`.
- [ ] Source files are classified by extension. The extension list must match the decision on item 19. _(Mechanism built; list empty until item 19 is decided.)_
- [x] Files that match nothing are left unclassified and not scanned.
- [x] Classification is unit-tested with a fixture set.

## Blockers

- Item 19: the list of source code extensions is not decided. Do not hard-code a list until it is. Put the list in one variable so it can be filled in.

## Notes

- Some files are both source and lifecycle (for example `setup.py` is Python code). Decide whether the lifecycle category wins. Record the decision in progress.md.
