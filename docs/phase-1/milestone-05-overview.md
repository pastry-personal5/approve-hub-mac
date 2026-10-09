# P1-M5: Request lifecycle

Status: Done

Implement the UI-free lifecycle defined by the [contract](milestone-04-overview.md). The [technical approach](milestone-05-architecture.md) fixes actor boundaries, validation, timing, digest, retries, and test evidence before activation.

## Goal

Make ordinary requests immutable and terminal outcomes deterministic under races and expiry.

## Scope

In: create, wait, cancel, decide, default two-minute and maximum ten-minute effective expiry, canonical request digest check, first-decision-wins, idempotency and pending capacity, and rejection of sensitive or unsafe text before storage. Pending requests and outcomes are transient across service restart.

Out: HTTP hosting, credential storage, GUI, rules, session grants, and decided history.

## Completion checklist

- [x] **Lifecycle actor:** `RequestLifecycle` enforces valid terminal transitions, sensitive and unsafe rejection before pending state, semantic idempotency, a 100-pending cap, and both wait flows.
- [x] **Focused tests:** Ten new core tests cover expiry bounds, ownership, races, repeated decisions, digest mismatch, idempotency, text safety, waiters, revisions, and actor recreation.
- [x] **Docs and gate:** The [technical approach](milestone-05-architecture.md#completion-evidence) and affected docs are current; the full validation gate passed on 2026-10-08.
