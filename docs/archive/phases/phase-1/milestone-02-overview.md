# P1-M2: Software Architecture

Status: Done

Decide ApproveHub's architecture from the P1-M1 research, name the API server, and record it in `docs/architecture.md`. The technical approach is in [milestone-02-architecture.md](milestone-02-architecture.md); the phase is [phase-1.md](phase-1.md).

## Goal

Turn the open choices from P1-M1 into owner-approved decisions, and write one architecture doc that later milestones build against.

## Scope

In:

- Naming the API server.
- `docs/architecture.md`, with the sections listed below.
- Resolving every item in AGENTS.md "Undecided", or deferring it with the owner's approval and a stated reason.
- Reflecting the owner's product decisions of 2026-10-07 (expiry, Touch ID for sensitive requests, session grants, no edits, history) in the state machine, security model and persistence sections. See the [changelog](changelog.md).
- Approval of any dependency or build tool the architecture needs.
- Reshaping the skeleton to match the chosen layout.

Out:

- The endpoint-level API spec. It is a later milestone that is not planned yet. This milestone decides transport style, auth model and versioning only.
- Implementing the server, any client, any adapter or the iOS app.
- Interaction design. [ux-gui.md](../../../ux-gui.md) and the other UX docs stay with the owner.

Starts after P1-M1 is `Done`, because it decides what P1-M1 researched.

## Required sections of `docs/architecture.md`

1. Components and boundaries: the API server, requesting apps, deciding clients (Mac GUI, iOS app) and storage.
2. Hosting model, from the P1-M1 hosting note.
3. Client roles: the Mac GUI uses the same API as the iOS app. Any exception needs the owner's approval and is recorded.
4. Request lifecycle and approval state machine: states, transitions and expiry. This logic lives outside SwiftUI views.
5. API shape: transport style, live-update mechanism, versioning and error model. Not endpoints.
6. Security model: authentication per role, transport security, device pairing, request integrity and audit.
7. How requesting apps connect. Agent-specific integration with Claude Code CLI and Codex CLI is deferred to later phases, so this section only records the constraints from the P1-M1 agent-flow findings that the API must not rule out.
8. Module and target layout, including how API types can be shared with an iOS client.
9. Concurrency under Swift 6, and typed-error handling.
10. Persistence.
11. Test strategy.

## Completion checklist

Check an item only after its evidence exists.

- [x] **Server name:** the owner selected **ApproveHub Service**. Evidence: [AGENTS.md](../../../../AGENTS.md), [architecture.md](../../../architecture.md), and [changelog.md](changelog.md). It contains no prohibited source-code term.
- [x] **Undecided items:** each is decided or explicitly deferred. Evidence: AGENTS.md "Undecided" holds only owner-approved deferred items, with reasons; the remaining decisions are in [architecture.md](../../../architecture.md) and the changelog.
- [x] **Architecture doc:** Evidence: [architecture.md](../../../architecture.md) is indexed in [docs/README.md](../../../README.md), has every required section, and links to the P1-M1 research.
- [x] **Dependencies:** Evidence: [architecture.md](../../../architecture.md) lists every direct dependency, version, license compatibility, and owner approval in the changelog.
- [x] **Skeleton matches the layout:** Evidence: `Package.swift` has the contract, core, service, and SwiftUI app targets described in [architecture.md](../../../architecture.md). The owner approved the restructure in the changelog.
- [x] **Owner review:** Evidence: the owner accepted [architecture.md](../../../architecture.md), logged in [changelog.md](changelog.md).
- [x] **Gate:** Evidence: `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test` passed on 2026-10-08.
- [x] **Docs:** Evidence: AGENTS.md "Decided" and "Undecided" are current, README.md documents the service architecture, and P1-M2 is marked done in [phase-1.md](phase-1.md).
