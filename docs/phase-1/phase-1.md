# Phase 1: Foundation

Status: Active
Goal: Establish the research, the architecture, and a building, gate-passing app skeleton that agent integration and the API server will be built on.

## Exit criteria

- The research notes written in P1-M1 are accepted by the owner.
- `docs/architecture.md` is accepted by the owner and names the API server.
- Every item in "Undecided" in [AGENTS.md](../../AGENTS.md) is decided, or deferred with the owner's approval and a stated reason.
- `swift build` succeeds on the app skeleton and the full gate passes.

## Out of scope

Phase 1 builds no API server, no GUI, no agent adapter and no iOS app. It decides how they will fit together.

## Milestones

New milestones are added with the next free number.

### P1-M1: Initial Research
Status: Done
Goal: Research how agents raise approvals, how custom apps and clients can talk to ApproveHub, and what hosting and security options exist, and add a minimal SwiftPM skeleton so the gate can run.
Plan: [overview](milestone-01-overview.md), [architecture](milestone-01-architecture.md)
Notes: Research notes accepted by the owner on 2026-10-07. Product scope accepted into [product-behavior.md](../product-behavior.md). Owner decisions are in the [changelog](changelog.md).

### P1-M2: Software Architecture
Status: Planned
Goal: Decide the architecture, name the API server, and record it in `docs/architecture.md`.
Plan: [overview](milestone-02-overview.md), [architecture](milestone-02-architecture.md)
