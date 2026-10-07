# P1-M4: API contract

Status: Planned

Define the canonical `/v1` OpenAPI contract after [M3](milestone-03-overview.md) settles first-run trust and GUI behavior. Write this milestone's technical approach before activation.

## Goal

Give the service, requester, and Mac GUI generated bindings with one tested contract.

## Scope

In: schemas for the unauthenticated service-identity challenge, requester create, submit-and-wait, stepwise wait and cancel, decider pending list and decide, live SSE events and cursor recovery, and RFC 9457 Problem Details with stable error codes. Define exact request digest fields and encoding, role scopes, bounds, and sensitive-request rejection.

Out: server behavior, lifecycle storage, GUI implementation, and later-phase rules, grants, history, notifications, and sensitive approval.

## Completion checklist

- [ ] **Contract:** `/v1` OpenAPI describes every in-scope operation, request and response schema, authentication scope, wait limit, event cursor, and error code, with examples for ordinary and rejected sensitive requests.
- [ ] **Generated bindings:** Swift client and server bindings generate and compile from the canonical spec; generated files are handled as the approved build process requires.
- [ ] **Contract checks:** Automated checks exercise schema compatibility, digest representation, stable error shapes, and both requester wait patterns.
- [ ] **Docs and gate:** The technical approach and affected docs are current, M4 status is updated after evidence exists, and the full validation gate passes.
