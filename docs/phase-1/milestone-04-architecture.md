# P1-M4: API contract, technical approach

Status: Done

This milestone turns the [M3 trust and request design](milestone-03-architecture.md) into the single [OpenAPI 3.1 contract](../../Sources/openapi.yaml). It supplies build-generated Swift types and client/server interfaces; service behavior belongs to M5–M7.

## Contract source and targets

`Sources/openapi.yaml` is authoritative. Each of `ApproveHubContract`, `ApproveHub`, and `ApproveHubService` has a relative `openapi.yaml` symlink to that file and its own `openapi-generator-config.yaml`. The approved Swift OpenAPI Generator build plugin emits shared public types in `ApproveHubContract`, a client importing that module in `ApproveHub`, and a server protocol importing it in `ApproveHubService`. Generated Swift is never checked in. The plugin is the already approved and pinned 1.14.0 dependency; this milestone adds no package dependency or new SwiftPM build tool.

The generated client and server interfaces do not themselves verify proof freshness, inject bearer headers, reject `Origin`, or authorize roles. M6–M7 must put those checks at the transport boundary before using these interfaces. The OpenAPI `security` requirements state the wire contract and do not replace enforcement.

The spec uses the fixed `http://127.0.0.1:46931` listener and `/v1` paths. The proof endpoint has no bearer requirement. All other endpoints have exactly one role-specific bearer requirement. Every bearer-bearing operation requires a newly generated challenge and successful verification of a fresh M3 Ed25519 service proof before its token is sent, including retries and SSE reconnects. The protocol label, listener, pin identifier, nonce, times, and signature are checked in M3's order. Every request carrying `Origin`, even a proof request, is rejected.

## Operations and lifecycle

| Operation | Success | Contract behavior |
|---|---:|---|
| `POST /v1/identity/proofs` | 200 | Accept one 32-byte unpadded Base64url challenge; return the exact six-field canonical-signature payload and Ed25519 signature. |
| `POST /v1/requester/requests` | 201 | Create an ordinary pending request and return its full snapshot. Require `Idempotency-Key`. |
| `POST /v1/requester/requests:submit-and-wait` | 200 | Create and hold until a terminal snapshot; require `Idempotency-Key`. |
| `POST /v1/requester/requests/{requestID}:wait` | 200 | Wait at most `waitSeconds` (1–30) and return the current full snapshot, possibly still pending. |
| `DELETE /v1/requester/requests/{requestID}` | 200 | Cancel if pending; return the current full snapshot. |
| `GET /v1/decider/requests` | 200 | Return up to 100 pending snapshots, newest first, and the matching event cursor. |
| `POST /v1/decider/requests/{requestID}:decide` | 200 | Approve or deny only with the matching immutable digest; return the current full snapshot. |
| `GET /v1/decider/events` | 200 | Decider-only `text/event-stream`, resumable through `Last-Event-ID`. |

All successful create, wait, cancel, and decide calls return a full `RequestSnapshot`. Terminal transitions are first-wins and idempotent: a subsequent cancel or matching-digest decision returns the unchanged terminal state. A pending result from a stepwise wait is never permission to run the controlled action. If a request is lost at restart, or a wait or service call fails, the requester blocks its action.

The server assigns an opaque UUID `id` and the stable `requesterName` from the authenticated credential. A caller submits `actionType` (1–128 characters), `text` (at most 16,384 UTF-8 bytes), the explicit `sensitive` flag, optional opaque `sessionID`, and optional positive `expirySeconds` (120 when omitted). The snapshot records the original `requestedExpirySeconds`; `expiresAt` is `createdAt` plus the lesser of that request and 600 seconds. The server later sets `resolvedAt` for a terminal state. Accepted request content and all these fields are immutable. The server rejects `sensitive: true` before adding it to the pending list; it also rejects M3's unsafe submitted text. No caller can supply a requester display name.

`Idempotency-Key` is scoped to the authenticated requester and current service lifetime. A retry with the same key and input refers to the original request; changed input with the same key returns `409 idempotency_key_reused`. A key and request lost on restart cannot recover an outcome. A requester must verify another fresh proof before each retry.

## Digest and examples

The decision digest is `sha256:` followed by the unpadded Base64url SHA-256 value of RFC 8785 canonical UTF-8 JSON. The canonical object has **exactly** `id`, `requesterName`, `actionType`, `text`, `sensitive`, `sessionID`, `createdAt`, and `expiresAt`. `sessionID` is JSON `null` when omitted. Timestamp strings are exactly those in the snapshot. `requestedExpirySeconds` is metadata; the digest commits to the effective deadline through `expiresAt`. The `requesterName` comes from authentication. The decider sends the digest from the displayed full snapshot, and the server compares it with the stored value before attempting a transition.

An ordinary create request, with a requester bearer sent only after a verified proof:

```http
POST /v1/requester/requests HTTP/1.1
Authorization: Bearer <requester-token>
Idempotency-Key: example-run-1
Content-Type: application/json

{"actionType":"run-command","text":"Run the test suite","sensitive":false}
```

An illustrative `201` snapshot (the digest matches the stated canonical fields):

```json
{"id":"550e8400-e29b-41d4-a716-446655440000","requesterName":"Build Agent","actionType":"run-command","text":"Run the test suite","sensitive":false,"requestedExpirySeconds":120,"createdAt":"2026-10-08T00:00:00Z","expiresAt":"2026-10-08T00:02:00Z","state":"pending","digest":"sha256:elaCJEQKavqDo4s2JkECjeMpE1GK_cAm13-k_OmNn0A"}
```

A request with `"sensitive":true` instead returns `422 application/problem+json` and creates no pending request:

```json
{"type":"urn:approvehub:problem:sensitive_request_not_supported","title":"Sensitive request not supported","status":422,"code":"sensitive_request_not_supported"}
```

## Event recovery

The pending list and its event cursor are captured at the same actor position. The GUI connects to `/v1/decider/events` with that cursor in `Last-Event-ID`, so changes after the list snapshot are replayed. Each SSE frame has an opaque `id`, `event: request.created` or `event: request.terminal`, and a `data` JSON full request snapshot. The stream is available only to a decider. An unknown or dropped cursor returns `409 event_cursor_unavailable`; the GUI refreshes the pending list and reconnects using the replacement cursor. After restart, the GUI likewise refreshes authoritative state. No requester SSE stream, persistent event history, or pagination is part of this release.

## Errors

Every error body is `application/problem+json` with RFC 9457 `type`, `title`, `status`, and stable `code`; `type` is `urn:approvehub:problem:<code>`. `detail` and `instance` are optional diagnostics. Clients branch on the HTTP status and code, never on prose.

| HTTP | Code | When |
|---:|---|---|
| 400 | `malformed_challenge` | Proof challenge encoding or decoded length invalid. |
| 400 | `malformed_input` | Invalid JSON, field, bounds, or request shape. |
| 400 | `missing_idempotency_key` | Create or submit-and-wait omits or invalidates the retry key. |
| 401 | `unauthenticated` | Missing, invalid, or revoked bearer credential. |
| 403 | `origin_rejected` | Any request carries `Origin`. |
| 403 | `wrong_role` | Credential lacks the operation's role. |
| 404 | `request_not_found` | ID absent, belongs to another requester, or was lost on restart. |
| 409 | `digest_mismatch` | Decision digest differs from stored immutable request. |
| 409 | `idempotency_key_reused` | Same key, changed create input. |
| 409 | `event_cursor_unavailable` | SSE replay position lost, unknown, or from a former process. |
| 422 | `sensitive_request_not_supported` | Sensitive request rejected before pending state. |
| 422 | `unsafe_request_text` | Submitted text rejected by M3 safety checks before persistence. |
| 429 | `pending_request_limit_reached` | Already 100 requests pending; `Retry-After` gives seconds. |

The contract's `RequestNotFound` response deliberately does not reveal cross-requester existence. The GUI and requesters treat identity proof failure as a separate local failure before bearer disclosure; it is not a server Problem Details response.

## Verification

Build the three plugin targets and compile contract tests against their generated declarations. `ruby Tests/ContractValidation/validate.rb` checks the ordinary and sensitive examples, digest encoding, problem code/status/type pairs, role and retry requirements, wait bounds, SSE framing, and replay-loss response. The [full validation gate](../contribution-guide.md#required-validation) passed on 2026-10-08, as did the contract checker. M5–M7 will add behavioral lifecycle and HTTP/SSE tests as their implementations arrive.
