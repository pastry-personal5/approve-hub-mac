# Phase 1: Core Mac approvals

Status: Active
Goal: Deliver a usable early Mac release in which an owner registers a requesting app, reviews ordinary requests in one window, decides them, and returns the outcome to the requester.

P1-M1 and P1-M2 established the research, approved architecture, and building skeleton. The remaining milestones implement the smallest complete requester-to-owner loop. [Product behavior](../product-behavior.md) retains approved goals for later phases.

## Exit criteria

- The owner can register, list, and revoke a requesting app's credential and export the service public-key pin through the owner CLI.
- A client verifies a fresh service signature against its pinned public key before sending bearer credentials. An unknown, wrong, or unverifiable listener fails closed.
- An authorized requester can submit an ordinary request, wait by either supported pattern, cancel its own request, and receive the terminal outcome. An unauthorized or sensitive request is rejected.
- The Mac window shows live pending requests, full immutable request detail, and Approve and Deny actions; the GUI uses the service API and contains no approval policy.
- The bundled app can start an absent service, the approved `approve-hub service` command can run it in the foreground, and a port collision fails closed.
- The requester-to-GUI-to-requester end-to-end suite runs rather than skips. Manual checks, milestone evidence, and the [full validation gate](../contribution-guide.md#required-validation) pass.

## Release boundary

The GUI must remain open to show pending requests. Phase 1 has no notification or menu-bar alert. Requests and outcomes are transient across a service restart, so requesters must fail closed when the service disappears. Rules, session grants, history, sensitive approvals, agent adapters, and iOS are deferred. Phase 1 rejects a request flagged sensitive; it does not silently downgrade it to an ordinary request. M3 must settle first-run credential bootstrap and public-key pin distribution before M4 defines the contract.

## Milestones

### P1-M1: Initial Research
Status: Done
Goal: Research approval flows, client connection, hosting, and security, and add a building SwiftPM skeleton.
Plan: [overview](milestone-01-overview.md), [architecture](milestone-01-architecture.md)
Notes: Research notes accepted by the owner on 2026-10-07. Product scope accepted into [product-behavior.md](../product-behavior.md). Owner decisions are in the [changelog](changelog.md).

### P1-M2: Software Architecture
Status: Done
Goal: Decide the architecture, name the API server, and record it in `docs/architecture.md`.
Plan: [overview](milestone-02-overview.md), [architecture](milestone-02-architecture.md)

### P1-M3: Core release design
Status: Done
Goal: Approve the single-window UX, credential setup, pinned service-key protocol, and explicit release exclusions.
Plan: [overview](milestone-03-overview.md), [architecture](milestone-03-architecture.md)
Notes: Owner-approved design and interview record are in the [phase changelog](changelog.md).

### P1-M4: API contract
Status: Done
Goal: Define and verify the `/v1` contract for identity, requester and decider operations, events, and errors.
Plan: [overview](milestone-04-overview.md), [architecture](milestone-04-architecture.md)

### P1-M5: Request lifecycle
Status: Done
Goal: Implement immutable ordinary requests and fail-closed lifecycle transitions.
Plan: [overview](milestone-05-overview.md), [architecture](milestone-05-architecture.md)

### P1-M6: Identity and credentials
Status: Done
Goal: Persist service and role credentials and provide owner credential commands.
Plan: [overview](milestone-06-overview.md), [architecture](milestone-06-architecture.md)

### P1-M7: ApproveHub Service
Status: Done
Goal: Serve the role-scoped API with bounded waits, events, stable errors, and fail-closed hosting.
Plan: [overview](milestone-07-overview.md), [architecture](milestone-07-architecture.md)

### P1-M8: Mac approval window
Status: Planned
Goal: Show and decide live pending requests in the Mac GUI.
Plan: [overview](milestone-08-overview.md), [architecture](milestone-08-architecture.md)

### P1-M9: Bundle and launch
Status: Planned
Goal: Package the app and helper and support GUI and foreground service launch.
Plan: [overview](milestone-09-overview.md); technical approach before activation.

### P1-M10: Early-release acceptance
Status: Planned
Goal: Verify and document the complete requester-to-GUI-to-requester flow.
Plan: [overview](milestone-10-overview.md); technical approach before activation.
