# P1-M6: Identity and credentials

Status: Done

Implement the [M3](milestone-03-overview.md) owner-approved bootstrap and service pin path. The [technical approach](milestone-06-architecture.md) records the implementation sequence and owner decisions.

## Goal

Persist service identity and role credentials and give the owner safe credential-management commands.

## Scope

In: persistent service signing key, requester credential hashes, separate GUI decider credential, owner CLI add/list/revoke requester commands, public-key pin export, and the approved first-run and recovery flow. Active requester names are unique. Replacing a token creates a new requester ID; revocation cancels that ID's pending requests. The CLI is credential administration, not an agent adapter.

Out: HTTP endpoints, agent-specific bridges, iOS pairing, and later-phase sensitive-decision signing proof.

## Completion checklist

- [x] **Storage and CLI:** Restart preserves identity and credentials; owner can add, list, and revoke requesters and export the service public-key pin following M3's approved flow. Active names are unique and explicit repeat setup restores a missing GUI pin. Add/revoke affects the next authenticated operation without a service restart; revocation cancels that requester's pending requests; key rotation refuses to run while the service is active. `setupRestartOneTimeOutputAndNameUniqueness`, `liveRevocationCancelsPendingBeforeAcknowledgement`, `liveOwnerRevocationWaitsForCancellationAcknowledgement`, and `deciderResetAndStoppedRotation` cover these boundaries.
- [x] **Secret handling:** Each new requester token is revealed once, then stored only as a password-quality hash; tokens are neither logged nor printed again. GUI credentials remain separate and protected in Keychain. File-content, command-output, and real Keychain round-trip assertions cover this.
- [x] **Tests:** Restart, live revocation and pending cancellation, new-ID replacement, duplicate-name rejection, missing-pin repair, stopped-service rotation, wrong-pin, wrong-role, concurrent-write, credential-storage, and secret-output tests pass. The M6 cross-process CLI acknowledgement test passes; M7 will verify fallback shutdown and decision/wait races with the HTTP service.
- [x] **Docs and gate:** The technical approach and setup docs are current. `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, and `swift test` passed on 2026-10-08 (29 tests after review fixes).
