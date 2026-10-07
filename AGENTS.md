# AGENTS.md

Agent entry point for `approve-hub-mac`. Leave the `CLAUDE.md` import stub unchanged. Read the [contribution guide](docs/contribution-guide.md) before implementation; it holds workflow, code, validation, and documentation rules. Find design and process docs in the [documentation index](docs/README.md).

## Working boundaries

- Work on clearly scoped tasks in the active milestone; check the [roadmap](docs/roadmap.md) and plans first. Follow the [contribution guide](docs/contribution-guide.md) and [development process](docs/development-process.md).
- Ask before changing an approved decision below, deciding an open question, changing a dependency or build tool, deleting user data, or broadly restructuring the repository.

## Decided — do not change without asking

- **Product:** [product behavior](docs/product-behavior.md) and [Phase 1 decisions](docs/archive/phases/phase-1/changelog.md).
- **Architecture and dependencies:** [architecture](docs/architecture.md).
- **Interface:** [GUI behavior](docs/ux-gui.md), [terms](docs/ux-terms.md), and [layout](docs/ux-information-architecture.md).
- **Stack, licensing, and build process:** [contribution guide](docs/contribution-guide.md).

## Undecided — ask before inventing

Record open product and architecture questions here, and ask before building on one.

- **Agent integration style:** deferred until integrations are planned; see [agent-flow research](docs/research-agent-approval-flows.md).
- **Exposure and iOS:** route, pairing, and deployment floor deferred until an iOS client is planned; see [security](docs/research-security-and-exposure.md) and [iOS](docs/research-ios-client.md) research.
- **Local service identity:** how clients verify the listener before sending credentials; see [hosting](docs/architecture.md#hosting-model).
- **Sensitive-decision proof:** how Touch ID is evidenced to the service; see [request lifecycle](docs/architecture.md#request-lifecycle-and-state-machine).
