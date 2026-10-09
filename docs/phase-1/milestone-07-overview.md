# P1-M7: ApproveHub Service

Status: Done

Expose the [contract](milestone-04-overview.md), [lifecycle](milestone-05-overview.md), and [identity](milestone-06-overview.md) over loopback HTTP. The implementation and evidence are in the accompanying [technical plan](milestone-07-architecture.md).

## Goal

Run a role-scoped, fail-closed service that supports both requester wait patterns and live decider updates.

## Scope

In: `127.0.0.1:46931` listener, signed identity challenge, requester and decider authorization, bounded waits, SSE event IDs and bounded replay, explicit replay-loss recovery, Problem Details, Origin rejection, and fail-closed port collision.

Out: GUI, bundle launch, LAN exposure, and later-phase features.

## Completion checklist

- [x] **API:** The generated server interface serves every canonical operation from the fixed loopback listener. It rejects `Origin` before proof or credential work, exposes neither requester decision authority nor credentials to an unverified listener, and maps every expected failure to the specified Problem Details result.
- [x] **Cross-process tests:** Both wait patterns, requester ownership concealment, authorization scopes, idempotency retries, live requester revocation during create/wait/decision, pending cancellation before acknowledgement, fallback shutdown on acknowledgement failure, decision/wait races, cancellation, expiry, Origin rejection, stable errors, uninitialized state, and port collision pass.
- [x] **Events:** List-to-stream handoff has no lost transition; ordered replay, empty-list cursors, unknown and evicted cursors, source gaps, disconnect, and service-restart recovery produce the specified SSE or explicit replay-loss behavior.
- [x] **Docs and gate:** The technical approach and affected docs are current, M7 status is updated after evidence exists, and the full validation gate passes.

## Completion evidence

`fixedListenerServesProofRolesAndRequesterLifecycle` in [ServiceHTTPTests.swift](../../Tests/ApproveHubServiceTests/ServiceHTTPTests.swift) starts the real helper subprocess and covers proof verification, all requester and decider operations, SSE transport, role and ownership errors, concurrent create/decision/wait with live revocation, acknowledgement order, fallback shutdown, port collision, and restart loss. `brokerReplaysAfterListCursorAndRejectsLostPositions` and `brokerEvictionGapAndRestartInvalidateOldCursors` in [ServiceEventBrokerTests.swift](../../Tests/ApproveHubServiceTests/ServiceEventBrokerTests.swift) cover the 1,024-event buffer, ordered replay, empty-list cursor, source gap, and old-process cursor behavior. The [M5 core tests](../../Tests/ApproveHubCoreTests/RequestLifecycleTests.swift) exercise first-terminal-transition races and client task cancellation.

On 2026-10-09, `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test` passed from the repository root (33 Swift tests). The HTTP test uses an actual process at `127.0.0.1:46931`, including a second process that cannot bind the occupied port.
