# P1-M3: Core release design

Status: Done

Approve the behavior and trust setup needed before the [API contract](milestone-04-overview.md). The [technical approach](milestone-03-architecture.md) defines the decision sequence.

## Goal

Give M4–M10 one owner-approved design for the single-window Mac release and the first-run trust path.

## Scope

In: pending-list and detail behavior; Approve and Deny actions; empty, loading, disconnected, expired, and error states; component terms and containment; credential setup and recovery; service signing key, client pin distribution, fresh challenge and signature verification before bearer credentials; exact Phase 1 exclusions and fail-closed cases.

Out: endpoint schemas, GUI implementation, credential implementation, notifications, menu-bar badge, rules, grants, history, Touch ID approval, agent adapters, and iOS.

## Completion checklist

- [x] **Owner-approved UX:** [GUI behavior](../ux-gui.md), [layout](../ux-information-architecture.md), and [terms](../ux-terms.md) specify the single window, list/detail/actions, accessibility, and empty/error states; owner acceptance is recorded in the [changelog](changelog.md).
- [x] **First-run trust path:** [architecture](../architecture.md) specifies service-key creation and persistence, how the owner obtains and distributes a trustworthy public-key pin, how the GUI obtains its decider credential, how requesters receive credentials, and recovery/revocation without silent trust-on-first-use. The owner approves it in the changelog.
- [x] **Identity protocol:** Architecture specifies the fresh challenge, signed data, signature and key encodings, replay boundary, key rotation behavior, and client verification order before any bearer token is sent; wrong pin, unknown listener, replay, and occupied port fail closed.
- [x] **Core behavior:** [Product behavior](../product-behavior.md) and architecture distinguish the early release from later approved goals, document transient outcomes after restart, and reject flagged sensitive requests.
- [x] **Owner review and docs:** The owner accepts the design; AGENTS.md and the documentation index point to current decisions; M3 is marked Done only after its evidence exists.
- [x] **Gate:** `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test` pass.
