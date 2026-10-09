# Documentation index

Status: Active

This index lists the design and process docs, one line each. Read only the doc you need. The rules for writing docs are in the [contribution guide](contribution-guide.md#documentation).

| Doc | What it covers |
|-----|----------------|
| [development-process.md](development-process.md) | Phases, milestones, IDs (`P1-M2`), definition of done, where plans live, and doc status values. |
| [contribution-guide.md](contribution-guide.md) | Contributor and agent workflow, setup, code and documentation rules, validation, and review conventions. |
| [product-behavior.md](product-behavior.md) | Product scope: what the app does and what it deliberately does not do. |
| [architecture.md](architecture.md) | Approved component boundaries, hosting, security, persistence, package layout, and test strategy. |
| [ux-terms.md](ux-terms.md) | Canonical component names for UI text, with their code-facing identifiers. |
| [ux-information-architecture.md](ux-information-architecture.md) | The Standard Layout: how the app's components contain one another. |
| [ux-gui.md](ux-gui.md) | Current interface and owner-approved GUI behavior, with planned behavior kept separate. |
| [roadmap.md](roadmap.md) | Every phase, one line each, and which phase is active. |
| [phase-1/phase-1.md](phase-1/phase-1.md) | Active Phase 1, Core Mac approvals: goal, exit criteria, release boundary, and milestones. |
| [phase-1/milestone-01-overview.md](phase-1/milestone-01-overview.md) | Completed P1-M1 research scope and completion evidence. |
| [phase-1/milestone-01-architecture.md](phase-1/milestone-01-architecture.md) | Completed P1-M1 technical approach. |
| [phase-1/milestone-02-overview.md](phase-1/milestone-02-overview.md) | Completed P1-M2 architecture scope and completion evidence. |
| [phase-1/milestone-02-architecture.md](phase-1/milestone-02-architecture.md) | Completed P1-M2 technical approach. |
| [phase-1/milestone-03-overview.md](phase-1/milestone-03-overview.md) | Completed P1-M3 core release design scope and acceptance evidence. |
| [phase-1/milestone-03-architecture.md](phase-1/milestone-03-architecture.md) | Completed P1-M3 owner-approved UX, credentials, and service-identity design. |
| [phase-1/milestone-04-overview.md](phase-1/milestone-04-overview.md) | Completed P1-M4 API contract scope and acceptance evidence. |
| [phase-1/milestone-04-architecture.md](phase-1/milestone-04-architecture.md) | P1-M4 canonical API approach, digest, operations, errors, and verification. |
| [phase-1/milestone-05-overview.md](phase-1/milestone-05-overview.md) | Completed P1-M5 request lifecycle scope and acceptance evidence. |
| [phase-1/milestone-05-architecture.md](phase-1/milestone-05-architecture.md) | Implemented P1-M5 lifecycle actor: validation, digest, time, retries, races, and tests. |
| [phase-1/milestone-06-overview.md](phase-1/milestone-06-overview.md) | Completed P1-M6 identity, credentials, owner CLI, and acceptance evidence. |
| [phase-1/milestone-06-architecture.md](phase-1/milestone-06-architecture.md) | Implemented P1-M6 credential storage, proof, CLI, recovery, and test approach. |
| [phase-1/milestone-07-overview.md](phase-1/milestone-07-overview.md) | Completed P1-M7 service API scope and acceptance evidence. |
| [phase-1/milestone-07-architecture.md](phase-1/milestone-07-architecture.md) | Implemented P1-M7 loopback HTTP service, authorization, and SSE replay. |
| [phase-1/milestone-08-overview.md](phase-1/milestone-08-overview.md) | Planned P1-M8 Mac approval window and acceptance evidence. |
| [phase-1/milestone-08-architecture.md](phase-1/milestone-08-architecture.md) | Planned P1-M8 SwiftUI decider client, request window, and SSE recovery approach. |
| [phase-1/milestone-09-overview.md](phase-1/milestone-09-overview.md) | Planned P1-M9 bundle and launch and acceptance evidence. |
| [phase-1/milestone-10-overview.md](phase-1/milestone-10-overview.md) | Planned P1-M10 early-release acceptance and closeout. |
| [phase-1/changelog.md](phase-1/changelog.md) | Active Phase 1 decisions, owner calls, and design changes. |
| [research-agent-approval-flows.md](research-agent-approval-flows.md) | How Claude Code and Codex CLI raise approvals, where a third-party app can intercept or connect, and how each fails. |
| [research-request-decision-interaction.md](research-request-decision-interaction.md) | What an approval request and decision carry, and how a requesting app gets the decision, with prior art. |
| [research-transport-and-server.md](research-transport-and-server.md) | Wire protocol and Swift server options for the API, with package facts and a hold-open and event-stream spike. |
| [research-hosting-and-packaging.md](research-hosting-and-packaging.md) | Where the API server could run, how SwiftPM becomes an `.app`, and signing, sandbox and macOS version floors. |
| [research-security-and-exposure.md](research-security-and-exposure.md) | Trust boundary, authentication per role, network exposure, iOS pairing, and spoof and replay resistance. |
| [research-ios-client.md](research-ios-client.md) | iOS push, background and local network limits, relay options, and what the API must offer an iOS client. |
