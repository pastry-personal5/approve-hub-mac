# P1-M4: API contract

Status: Done

The canonical `/v1` OpenAPI contract translates [M3](milestone-03-overview.md)'s first-run trust and GUI behavior into generated Swift interfaces. The [technical approach](milestone-04-architecture.md) records the exact fields, flows, and verification evidence.

## Goal

Give the service, requester, and Mac GUI generated bindings with one tested contract.

## Scope

In: schemas for the unauthenticated service-identity challenge, requester create, submit-and-wait, stepwise wait and cancel, decider pending list and decide, live SSE events and cursor recovery, and RFC 9457 Problem Details with stable error codes. Define exact request digest fields and encoding, role scopes, bounds, and sensitive-request rejection.

Out: server behavior, lifecycle storage, GUI implementation, and later-phase rules, grants, history, notifications, and sensitive approval.

## Completion checklist

- [x] **Contract:** [`Sources/openapi.yaml`](../../Sources/openapi.yaml) describes every in-scope operation, request and response schema, authentication scope, wait limit, event cursor, and error code, with examples for ordinary and rejected sensitive requests.
- [x] **Generated bindings:** `swift test` built the shared types and generated client and server targets from one symlinked spec. No generated source is checked in.
- [x] **Contract checks:** The generated-interface tests type-check both wait patterns; `ruby Tests/ContractValidation/validate.rb` verifies examples, digest representation, error shapes, role scopes, and SSE replay-loss response.
- [x] **Docs and gate:** The technical approach and affected docs are current. On 2026-10-08, `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test` passed, along with the contract checker.
