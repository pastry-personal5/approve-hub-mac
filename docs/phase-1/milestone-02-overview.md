# P1-M2: Software Architecture

Status: Planned

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
- Interaction design. [ux-gui.md](../ux-gui.md) and the other UX docs stay with the owner.

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

- [ ] **Server name:** two or three candidates are proposed with rationale, and the owner picks one. Evidence: the name is under "Decided" in AGENTS.md, in `docs/architecture.md`, and in [changelog.md](changelog.md). It contains no `phase` or `MVP`.
- [ ] **Undecided items:** each is decided or explicitly deferred. Evidence: AGENTS.md "Undecided" holds only deferred items, each with a reason and the owner's approval. The rest are under "Decided", and the changelog has one entry per decision.
- [ ] **Architecture doc:** Evidence: `docs/architecture.md` exists, is indexed in [docs/README.md](../README.md), has every required section, and each choice links to a P1-M1 note or a "Decided" item.
- [ ] **Dependencies:** Evidence: each proposed dependency or build tool is listed with its license and Apache-2.0 compatibility and has the owner's approval in the changelog. If none is needed, the architecture doc says so.
- [ ] **Skeleton matches the layout:** Evidence: the target layout in `Package.swift` matches the architecture doc. Any restructure was approved by the owner first and is logged.
- [ ] **Owner review:** Evidence: the owner accepts `docs/architecture.md`, and the acceptance is logged in [changelog.md](changelog.md).
- [ ] **Gate:** Evidence: `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict` and `swift test` all pass.
- [ ] **Docs:** Evidence: AGENTS.md "Decided" and "Undecided" are current, README.md is updated if user-visible facts changed, and the P1-M2 status is updated in [phase-1.md](phase-1.md).
