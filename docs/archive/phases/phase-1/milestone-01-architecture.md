# P1-M1: Initial Research, technical approach

Status: Done

How the research and the skeleton in [milestone-01-overview.md](milestone-01-overview.md) get done. No product code is written except the skeleton.

## Research method

- **Sources, in order:** primary documentation and source code first. Use the Context7 MCP for library, framework and CLI documentation. Use web search for the rest.
- **Citations:** each claim cites a URL, the version it applies to and the date it was read. For agent tools, record the version examined. A claim that no primary source confirms is marked `Unverified`.
- **Experiments:** the owner allows experiments without asking first, for example running an agent CLI with a hook against a throwaway directory. Scripts and runs live in the session scratchpad, not in the repo, and only their findings are recorded. They may use the owner's API credits and logged-in agent sessions, so each note states which experiments ran and what they used. No experiment reads or changes the owner's files outside the scratchpad, and no secret or token is written into a note.
- **Notes recommend, they do not decide.** A note may end with a recommendation. A decision is made in P1-M2 and recorded in AGENTS.md "Decided".

## Note template

Each research note follows the docs format in AGENTS.md: title, `Status: Draft`, then a one- to three-sentence summary. Sections:

1. Questions: the questions from the overview, copied as headings.
2. Findings: one subsection per question, with citations.
3. Options: each option with its trade-offs.
4. Recommendation (optional).
5. Open questions: anything that needs an owner or P1-M2 decision.
6. Sources.

A note's status moves to `Active` when the owner accepts it. It is archived once its conclusions have become decisions.

## Sequence

1. **Skeleton and gate.** It is small and independent, and it puts the gate in place early.
2. **Agent scope** is fixed by the owner (Claude Code and Codex CLI), so no shortlist step is needed.
3. **Topics 1 and 2**, which can run in parallel. Their findings feed topics 3 to 5.
4. **Topics 3, 4 and 5.** Topic 4 depends on topic 3 for the server technology. Topic 5 depends on topics 3 and 4 for the exposure options.
5. **Topic 6**, which can start as soon as topic 2 is drafted.
6. **Consolidation:** add the open choices from every note to the existing list in AGENTS.md "Undecided", and write the product-scope proposal.
7. **Owner review and wrap-up:** owner accepts each note, then the gate, then the docs updates.

## Skeleton

- `Package.swift` with `swift-tools-version: 6.0` and no `platforms` entry beyond what the skeleton needs. The minimum macOS version is a topic 4 question and a P1-M2 decision.
- One executable target named `ApproveHub` with an entry point that does nothing yet, and one test target `ApproveHubTests` with a single trivial test. No UI, server or request-handling code.
- Tests use `@testable import ApproveHub`. If the toolchain cannot test an executable target, fall back to a library target plus a thin executable, and record that in [changelog.md](changelog.md).
- No third-party dependencies. `swift format` runs with its default settings, so there is no `.swift-format` file. Add a `.swiftlint.yml` only if the default SwiftLint rules cannot pass.
- The layout is deliberately minimal. P1-M2 owns the real module layout and may restructure it with the owner's approval.
- Names follow AGENTS.md: no `phase` or `MVP` in any identifier, comment or string.

## Constraints

- The stack, license and "ask before" rules in [AGENTS.md](../../../../AGENTS.md) apply. The research may list candidate dependencies, but adding one needs the owner's approval, and none is added in this milestone.
- Keep each fact in one place. Notes link to each other and to the overview instead of copying.
