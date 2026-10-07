# Contribution Guide

Status: Active

How contributors and coding agents work on `approve-hub-mac`: scope, setup, code and documentation rules, validation, and review conventions. [AGENTS.md](../AGENTS.md) indexes approved decisions and open questions; the [development process](development-process.md) defines phase and milestone plans.

## Scope and decisions

- Work autonomously only on a clearly scoped task within the active milestone. The [roadmap](roadmap.md) identifies the active phase; follow its milestones in order unless the phase plan says otherwise.
- Before implementation, read the active phase and milestone plans, the relevant design docs, and applicable open questions in [AGENTS.md](../AGENTS.md).
- Follow the [development process](development-process.md) for milestone plans, completion checklists, evidence, and status. Keep implementation, tests, and affected docs in the same change.
- Ask before deciding an open question, changing a dependency or build tool, deleting user data, or broadly restructuring the repository. Within an approved milestone and task scope, proceed without separate approval on other choices.
- All project code uses Apache-2.0. Approved dependencies must have compatible licenses; approved versions are in [architecture.md](architecture.md).

## Setup and development

- macOS with a Swift 6.2 toolchain (Xcode 26 or later), which provides `swift build`, `swift test` and `swift format`
- SwiftLint (`brew install swiftlint`)

The approved packaging design uses a repo script to build an `.app` from SwiftPM output and sign it ad-hoc. The app has no App Sandbox, Developer ID signing, or notarization because it runs on the owner's own Macs.

```sh
swift build                                        # build the app
swift run approve-hub                              # run the app skeleton
swift run approve-hub-service                      # run the service skeleton
swift format --in-place --recursive Sources Tests  # format the code
```

The Makefile offers `make build`, `make run`, `make test`, `make format`, `make lint`, and `make check`.

## Code conventions

- Format with the default `swift format` settings; do not hand-format. Keep `swiftlint lint --strict` free of warnings.
- Use `throws` and typed errors. Do not use force unwrap (`!`) or `try!` outside tests.
- Keep UI code in SwiftUI views and approval logic outside views so it can be tested.
- Name code after the concept it owns. Do not put phase words (`phase`, `phase-1`, `phase1`, `phase_1`) in module, file, type, function, variable, constant, test, or build and script target names.
- Do not use `MVP` in any case in source code or scripts, including identifiers, comments, and strings. It belongs only in `docs/`.

## Required validation

Before calling a change or milestone done, run the full gate from the repository root. If a command cannot run, leave its related milestone checklist item unchecked and report the exact blocker.

```sh
swift format lint --strict --recursive Sources Tests
swiftlint lint --strict
swift test
```

## Documentation

- `README.md` is the short user-facing overview. `AGENTS.md` is the agent entry point and decision index. `docs/` contains design, research, process, and plan docs; finished or superseded docs live in `docs/archive/`.
- Use lowercase kebab-case filenames. Begin each doc with a title, `Status:` line, and one- to three-sentence summary. Add new docs to the [index](README.md) with a one-line description.
- Follow the [development process](development-process.md) for phase and milestone plans, status, checklists, and filenames.
- Update directly affected docs with code or decisions. Update the root `README.md` when user-visible features, requirements, or build steps change. Update `AGENTS.md` when project decisions or open questions change.
- Link to the authoritative doc instead of copying its facts.
- Archive instead of deleting a finished or superseded doc: set its status, move it with `git mv` into `docs/archive/` (a finished phase directory goes under `docs/archive/phases/`), and fix links. Archived docs are not maintained.

## Efficient agent workflow

- Skip generated and bulky content. Never read or search `.build/`, `DerivedData/`, or `.swiftpm/`. Use `rg` or `git grep`; avoid lockfiles, `LICENSE`, and archived docs unless the task needs them.
- Start with the [documentation index](README.md), then read only relevant docs. For a long doc, list headings with `rg -n '^#' <file>` and read the needed sections.
- Keep build output small with quiet flags or focused filters. During iteration, run only affected tests; run the full gate once at the end.
- Look up APIs in the pinned dependency source, one module or header at a time.
- Make targeted edits without re-reading a file merely to confirm an edit. Check `git diff --stat` before reading a full diff, and summarize results instead of pasting long output.

## Bundled-app E2E host

`E2E/ApproveHubE2E.xcodeproj` is the minimal XCTest/XCUIAutomation host for
the bundled-app suite. It reserves injected biometric and notification ports;
the test is skipped until those adapters and the bundle launcher exist.

After building the app bundle, run the host manually:

```sh
xcodebuild -project E2E/ApproveHubE2E.xcodeproj -scheme ApproveHubE2ETests \
  -testPlan ApproveHubE2E -destination 'platform=macOS' test
```

Test real Touch ID and notification authorization manually. They are system
dialogs and are not automated by this host.

## Commit messages

Write commit messages in [Conventional Commits](https://www.conventionalcommits.org)
(Angular) style.

- **Title:** `<type>[(scope)]: <summary>` — lowercase, imperative, 50 characters
  or fewer, no trailing period. Types: `feat`, `fix`, `docs`, `style`,
   `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- **Body** (optional): one blank line after the title, then short paragraphs
  explaining *why* the change was made, wrapped at 72 characters. Keep it brief.

Keep each commit focused. Example:

    feat(parser): add support for nested lists

    Nested list items were flattened into a single level. Keep the nesting
    so the parsed document matches the source.

## Pull requests

When changes are proposed through a pull request, keep it focused and include:

- a short description of the user or maintenance impact;
- the relevant tests and documentation updates; and
- the result of the required validation commands, or the exact reason a command
  could not run.
