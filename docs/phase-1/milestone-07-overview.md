# P1-M7: ApproveHub Service

Status: Planned

Expose the [contract](milestone-04-overview.md), [lifecycle](milestone-05-overview.md), and [identity](milestone-06-overview.md) over loopback HTTP. Write this milestone's technical approach before activation.

## Goal

Run a role-scoped, fail-closed service that supports both requester wait patterns and live decider updates.

## Scope

In: `127.0.0.1:46931` listener, signed identity challenge, requester and decider authorization, bounded waits, SSE event IDs and bounded replay, explicit replay-loss recovery, Problem Details, Origin rejection, and fail-closed port collision.

Out: GUI, bundle launch, LAN exposure, and later-phase features.

## Completion checklist

- [ ] **API:** Service implements the generated contract without exposing requester decision authority or credentials to an unverified listener.
- [ ] **Cross-process tests:** Both wait patterns, authorization scopes, cancellation, SSE replay and replay loss, restart refresh, Origin rejection, stable errors, and port collision pass.
- [ ] **Docs and gate:** The technical approach and affected docs are current, M7 status is updated after evidence exists, and the full validation gate passes.
