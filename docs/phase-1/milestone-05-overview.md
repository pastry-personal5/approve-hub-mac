# P1-M5: Request lifecycle

Status: Planned

Implement the UI-free lifecycle defined by the [contract](milestone-04-overview.md). Write this milestone's technical approach before activation.

## Goal

Make ordinary requests immutable and terminal outcomes deterministic under races and expiry.

## Scope

In: create, wait, cancel, decide, default two-minute and maximum ten-minute expiry, canonical request digest check, first-decision-wins, and rejection of sensitive requests. Pending requests and outcomes are transient across service restart.

Out: HTTP hosting, credential storage, GUI, rules, session grants, and decided history.

## Completion checklist

- [ ] **Lifecycle actor:** Only valid transitions are possible; terminal outcomes never change; sensitive requests are rejected before becoming pending.
- [ ] **Focused tests:** Actor tests cover expiry bounds, cancellation ownership, decision/cancel/expiry races, repeated or late decisions, digest mismatch, and restart semantics.
- [ ] **Docs and gate:** The technical approach and affected docs are current, M5 status is updated after evidence exists, and the full validation gate passes.
