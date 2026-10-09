# P1-M5: Request lifecycle, technical approach

Status: Done

The UI-free request lifecycle is implemented in `ApproveHubCore` against the [canonical M4 contract](../../Sources/openapi.yaml). It uses the owner-selected M5 text-safety and idempotency policies; HTTP hosting, credential storage, and SSE transport remain in later milestones.

## Boundaries and model

Add one `RequestLifecycle` actor in `ApproveHubCore`. It owns every in-memory request, terminal outcome, idempotency record, waiter, pending count, and internal transition revision for one service lifetime. Constructing a new actor starts with no requests or keys; no disk adapter or restoration path is added. M6 supplies an authenticated, opaque requester identity and its owner-assigned stable name. M7 calls the actor only after authentication and maps typed domain errors to the M4 Problem Details codes.

The actor stores a private record with immutable `let` fields for the service-assigned UUID, requester identity key and name, exact accepted action type and text, sensitive flag, optional session ID, original requested lifetime, creation time, effective deadline, and digest. It stores state and optional resolution time separately. A public value snapshot copies these fields without exposing the internal requester identity key. The snapshot's name comes from the authenticated context, never the create input. Ownership and idempotency scope use the opaque identity key rather than the display name, so equal names cannot grant cross-requester access.

The actor exposes domain operations corresponding to create, submit-and-wait, stepwise wait, cancel, decide, and a pending snapshot. The two wait patterns share the same waiter mechanism. Core values and errors remain independent of HTTP status codes, `Authorization`, Keychain, GUI state, and SSE frame formatting. M7 maps them to generated contract types and verifies that wire timestamp spelling matches the strings M5 hashes.

## Validation and creation

Validate the decoded input before adding any request or idempotency record. Require a nonempty action type of at most 128 characters; at most 16,384 UTF-8 bytes of exact submitted text; an optional nonempty session ID of at most 256 characters; and positive requested expiry seconds. Omitted expiry becomes 120 seconds. Preserve the original requested value in the snapshot and calculate the effective deadline using `min(requestedExpirySeconds, 600)`. Reject `sensitive: true` before pending insertion. Reject malformed fields and unsafe text with distinct typed errors for M7's `malformed_input`, `sensitive_request_not_supported`, and `unsafe_request_text` responses.

The owner chose a conservative, deterministic safety check in the core before storage. Reject control characters other than tab and line feed, Unicode format controls (including bidirectional overrides and zero-width characters), line/paragraph separators, private-use code points, and Unicode noncharacters in caller-visible action type or submitted text. Do not normalize, rewrite, mask, or truncate accepted content. For submitted text, also reject recognizable credential material: PEM or OpenSSH private-key blocks, a populated `Authorization: Bearer` header, common provider token prefixes with token-length suffixes, and populated assignments or JSON-like fields named `password`, `passwd`, `secret`, `client_secret`, `api_key`, `access_token`, `refresh_token`, or `private_key` (case-insensitive). Keep the exact signatures in one documented validator with positive and harmless-near-match fixtures; do not claim that pattern matching detects every secret. M8 handles display presentation without changing stored text.

Creation checks the 100-pending cap atomically. A rejected sensitive, unsafe, malformed, or over-capacity attempt creates no request, key reservation, or event. For an accepted request, assign a UUID, compute its digest, record the key, insert a pending record, and publish one internal `created` transition in one actor turn. `pending_request_limit_reached` and `Retry-After` are mapped by M7; the actor exposes the capacity error and earliest pending deadline.

## Digest and timestamps

Generate the `sha256:` digest from the exact eight-field object in [M4](milestone-04-architecture.md#digest-and-examples): `actionType`, `createdAt`, `expiresAt`, `id`, `requesterName`, `sensitive`, `sessionID`, and `text`. Serialize those fixed ASCII keys in RFC 8785 order, with JSON string escaping, lowercase JSON booleans, and explicit `null` for an absent session ID. The input contains no JSON numbers, so a small dedicated canonicalizer can meet this contract without adding a dependency. Hash its UTF-8 bytes with CryptoKit SHA-256, then use unpadded Base64url. Test the M4 example and independent quote, backslash, newline, and non-ASCII vectors so an ordinary JSON encoder cannot silently change the digest.

Use a single UTC RFC 3339 representation with fixed millisecond precision for snapshot timestamps and digest input. Quantize the wall-clock creation time once, calculate the displayed effective expiry from that timestamp, and keep these strings immutable. Compare expiry using a monotonic clock so a wall-clock adjustment cannot extend an approval window. Inject a test clock providing both wall time and monotonic advancement. M7 must verify that generated response encoding preserves the same timestamp strings that M5 hashed; if the generated `Date` mapping changes their spelling, fix the adapter before serving the API rather than changing the digest or the canonical spec silently.

## Idempotency and ownership

Key each create/submit retry record by `(authenticatedRequesterID, Idempotency-Key)` for the current actor lifetime. Compare decoded semantic fields after defaults are applied: JSON property order and whitespace do not matter, and omitted expiry equals explicit `120`. Preserve the exact decoded Unicode sequence when comparing strings and opaque keys; canonically equivalent but differently encoded strings are distinct inputs. An exact semantic retry refers to the original request ID and returns its **current** snapshot; submit-and-wait reattaches to that request until terminal. A changed semantic input returns the typed `idempotency_key_reused` error. Validate the key's length and encoding at the M7 boundary as specified by OpenAPI. Keep successful keys and terminal snapshots until actor teardown, because the M4 contract gives retries service-lifetime scope. Rejected attempts do not reserve keys.

Requester reads, waits, and cancellation require the matching internal requester identity key. Unknown IDs, IDs owned by another requester, and IDs lost after actor recreation all produce the same `request_not_found` domain error. The decider path receives no requester credential and can decide only through the M7 decider authorization boundary.

## State transitions and waits

Only `pending` may become `approved`, `denied`, `expired`, or `cancelled`. Every mutation first checks whether the monotonic deadline has passed; at the deadline (`now >= deadline`) expiry wins over a late decision or cancel, even if a scheduled wakeup has not run. The first terminal transition records one resolution time, decreases the pending count once, and publishes one `terminal` transition. Later cancel or matching-digest decision calls return the unchanged current terminal snapshot. A decision checks its digest against the stored immutable digest before attempting a transition; mismatch returns a typed `digest_mismatch` error even when the request is terminal.

Register waiters under actor isolation after checking the current state to avoid a lost wakeup. A stepwise wait accepts 1–30 seconds and returns the current snapshot when that interval ends or the request becomes terminal. Submit-and-wait has no 30-second step limit and wakes only on a terminal state. Expiry wakes both kinds. Multiple waiters on one request all receive the same terminal snapshot. Cancelling a client task removes only that waiter; it does not cancel the approval request. Test-clock advancement drives scheduled expiry and waiter timers without real sleeps.

The actor exposes pending snapshots newest first, paired atomically with a monotonically increasing internal transition revision. It emits ordered `created` and `terminal` transition records for M7 to turn into `request.created` and `request.terminal` SSE frames. M7 owns opaque event IDs, the bounded replay buffer, `Last-Event-ID`, and the `409 event_cursor_unavailable` response. M7 subscribes to transitions before binding the listener and does not return a list cursor until its event buffer has reached the snapshot's revision. If continuity is lost, it returns replay loss instead of silently skipping events. This handoff avoids a list-to-stream race without putting HTTP or SSE framing in the core.

## Implementation sequence and evidence

1. Add immutable domain inputs, snapshots, typed errors, an injectable clock, and the pure text validator and digest encoder in `ApproveHubCore`.
2. Add the lifecycle actor with atomic creation, idempotency, ownership checks, capacity, transitions, waiters, expiry, and internal transition revisions.
3. Add focused tests in `Tests/ApproveHubCoreTests`: M4 digest and timestamp vectors; accepted exact text and rejected safety cases; default and capped expiry; 100-pending capacity; same and changed-key retries; cross-requester concealment; concurrent decisions, cancel, and expiry at the deadline; repeated and late decisions; both wait flows and waiter cancellation; pending order and transition revisions; actor recreation losing all requests and keys.
4. Run the [full gate](../contribution-guide.md#required-validation), update affected docs and the M5 checklist with evidence, and only then mark M5 Done. M6–M7 implement credential and HTTP behavior against these domain interfaces.

No new package dependency, build tool, on-disk request store, GUI code, or public API endpoint is part of M5.

## Completion evidence

`Tests/ApproveHubCoreTests/RequestContentTests.swift` covers the M4 digest fixture, escaping vectors, and exact Unicode retry comparison. `RequestLifecycleTests.swift` covers millisecond timestamps, default and capped expiry, the exact-deadline race, sensitive and unsafe rejection, idempotency and ownership, the 100-pending limit, repeated and concurrent terminal operations, both wait flows and cancellation, transition revisions, and actor recreation. On 2026-10-08, `swift format lint --strict --recursive Sources Tests`, `swiftlint lint --strict`, `swift test` (13 tests), and the M4 contract checker passed.
