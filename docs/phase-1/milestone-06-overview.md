# P1-M6: Identity and credentials

Status: Planned

Implement the [M3](milestone-03-overview.md) owner-approved bootstrap and service pin path. Write this milestone's technical approach before activation.

## Goal

Persist service identity and role credentials and give the owner safe credential-management commands.

## Scope

In: persistent service signing key, requester credential hashes, separate GUI decider credential, owner CLI add/list/revoke requester commands, public-key pin export, and the approved first-run and recovery flow. The CLI is credential administration, not an agent adapter.

Out: HTTP endpoints, agent-specific bridges, iOS pairing, and later-phase sensitive-decision signing proof.

## Completion checklist

- [ ] **Storage and CLI:** Restart preserves identity and credentials; owner can add, list, and revoke requesters and export the service public-key pin following M3's approved flow.
- [ ] **Secret handling:** Each new requester token is revealed once, then stored only as a password-quality hash; tokens are neither logged nor printed again. GUI credentials remain separate and protected in Keychain.
- [ ] **Tests:** Restart, revocation, wrong-pin, credential-storage, and secret-output tests pass.
- [ ] **Docs and gate:** The technical approach and setup docs are current, M6 status is updated after evidence exists, and the full validation gate passes.
