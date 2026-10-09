# P1-M7: ApproveHub Service, technical approach

Status: Done

This milestone exposes the completed lifecycle and credential components through
the canonical HTTP contract. It adds no new public capability, dependency, or
trust decision: the service remains a fixed loopback-only process and requests
and event cursors remain process-local.

## Boundaries and startup

`ApproveHubService` contains a transport adapter that conforms to the
generated server `APIProtocol`; the generated declarations and
`Sources/openapi.yaml` remain authoritative. The `CredentialRuntime` actor
applies durable credential revisions before authorization, and the handler
coordinates it with `RequestLifecycle` and the event broker. It does not put HTTP
types, headers, or SSE frames in `ApproveHubCore`.

Before binding, startup will read and validate credential state, construct the
`ServiceProofSigner` and `RequestLifecycle`, acquire the M6 service lease,
and apply the current credential revision. It will subscribe the event broker
to lifecycle transitions before accepting traffic. It will then bind exactly
`127.0.0.1:46931`; it must not bind an uninitialized, corrupt, or
partially-recovered credential store. A bind failure, including an occupied
port, stops startup, releases the lease, and exposes no fallback listener.

Hummingbird 2.27.0 binds the application to the fixed host and port, and
startup errors surface from its async run method. The generated server protocol
is registered with the pinned OpenAPI-Hummingbird transport; the subprocess
test verifies its JSON, Problem Details, and `text/event-stream` responses.
Address reuse permits a prompt restart after `TIME_WAIT` while a live listener
still wins the port collision test. The stopped-service port probe uses the
same address-reuse setting and attempts `listen` before allowing rotation.

After binding, the credential runtime continuously observes durable revisions.
It applies a revocation by cancelling that requester's pending requests before
writing the service acknowledgement required by M6. Shutdown cancels the
observer, closes all event streams, and releases the lease. A restart creates
a fresh lifecycle and fresh event-cursor namespace, intentionally losing all
requests, outcomes, idempotency keys, and replay state.

## Request boundary and authorization

One transport-boundary check applies to every operation, including the proof
endpoint: any `Origin` header produces the specified `403 origin_rejected`
Problem Details response before decoding a body, signing a proof, or reading a
bearer token. JSON and header validation errors are converted to the stable
M4 problem codes and `application/problem+json`; unexpected errors are logged
without secrets and return a non-diagnostic server failure.

`POST /v1/identity/proofs` accepts only canonical, unpadded Base64url data that
decodes to 32 bytes, obtains the current signer after credential state is
known-good, and returns its exact proof. It never accepts a bearer token or
changes service state.

For all other operations, the adapter extracts exactly one Bearer token and
asks the runtime to apply any newer credential revision before authenticating.
The credential store supplies either an authenticated requester identity or a
decider authorization; wrong role, missing or malformed credentials, and
revoked credentials map to the M4 `wrong_role` or `unauthenticated` results.
The requester identity, never a client-supplied name or ID, becomes the
lifecycle identity. Requester routes may create, wait for, and cancel only
that identity's requests; only the decider routes may list, stream, or decide.

The runtime applies the current credential revision before each authorization,
and the handler rechecks requester authorization after an awaited result and
before writing a response. Thus a revocation that commits while a wait is in
flight yields cancellation or authentication failure, never a newly delivered
approval. A decision after the runtime has applied revocation observes the
cancelled state. This is the M6 cancellation-before-acknowledgement guarantee
at the HTTP boundary, not a new authorization rule.

## Contract mapping

The handler translates generated operation input and output values to the
typed lifecycle values without reimplementing lifecycle policy. It validates
the UUID path value, 1–128-character `Idempotency-Key`, and request payload
at the HTTP boundary; `RequestLifecycle` remains the authority for text
safety, expiry, capacity, idempotency semantics, ownership concealment,
digest comparison, and first-terminal-transition wins. Its typed errors map
one-to-one to the stable M4 problem table, including `Retry-After` for the
pending limit.

`submit-and-wait` retains its request task until the lifecycle returns a
terminal snapshot; a dropped client task only removes its waiter. Stepwise
wait remains 1–30 seconds. No service timeout may turn a pending snapshot
into permission to act. Every create, retry, wait, cancel, and decision response
uses the full immutable snapshot conversion, including exact timestamps and
digest spelling.

## Events and replay

The service event broker is the sole consumer of lifecycle transitions. It
assigns opaque, process-scoped cursor IDs and retains a bounded ring of 1,024
full-snapshot events. It records the cursor position corresponding to each
observed lifecycle revision, including the initial empty position. Event frames
are emitted in order as UTF-8 SSE with one `id`, either `request.created` or
`request.terminal`, and one JSON `RequestSnapshot` data field.

For a pending-list response, the adapter first obtains the lifecycle snapshot
and revision, then waits until the broker has observed that revision before it
returns the matching cursor. If the required position is no longer retained,
it repeats the snapshot rather than returning a cursor that could skip a
transition. This realizes M5's list-to-stream handoff rule: a client that
connects with the returned cursor receives every later retained event.

An event connection with no `Last-Event-ID` begins at the current position. A
known retained cursor replays later events in order and then stays subscribed.
An unknown, expired, or previous-process cursor returns `409
event_cursor_unavailable`; it never silently starts at the latest position.
If the lifecycle-to-broker stream reports a gap or the broker cannot preserve
continuity, the broker invalidates the affected cursor generation and closes
active streams. Reconnection then receives the same explicit replay-loss
response and the decider refreshes the authoritative list. Event streams carry
no requester credentials or requester-visible events.

## Implementation sequence and evidence

1. Add the generated-handler/transport integration spike and a test-only
   loopback harness. Prove generated request decoding, Problem Details
   encoding, a bounded SSE response, and exact fixed-address startup before
   adding endpoint behavior.
2. Build the service runtime, startup/shutdown ownership, Origin guard,
   credential refresh and role authorization. Exercise uninitialized state,
   corrupt state, occupied port, proof signing, and secret-free failures.
3. Map requester and decider operations to `RequestLifecycle`, including
   response conversion and every specified domain error. Add authenticated
   cross-process coverage for both wait patterns, ownership concealment,
   idempotency, decisions, cancellation, expiry, and decision/wait races.
4. Add the event broker and SSE endpoint. Test list-to-stream continuity,
   ordered replay, an empty-list cursor, buffer eviction, malformed or unknown
   cursors, stream disconnect, source-transition gap recovery, and service
   restart.
5. Exercise concurrent credential changes: token replacement, requester
   revocation during create, wait, and decision, pending cancellation before
   acknowledgement, and verified service shutdown when acknowledgement fails.
   Run the full validation gate, record evidence in the overview, and only
   then mark M7 Done.

## Completion evidence

`ServiceHTTPTests.fixedListenerServesProofRolesAndRequesterLifecycle` starts the
real service executable against isolated credential state and exercises the
fixed listener, generated JSON and SSE transport, proof verification, role and
ownership boundaries, both waits, cancellation, expiry, live revocation,
acknowledgement failure, port collision, and restart loss. The broker tests
exercise replay ordering, empty cursors, eviction, source gaps, and previous
process cursors. The full validation results are recorded in the
[overview](milestone-07-overview.md#completion-evidence).
