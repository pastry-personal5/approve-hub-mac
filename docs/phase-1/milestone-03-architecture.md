# P1-M3: Core release design, technical approach

Status: Done

Sequence the owner decisions needed for the [M3 overview](milestone-03-overview.md). This milestone updates design docs and does not implement a protocol or screen.

## Inputs and constraints

Use the accepted [product behavior](../product-behavior.md), [architecture](../architecture.md), [M2 evidence](milestone-02-overview.md), and the reopened [phase boundary](phase-1.md). Preserve the M1/M2 decisions unless the owner explicitly changes one. The GUI remains an API client; requesters cannot decide. A caller must verify a fresh service signature with a previously trusted public-key pin before sending bearer credentials.

## Decision sequence

1. **Window and vocabulary:** Present the owner with a concrete single-window request list and detail, action placement, selection and refresh behavior, and loading, empty, disconnected, expired, cancellation, and error states. Resolve exact visible terms and containment in the three UX docs. Include keyboard and VoiceOver behavior.
2. **Credential bootstrap:** Present exact first-run steps for service signing-key creation and persistence, the GUI's decider credential, requester registration, display or export of a new requester token exactly once, and owner recovery. Decide who can invoke setup, where credentials live, and how an uninitialized service behaves. Record the owner-approved sequence before M4.
3. **Pin distribution:** Present a trustworthy local export and transfer path for the service public-key pin, including how each requester and GUI installs it, what happens when it is absent or wrong, and how rotation is handled. A port response alone, bearer-token acceptance, and silent trust-on-first-use are insufficient. Record exact owner steps and failure behavior before M4.
4. **Challenge protocol:** Specify nonce generation, freshness and replay handling, service signature input and encoding, identity/key identifier, and verification order. Bind the signed proof to this service and challenge. Define how clients avoid credential disclosure on unknown or occupied ports. M4 translates this design into OpenAPI; M6 and M7 implement it.
5. **Failure and exclusion pass:** Walk through service down, timeout, restart, replay loss, cancellation, digest mismatch, token revocation, and sensitive-flag rejection. Make the service, client, and GUI responsibilities explicit. Keep rules, grants, history, notifications, menu-bar alerting, and Touch ID decisions outside the early release.
6. **Approval:** Record the owner-approved design in the changelog, update the authoritative UX and architecture documents, then run the required gate. Only then mark M3 Done and write M4's technical approach before activation.

## Owner-approved design

The owner accepted the following design through the P1-M3 interview on
2026-10-08. It deliberately leaves endpoint paths, HTTP headers, request
schemas, and CLI spelling to their implementation milestones.

### Standard Layout and interaction

The early release has one ordinary macOS window titled **ApproveHub**. It is a
two-column inbox-style window: a **Request List** in the sidebar and **Request
Detail** in the content area. The Request List contains only live pending
ordinary requests, ordered newest first. Each row shows requester, action
type, and a one-line submitted-text preview. Selecting its title opens the
full detail. A newly arriving request does not steal an existing selection;
when there is no selection, the newest pending request is selected.

Request Detail shows the complete immutable request, including requester,
action type, submitted text, request identifier, expiry, and digest. The
owner can make either of the only two decisions with **Approve** and **Deny**
controls at its top-right. Matching icon controls also appear at the right of
every Request List row and decide that row immediately; they have visible
tooltips and complete VoiceOver labels. Neither decision requires a
confirmation dialog, and Approve has no keyboard shortcut. Both the list and
detail actions are disabled unless the GUI has a currently verified service
identity, its decider credential, and a pending request. They remain
unavailable for expired, cancelled, or already-decided requests. A decision is
sent only for the exact immutable request and its digest. After a decision,
the newest remaining request is selected.

The window has these mutually exclusive presentation states:

- **Connecting:** no request action is available while the GUI is obtaining a
  fresh service proof and connecting its event stream.
- **No Pending Requests:** the connected empty state says that ApproveHub is
  ready and waiting; it does not imply that the service will notify the owner.
- **Pending Request:** the list and the selected full detail are visible.
- **No Longer Available:** a selected request that expires, is cancelled, or
  is decided elsewhere stays visible only as a non-actionable terminal state
  until the selection changes or the next refresh. It is not retained as
  history.
- **Disconnected:** the GUI labels any last-known list as stale, disables
  actions, and offers Retry. It distinguishes a stopped or unreachable
  service from an identity failure.
- **Setup Required or Identity Error:** an uninitialized service shows Setup
  Required. A missing/wrong service pin, malformed proof, or expired/replayed
  challenge has no Retry-that-bypasses-trust path and directs the owner to
  recovery. A missing or rejected decider credential can trigger only the
  separately specified local-helper recovery after successful pin verification.
- **Request Error:** a recoverable refresh or action error appears inline in
  the affected detail, preserves safe current state where possible, and never
  presents an uncertain request as approvable.

The GUI exposes the Request List, Request Detail, state message, Retry,
Approve, and Deny by those names to VoiceOver. Focus moves to the state
message when the selection becomes unavailable, and otherwise stays with the
owner's current control. Standard keyboard navigation reaches every control;
color is not the only indication of connection, error, or destructive action.

### Explicit first-run and recovery path

The owner, while logged in to the local macOS account, performs an explicit
local setup command before the service can accept network traffic. Setup:

1. creates one persistent Ed25519 service signing key in an owner-only
   Application Support location;
2. creates a separate random decider bearer credential, stores only its
   password-quality hash with the service, and writes the GUI copy to the
   owner's Keychain;
3. creates no requester credential implicitly;
4. writes the initial GUI pin only as part of this explicit setup; and
5. presents the owner with a versioned public-key pin and its fingerprint for
   independent transfer to each requester.

An uninitialized service neither binds the loopback port nor accepts an
unauthenticated setup request. When the GUI starts its bundled helper and it
reports this declared uninitialized exit state, the GUI shows a Setup Required
page with the owner CLI next step; when no helper is started, an unreachable
port remains simply Disconnected. The GUI never generates a service identity,
trusts a listener on first use, or turns a normal Retry into setup. The owner
uses the local command, not the loopback API, to initialize, add/list/revoke
requesters, or rotate the service key. Exact command names and storage APIs
are implementation detail for P1-M6.

Requester registration creates a distinct random bearer token, shows it once
to the owner for delivery to that requester, and stores only its
password-quality hash. The owner transfers the token and the matching pin by
an independent, owner-controlled route; neither is obtained from the service
over its normal loopback API. A requester must install the received pin before
it can make an authenticated request. Losing a requester token means issuing a
replacement and revoking the old one. Resetting the GUI's decider credential
revokes the old credential and replaces its Keychain item. Credential
replacement and revocation are auditable without logging a secret. If the GUI
credential is missing or rejected, the GUI first verifies the pinned service
proof. Only after that verification may it invoke its bundled local helper to
revoke and replace the decider credential and update the Keychain item. An
identity-proof failure never triggers this automatic recovery.

The public-key pin is a versioned document containing the protocol version,
the `ed25519` algorithm name, the 32-byte Ed25519 public key, and its key
identifier. The key and SHA-256 key identifier use unpadded base64url; the
identifier is the SHA-256 digest of the raw public-key bytes. The export also
shows a grouped hexadecimal SHA-256 fingerprint for an owner to compare over
the independent transfer route. A pin is public but its integrity is security
critical: it is never learned from a listener, a normal API response, or an
automatic key-change prompt.

Service-key rotation is a hard, owner-initiated cutover. The local command
generates a new signing key, replaces the local GUI pin, and exports a new pin
for the owner to distribute before affected requesters can resume. Existing
clients reject the new key until the owner explicitly installs the new pin;
the service never silently accepts an old or new pin as equivalent. A suspected
key compromise uses the same cutover path, plus explicit requester or decider
credential revocation when appropriate.

### Service-identity proof

Before every bearer-bearing request, a client obtains a fresh service proof.
Each proof is bound to a newly generated 32-byte CSPRNG challenge. The client
keeps that challenge private until it sends the unauthenticated proof request,
accepts it once, and discards it after at most 60 seconds. It never reuses
challenges across requests or retries.

The service returns an unsigned proof payload containing exactly: the protocol
label `approvehub-service-proof-v1`; the fixed listener
`http://127.0.0.1:46931`; its key identifier; the challenge; an issued-at time;
and an expiry no more than 60 seconds after issue. It RFC 8785-canonicalizes
that payload as UTF-8 and signs those bytes with its Ed25519 key. The
signature is the raw 64-byte Ed25519 signature encoded as unpadded base64url.
The public key is the raw 32-byte Ed25519 representation encoded the same
way. This uses the CryptoKit-compatible `Curve25519.Signing` key and signature
representations; the signing key is not reused as a key-agreement key.

Before a client sends its bearer credential, it verifies all of the following,
in order: the response has the expected protocol and fixed listener; the key
identifier equals the installed pin's identifier; the proof challenge equals
its still-unused challenge; the times fall inside its 60-second freshness
window; and the canonical payload's signature verifies against the installed
raw public key. Only then may it transmit its role-specific bearer credential.
A failed check,
malformed encoding, reused challenge, missing pin, unknown key, wrong pin,
timeout, or a port occupied by a listener that cannot provide this proof is an
identity failure: no bearer credential is sent and the operation fails closed.
The proof authenticates the service key, not a browser origin; `Origin`
headers remain rejected and role authorization remains required.

The nonce is the replay boundary: a captured response cannot satisfy a new
client challenge, and a client never accepts its own challenge twice. The
short expiry bounds the usefulness of a response even if a client crashes
before discarding its local state. Requesters block their controlled action on
every identity failure, service disappearance, cancellation, expiry, or
rejection; the GUI disables decisions and represents its last state as stale.

### Release boundary

The service rejects a request carrying the sensitive flag before it enters the
pending list. It does not downgrade it to ordinary. Pending requests and all
outcomes are in-memory only; after a service restart, clients refresh, treat
their interrupted waits as failed, and requesters block their controlled
action. This release includes neither notifications nor a menu-bar badge,
rules, grants, decided history, Touch ID approval, agent-specific adapters,
LAN or remote exposure, iOS pairing, nor iOS support.

## Outputs

Update [ux-gui.md](../ux-gui.md), [ux-information-architecture.md](../ux-information-architecture.md), [ux-terms.md](../ux-terms.md), [architecture.md](../architecture.md), [product-behavior.md](../product-behavior.md), AGENTS.md, and the [changelog](changelog.md). Keep exact endpoint names and schemas for M4; M3 must nevertheless settle bootstrap and proof semantics so M4 does not invent them.
