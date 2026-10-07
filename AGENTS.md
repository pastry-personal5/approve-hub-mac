# AGENTS.md

Instructions for AI coding agents and contributors working in this repository.

This file is the **single source of agent instructions**. `CLAUDE.md` is a one-line stub that imports it with `@AGENTS.md`. Leave the stub as it is and put new guidance here.

## Project

`approve-hub-mac`: A Mac app with a GUI for approving what your AI agents ask to do. AI asks. You decide. Your agent continues.

Stack: Swift with SwiftPM, swift-format, SwiftLint and swift test.

See [README.md](README.md) for the user-facing overview and [docs/product-behavior.md](docs/product-behavior.md) for product scope. Setup, validation, commit message, and pull request conventions are in [docs/contribution-guide.md](docs/contribution-guide.md). Design and process docs are indexed at [docs/README.md](docs/README.md).

## Agent workflow

- Work autonomously only on a clearly scoped task within the active milestone. `docs/roadmap.md` identifies the active phase (create it when the first phase is planned); follow its milestones in order unless its phase plan says otherwise.
- Before starting implementation, read the active phase and milestone plans, the relevant design docs, and the applicable items under "Undecided" below.
- Before executing a milestone, add a completion checklist to its overview doc. The checklist is its executable definition of done; it replaces a narrative "Done when" section.
- Check an item only after its acceptance evidence exists. Keep implementation, tests, and directly affected documentation in the same change.
- A milestone is complete only when every checklist item is checked and the gate passes: `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test`. If a command cannot run, leave its related item unchecked and report the exact blocker.
- Ask before deciding an item in "Undecided", adding or changing a dependency or build tool, deleting user data, or broadly restructuring the repository. Everything else that is within the approved milestone and task scope may proceed without a separate approval.

## Decided — do not change without asking

- **Technical stack:** Swift with SwiftPM, swift-format, SwiftLint and swift test.
- **Product scope:** [product-behavior.md](docs/product-behavior.md). It covers what ApproveHub is, the API server and its clients, the threat model, agents, iOS, where the server runs and how it starts, the macOS 26 floor and own-Mac use, requests and expiry, fail-closed behavior, deciding (Touch ID, grants, digests) and history. The owner's decisions are dated in [docs/phase-1/changelog.md](docs/phase-1/changelog.md).
- **Interaction model:** [ux-gui.md](docs/ux-gui.md). Component vocabulary is in [ux-terms.md](docs/ux-terms.md) and the layout containment model in [ux-information-architecture.md](docs/ux-information-architecture.md).
- **License:** Apache-2.0 for all project code.
- **Development process:** work is organized in numbered phases (Phase 1, 2, 3, …). Each phase has numbered milestones (Milestone 1, 2, 3, …), and milestone numbering restarts in every phase. Milestone IDs look like `P1-M2`. See [docs/development-process.md](docs/development-process.md).
- **Server stack:** Hummingbird as the server and Swift OpenAPI Generator (a SwiftPM build plugin) with its runtime and transports are approved in principle. P1-M2 lists the exact packages, versions and licenses, and nothing is added to `Package.swift` before the milestone that needs it.
- **Local transport:** apps and the GUI reach the server on a loopback port with a token, and the server checks the Origin header.
- **App build and signing:** a script in the repo builds the `.app` from the SwiftPM output and signs it ad-hoc. There is no App Sandbox, and no Developer ID signing or notarization, because the app runs only on the owner's own Macs. Script and file names follow the code naming rules below.

## Undecided — ask before inventing

List open product and architecture questions here as they come up, and ask before building on one. P1-M1 adds the choices its research raises. P1-M2 decides them.

- **API server name:** decided in P1-M2. See [docs/phase-1/changelog.md](docs/phase-1/changelog.md).
- **Integration styles:** which integration mechanisms to support first for agents (hook shim, host app, channel relay). Deferred with the known agents to later phases. See [research-agent-approval-flows.md](docs/research-agent-approval-flows.md).
- **Exposure and iOS:** local network only or remote access, the relay route, the pairing method and the iOS minimum version. Needed only once an iOS client is planned, since iOS is not in the first release. See [research-security-and-exposure.md](docs/research-security-and-exposure.md) and [research-ios-client.md](docs/research-ios-client.md).

## Environment setup

- macOS with a Swift 6.2 toolchain (Xcode 26 or later), which provides `swift build`, `swift test` and `swift format`
- SwiftLint (`brew install swiftlint`)

## Commands

```sh
swift build                                        # build the app
swift run                                          # run the app
swift test                                         # run the tests
swift format --in-place --recursive Sources Tests  # format the code
swiftlint lint --strict                            # lint with warnings treated as errors
```

Before you consider a change done, run the gate: `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test`.

## Code conventions

- Format with `swift format` and its default settings; do not hand-format.
- Keep `swiftlint lint --strict` clean; no warnings are allowed.
- Handle errors with `throws` and typed error values; no force unwrap (`!`) or `try!` outside tests.
- Keep UI code in SwiftUI views and keep approval logic out of the views so it can be tested.
- Don't use phase words such as `phase`, `phase-1`, `phase1`, or `phase_1` in source-code names: modules, files, types, functions, variables, constants, tests, or build and script targets. Name code after the concept it owns.
- Don't use `MVP` in any form (`MVP`, `mvp`, `Mvp`) anywhere in source code or scripts, including identifiers, comments, and strings. Those terms belong only in `docs/`.

## Dependencies and licensing

- Ask before adding or changing a dependency or build tool. Approved dependencies must have licenses compatible with Apache-2.0.

## Documentation

- **Where docs go:**
  - `README.md` is user-facing.
  - `AGENTS.md` holds the rules for contributors and agents.
  - `docs/` holds design, research, process, and plan docs.
  - `docs/archive/` holds docs that are no longer active.
- **Format:** filenames are lowercase kebab-case. Each doc starts with a title, then a `Status:` line, then a one- to three-sentence summary.
- **Index:** add every new doc to [docs/README.md](docs/README.md) with a one-line description.
- **Phases and milestones:** phase plans and milestone status follow [docs/development-process.md](docs/development-process.md).
- **Phase-plan filenames:** every phase overview is named `phase-N.md`, where `N` is its phase number; never use a generic `phase.md`.
- **Milestone checklists:** each milestone overview has a completion checklist instead of a "Done when" section. Check an item only after its acceptance evidence exists; do not mark the milestone `Done` until every item is checked and the full gate passes.
- **Keep docs current:**
  - Update docs in the same change as the code or decision they describe.
  - Update `README.md` when user-visible features, requirements, or build steps change.
  - Update this file when build commands, tooling, or project decisions change, or when an item under "Undecided" gets decided.
- **Link, don't copy.** Each fact lives in one place, and other docs link to it.
- **Archive, don't delete:**
  1. When a doc is finished or superseded (for example a completed phase plan), set its status line.
  2. `git mv` it into `docs/archive/`. A finished phase directory (`docs/phase-N/`) moves as a whole into `docs/archive/phases/`.
  3. Fix every link to it.

  Archived docs are not maintained.

## Token efficiency

This file is loaded in every session, so keep it short. Long-form material belongs in `docs/`.

- **Skip generated and bulky files.**
  - Never read or search build output and dependency directories (`.build/`, `DerivedData/`, `.swiftpm/`).
  - Search with `rg` or `git grep`, which skip ignored files.
  - Don't open lockfiles, `LICENSE`, or `docs/archive/` unless the task needs them.
- **Read docs narrowly.** Start with `docs/README.md`, then read only what the task needs. For long docs, list the headings with `rg -n '^#' <file>` and read just the relevant section.
- **Keep build output small.** Use the quiet flags of the stack's tools, and filter long logs, for example with `2>&1 | rg 'error|warning' | head -n 40`.
- **Iterate narrowly, verify once.**
  - While iterating, run only the affected tests.
  - Run the full gate once, before calling the change done.
- **Look up APIs at the source.** Grep the pinned version of a dependency's source, or the one module or header you need, instead of browsing its whole tree.
- **Ask before building on an undecided item.** Redoing work is the most expensive outcome.
- **Edit, don't rewrite.**
  - Change files with targeted edits.
  - Don't re-read a file to confirm an edit.
  - Check `git diff --stat` before reading a full diff.
- **Reply briefly.** Summarize command output and diffs instead of pasting them.
