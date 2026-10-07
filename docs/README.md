# Documentation index

Status: Active

This index lists the design and process docs, one line each. Read only the doc you need. The rules for writing docs are in [AGENTS.md](../AGENTS.md) under "Documentation".

| Doc | What it covers |
|-----|----------------|
| [development-process.md](development-process.md) | Phases, milestones, IDs (`P1-M2`), definition of done, where plans live, and doc status values. |
| [contribution-guide.md](contribution-guide.md) | Local setup, required validation, commit message style, and pull request conventions. |
| [product-behavior.md](product-behavior.md) | Product scope: what the app does and what it deliberately does not do. |
| [ux-terms.md](ux-terms.md) | Canonical component names for UI text, with their code-facing identifiers. |
| [ux-information-architecture.md](ux-information-architecture.md) | The Standard Layout: how the app's components contain one another. |
| [ux-gui.md](ux-gui.md) | Current interface and owner-approved GUI behavior, with planned behavior kept separate. |
| [roadmap.md](roadmap.md) | Every phase, one line each, and which phase is active. |
| [phase-1/phase-1.md](phase-1/phase-1.md) | Phase 1, Foundation: goal, exit criteria, and its milestones. |
| [phase-1/milestone-01-overview.md](phase-1/milestone-01-overview.md) | P1-M1, Initial Research: scope, research topics, and completion checklist. |
| [phase-1/milestone-01-architecture.md](phase-1/milestone-01-architecture.md) | P1-M1 technical approach: research method, note template, sequence, and skeleton. |
| [phase-1/milestone-02-overview.md](phase-1/milestone-02-overview.md) | P1-M2, Software Architecture: scope, required architecture sections, and completion checklist. |
| [phase-1/milestone-02-architecture.md](phase-1/milestone-02-architecture.md) | P1-M2 technical approach: how the decisions and the architecture doc get made. |
| [phase-1/changelog.md](phase-1/changelog.md) | Phase 1 decisions, owner calls and design changes, newest first. |
| [research-agent-approval-flows.md](research-agent-approval-flows.md) | How Claude Code and Codex CLI raise approvals, where a third-party app can intercept or connect, and how each fails. |
| [research-request-decision-interaction.md](research-request-decision-interaction.md) | What an approval request and decision carry, and how a requesting app gets the decision, with prior art. |
| [research-transport-and-server.md](research-transport-and-server.md) | Wire protocol and Swift server options for the API, with package facts and a hold-open and event-stream spike. |
| [research-hosting-and-packaging.md](research-hosting-and-packaging.md) | Where the API server could run, how SwiftPM becomes an `.app`, and signing, sandbox and macOS version floors. |
| [research-security-and-exposure.md](research-security-and-exposure.md) | Trust boundary, authentication per role, network exposure, iOS pairing, and spoof and replay resistance. |
| [research-ios-client.md](research-ios-client.md) | iOS push, background and local network limits, relay options, and what the API must offer an iOS client. |
