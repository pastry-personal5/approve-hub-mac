# P1-M8: Mac approval window

Status: Planned

Build the [M3](milestone-03-overview.md) owner-approved single-window design against the service API. The [technical approach](milestone-08-architecture.md) records its client boundary, trust path, and acceptance evidence.

## Goal

Let the owner see and decide ordinary pending requests in a live Mac window.

## Scope

In: pending list, complete immutable request detail, Approve and Deny, initial refresh, SSE updates, reconnection and replay-loss refresh, and empty, loading, disconnected, and error states.

Out: approval policy in views, notifications, menu-bar badge, Touch ID approval, rules, grants, and history.

## Completion checklist

- [ ] **Window:** The GUI follows approved UX, verifies the pinned service identity before its bearer credential, and uses the service API for list and decisions.
- [ ] **GUI tests:** Decisions, refresh, reconnect and replay-loss recovery, expired or cancelled selection, and connection/error states pass; views contain no approval policy.
- [ ] **Docs and gate:** The technical approach and affected docs are current, M8 status is updated after evidence exists, and the full validation gate passes.
