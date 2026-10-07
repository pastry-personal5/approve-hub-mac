# P1-M1: Initial Research

Status: Done

Research how agents raise approvals, how custom apps and clients can talk to ApproveHub, and which hosting and security options exist. Add a minimal SwiftPM skeleton so the gate can run. The technical approach is in [milestone-01-architecture.md](milestone-01-architecture.md); the phase is [phase-1.md](phase-1.md).

## Goal

Give P1-M2 enough sourced findings to decide the architecture, and leave the repository with a skeleton that builds and passes the gate.

## Scope

In:

- Six research topics, each written up as a note in `docs/` (listed below).
- A list of open architecture choices in AGENTS.md "Undecided".
- A proposal for the text of [product-behavior.md](../../../product-behavior.md).
- A minimal SwiftPM skeleton.

Out:

- Building an API server, GUI, agent adapter or iOS app.
- Deciding the architecture. Notes may recommend; P1-M2 decides.
- Writing the content of `product-behavior.md` directly. It is a Decided doc, so the owner accepts text into it.
- Adding any third-party dependency or build tool.

## Research assumptions

Owner decisions of 2026-10-07, logged in [changelog.md](changelog.md). The notes research within them:

- **Agents:** Claude Code and Codex CLI only.
- **Requesting apps:** written only by the owner for now. Treat callers as authenticated but not public, and avoid choices that would block a public API later.
- **Deciders:** one owner on their own devices. Pairing means pairing the owner's own devices, and several-person approval is out of scope.
- **Remote access:** research both LAN-only and away-from-home options with trade-offs. P1-M2 decides.

## Research topics

Terms used in the notes: a *requesting app* is a custom app that submits approval requests. A *deciding client* is the Mac GUI or the iOS app, which shows requests and records approve or deny. Both terms are working names that P1-M2 finalizes.

1. **Agent approval flows and integration points** (`research-agent-approval-flows.md`)
   - For Claude Code and Codex CLI: how each raises an approval, what it waits on, how it resumes, and what happens on timeout or no answer. Add a short note on what supporting a third agent would take.
   - Where a third-party app can intercept or connect to that flow. Candidates to verify from primary docs: agent hooks, an MCP permission-prompt tool, SDK permission callbacks, protocol-level permission requests such as ACP, terminal or PTY wrapping, and a wrapper process.
   - Per integration point: can it block, can it allow, deny or modify, what context it exposes, whether it fails open or closed, and what trust or installation it needs.
   - Options for how a requesting app bridges an agent into ApproveHub's API.
   - The open product question of whether ApproveHub ships agent adapters or only the API.
2. **Request and decision interaction** (`research-request-decision-interaction.md`)
   - What a request carries: requester identity, action description, context, expiry, idempotency key.
   - Outcomes: approve, deny, expire.
   - How a requesting app that must block gets the decision: long-poll, polling, streaming or webhook.
   - Retries, idempotency and expiry behavior.
   - What happens when several deciding clients see the same request.
   - Prior art, such as OAuth CIBA and push-approval services.
3. **Transport and server technology** (`research-transport-and-server.md`)
   - HTTP/JSON with SSE or WebSocket compared with gRPC and other options.
   - Swift server options, such as SwiftNIO, Hummingbird, Vapor and Network.framework.
   - OpenAPI and client generation for Swift, and sharing API types between macOS and iOS.
   - License fit with Apache-2.0, maintenance status, Swift 6 concurrency support.
4. **Hosting and packaging** (`research-hosting-and-packaging.md`)
   - Server inside the GUI process, in a separate background process (launch agent or login item), or the GUI as a pure client.
   - What happens to queued requests when the GUI is closed, and how the GUI finds and connects to the server.
   - SwiftPM-only `.app` bundling, and what needs a bundle, such as notifications.
   - Sandbox entitlements for a listening server, hardened runtime, signing, notarization and distribution.
   - The minimum macOS version to support.
5. **Security and network exposure** (`research-security-and-exposure.md`)
   - Authentication for each role: requesting apps, the Mac GUI and the iOS app.
   - Loopback only versus LAN with TLS and Bonjour, iOS device pairing, and access away from home.
   - Spoofed or replayed approvals, and binding a decision to the exact request content.
   - Audit log and secret storage.
6. **iOS client constraints, survey only** (`research-ios-client.md`)
   - Push notifications (APNs needs a relay), the Local Network permission, background limits and discovery.
   - What the API must offer so an iOS client can work within those limits.

## Completion checklist

Check an item only after its evidence exists.

- [x] **Topic 1 note:** Evidence: `docs/research-agent-approval-flows.md` exists, is indexed in [docs/README.md](../../../README.md), answers every question above with a cited source, and follows the note template in [milestone-01-architecture.md](milestone-01-architecture.md) (Questions, Findings, Options, Recommendation, Open questions, Sources, plus a short Method section).
- [x] **Topic 2 note:** Evidence: `docs/research-request-decision-interaction.md`, same criteria.
- [x] **Topic 3 note:** Evidence: `docs/research-transport-and-server.md`, same criteria.
- [x] **Topic 4 note:** Evidence: `docs/research-hosting-and-packaging.md`, same criteria.
- [x] **Topic 5 note:** Evidence: `docs/research-security-and-exposure.md`, same criteria.
- [x] **Topic 6 note:** Evidence: `docs/research-ios-client.md`, same criteria.
- [x] **Undecided list:** every open architecture choice the notes raise is listed in AGENTS.md "Undecided". Evidence: each entry links to the note that raised it, and the adapters-or-API-only question is among them.
- [x] **Product-scope proposal:** Evidence: `docs/archive/research-product-scope.md` (written with `Status: Proposal`, archived once accepted), carrying the 2026-10-07 owner statements in [changelog.md](changelog.md). The owner accepted the text on 2026-10-07 and it is now in `product-behavior.md`; the acceptance is logged in the changelog.
- [x] **Skeleton:** a SwiftPM package with one executable target, one test target and no third-party dependencies. Evidence: `swift build` succeeds, and `swift test` runs at least one test and passes.
- [x] **Gate:** Evidence: `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict` and `swift test` all pass.
- [x] **Owner review:** Evidence: the owner accepts each note, and the acceptance is logged in [changelog.md](changelog.md).
- [x] **Docs:** Evidence: every new doc is indexed in [docs/README.md](../../../README.md), the P1-M1 status is updated in [phase-1.md](phase-1.md), and README.md is updated if the skeleton changes the build steps.
