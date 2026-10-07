# Research: request and decision interaction

Status: Active

How a requesting app submits an approval request to ApproveHub and gets the decision back, and what the request and the decision must carry. Written for [P1-M1](archive/phases/phase-1/milestone-01-overview.md) topic 2, building on [the agent flow findings](research-agent-approval-flows.md). It lists requirements and options for the API; it does not define endpoints, which is a later milestone.

Accepted by the owner on 2026-10-07 as the record of what was found. Where an owner decision in the [Phase 1 changelog](archive/phases/phase-1/changelog.md) conflicts with a recommendation here, the decision wins.

## Method

- **Sources:** the specifications and vendor docs listed under "Sources", read on 2026-10-07 from their raw text. Where this note says "agent hooks", it relies on the experiments recorded in the [agent flow note](research-agent-approval-flows.md).
- **Prior art:** OAuth CIBA and the device flow are the closest standard patterns, and Duo's Auth API is a shipped push-approval service. All three approve a login, not an agent action, so they are analogies for the interaction shape and not for the payload.
- **Experiments:** none for this topic.
- **Marking:** `Unverified` marks a claim without a primary source or experiment.

## Questions

1. What does a request carry?
2. What outcomes can a decision have?
3. How does a requesting app that must block get the decision: long-poll, polling, streaming or webhook?
4. How do retries, idempotency and expiry work?
5. What happens when several deciding clients see the same request?
6. What does prior art such as OAuth CIBA and push-approval services show?

## Findings

### 1. What a request carries

From the agent flows already observed, a requesting app can supply these for an agent action:

| Field | Source in the agent flow |
|---|---|
| Agent kind, session id | Hook input (`session_id`) in both agents |
| Tool name and tool input | `tool_name`, `tool_input` in both agents |
| Human-readable description | `tool_input.description` in both agents. Codex says not to rely on it for every tool |
| Working directory and mode | `cwd`, `permission_mode` |
| Structured action detail | Codex app-server adds `commandActions`, `networkApprovalContext`, `availableDecisions` |

Prior art adds fields that no agent supplies by itself:

- **A message that interlocks the two devices.** CIBA's `binding_message` is "a human-readable identifier or message intended to be displayed on both the consumption device and the authentication device to interlock them together for the transaction". Duo's Verified Push has a verification code that expires 60 seconds after issuance. [CIBA §7.1](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html), [Duo Auth API](https://duo.com/docs/authapi)
- **A requested lifetime.** CIBA's `requested_expiry` lets the client ask for the lifetime of the request, and the server MAY adjust it. [CIBA §7.1](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html)
- **A structured description of the action.** OAuth Rich Authorization Requests define an `authorization_details` array whose objects have a REQUIRED `type` that determines the allowed contents, plus conventional fields such as `actions` and `locations`. It is a standard shape for "what is being approved". [RFC 9396](https://www.rfc-editor.org/rfc/rfc9396.txt)
- **An unguessable identifier.** CIBA requires the request id (`auth_req_id`) to carry at least 128 bits of entropy, with 160 recommended. [CIBA §7.3](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html)

Display safety matters because a human decides from this text. Claude Code's channel relay, which sends approval prompts to a remote chat, neutralizes direction-override and invisible characters, folds whitespace, truncates around a counted marker so the end of a long command still reaches the approver, and masks recognizable credentials. [Channels reference](https://code.claude.com/docs/en/channels-reference.md)

### 2. Outcomes

- **Standard error and result vocabularies:**
  - CIBA: `authorization_pending`, `slow_down`, `expired_token`, `access_denied`. [CIBA §11](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html)
  - Duo: `allow`, `deny` and `waiting`, with a `timeout` status after 60 seconds. [Duo Auth API](https://duo.com/docs/authapi)
- **Agents accept only allow or deny, with a message for deny.** Claude Code's `PermissionRequest` hook and Codex's both return `allow` or `deny`, and the deny `message` reaches the model (Observed in both). Claude Code additionally accepts `updatedInput` and permission updates. Codex reserves those fields and fails closed if used.
- **A request can end without a person deciding.** The agent can answer first or give up:
  - Claude's channel relay applies whichever answer arrives first and drops the other.
  - Codex's app-server sends `serverRequest/resolved` when a request was "answered or cleared".
  - Both agents give up on a hook at its timeout: Codex killed the hook process (Observed), and Claude Code documents that it cancels the hook. After that the requester is gone.
- **Implied states:** `pending`, `approved`, `denied`, `expired` (nobody decided in time) and `cancelled` (the requester withdrew or disappeared). The agent maps the last two to its own fallback.

### 3. How a blocking requester gets the decision

| Pattern | Standard source | Fit for a hook shim | Fit for a host app |
|---|---|---|---|
| **Hold the submit request open** until a decision | Duo's synchronous `/auth` returns only when authentication completes | Works. Claude Code's `http` hook waited 5 s in an experiment, and both agents default to a 600 s hook timeout | Works |
| **Submit, then long-poll** | Duo's `/auth_status` long-polls for the next status update. CIBA allows it and recommends 30 s | Works. A command shim can loop | Works |
| **Submit, then poll on an interval** | CIBA poll mode and RFC 8628 use an `interval` and `slow_down` | Works but adds latency and load | Works |
| **Stream events** | Server-Sent Events: `Last-Event-ID` resumes, and 204 stops reconnecting | Heavy for a short-lived hook script | Fits a long-lived host, and fits deciding clients that must update live |
| **Webhook callback** | CIBA ping and push modes require the client to register a callback URI | Poor. A hook process is short-lived and cannot receive callbacks | Possible but adds a server to every requester |

Details that constrain the first three:

- **Hold times.** CIBA recommends 30 s long-poll timeouts and says clients should be ready to wait at least 30 s, citing RFC 6202 §5.5. RFC 6202 notes that intermediaries may buffer partial responses and that long-poll timeouts need handling (§5.5, §5.6). On loopback there are no intermediaries, but over a LAN or relay for the iOS client the same concerns apply. [CIBA §10](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html), [RFC 6202](https://www.rfc-editor.org/rfc/rfc6202.txt)
- **No overlapping polls.** A CIBA client MUST NOT send two overlapping requests with the same request id, and a server under load may answer 503 with `Retry-After`. [CIBA §10](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html)
- **Backoff and stopping.** RFC 8628: on any error other than `authorization_pending` or `slow_down`, the client MUST stop polling. On a connection timeout it MUST reduce its polling frequency, and exponential backoff is RECOMMENDED. [RFC 8628 §3.5](https://www.rfc-editor.org/rfc/rfc8628.txt)
- **Agent deadlines are the outer bound.** A held-open request cannot outlast the agent's hook timeout (default 600 s in both agents). After that the agent has already moved on, so ApproveHub must not keep asking a person to approve it.

### 4. Retries, idempotency and expiry

- **Duplicate submits.** If a requesting app's submit times out, it cannot know whether the request exists. The IETF Idempotency-Key draft addresses this with a client-generated unique key, optionally combined with a fingerprint of the payload. It is a draft, not an RFC. Draft 07 (October 2025) states it expires on 18 April 2026, and I did not confirm a newer revision. [draft-ietf-httpapi-idempotency-key-header-07](https://www.ietf.org/archive/id/draft-ietf-httpapi-idempotency-key-header-07.txt)
- **Naturally idempotent alternative.** `Unverified` as a recommendation: letting the requester choose the request id makes a retried create return the same request. That is design reasoning, not a source finding.
- **Server-side expiry.** CIBA requires `expires_in` on every acknowledged request and an `expired_token` error afterwards, and tells clients to clean up requests whose callbacks never arrive. Duo's push times out after 60 s. [CIBA §7.3, §7.4](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html)
- **Requester disappearance.** A timed-out hook is killed (Observed for Codex) or cancelled (documented for Claude Code). Nothing tells ApproveHub, so a request can stay pending for a person who is now approving something nobody is waiting for. A short server-side expiry, an explicit cancel call, and a visible "requester gone" signal would address this. These are options, not findings.

### 5. Several deciding clients

- **Existing behavior to match.** Claude Code's channel relay lets the terminal and a remote channel both answer, applies whichever arrives first and drops the other. With several Codex hooks, any `deny` wins, otherwise an `allow` proceeds. [Channels reference](https://code.claude.com/docs/en/channels-reference.md), [Codex hooks](https://learn.chatgpt.com/docs/hooks.md)
- **Scope here.** The owner decided on 2026-10-07 that one person decides, on their own devices ([changelog](archive/phases/phase-1/changelog.md)). That makes "first decision wins" sufficient and rules out quorum or roles.
- **What the API must still do:** answer a late decision with the current state (already decided, expired, or cancelled) instead of silently overwriting, and tell every other deciding client that the request is resolved so its UI updates.

### 6. Prior art summary

| Property | CIBA | Device flow (RFC 8628) | Duo Auth API |
|---|---|---|---|
| Who asks, who approves | A client asks, a user approves on a separate device | A device asks, a user approves in a browser | An application asks, a user approves on a phone |
| Id and lifetime | `auth_req_id` (at least 128 bits), `expires_in` | `device_code`, `expires_in` | `txid`, push timeout 60 s |
| Delivery | poll, ping or push | poll | synchronous, or async with long-poll |
| Pending signal | `authorization_pending`, `slow_down` | same | `waiting` |
| Terminal states | `access_denied`, `expired_token` | same | `allow`, `deny` (with `timeout` status) |

## Options

For how a requesting app gets the decision:

- **A. One held-open request, with a deadline.** The requester submits and waits for the answer on the same connection. Simplest for a hook shim. Weak over networks with intermediaries, and a lost connection leaves an unknown state.
- **B. Create, then wait-with-deadline.** Submit returns the request id at once. The requester then calls a wait operation that returns on a decision or after a bounded time (about 30 s is the CIBA convention) and repeats. Survives dropped connections, and any requester can implement it, including a shell script.
- **C. B plus a stream for long-lived clients.** The same API also offers an event stream (SSE-style, resumable) for deciding clients and for host apps. The stream is a convenience on top of B and not a separate model.
- **D. Callbacks.** Possible later for always-on requesting apps, but a poor fit for hook shims, so not a starting point.

## Recommendation

Optional and not a decision. B for requesting apps, with a held-open submit as a convenience only if loopback-only use is confirmed. C for deciding clients. Whatever is chosen, the API needs:

- **Identity:** an unguessable server-assigned request id.
- **Retries:** client-supplied idempotency.
- **Lifetime:** a server-side expiry and an explicit cancel, both bounded by the requester's own deadline.
- **Outcomes:** `approved`, `denied`, `expired` and `cancelled`, with an optional message back to the requester.
- **Late decisions:** a conflict answer showing the current state.
- **Display safety:** sanitized display text, and a short code both sides can show.

The binding of a decision to the exact request content belongs to [topic 5](research-security-and-exposure.md).

## Open questions

- Which delivery pattern or patterns must the first version support, given hook shims and host apps both exist (see the [agent flow note](research-agent-approval-flows.md))?
- What is the longest time ApproveHub should hold a request open, and what is the default expiry? Both agents allow up to 600 s, which is long for a person to be reachable.
- Should an approval be able to change the request (`updatedInput`)? Claude Code accepts it and Codex rejects it today, so a portable API either omits it or makes it optional per agent.
- Should "approve for the rest of the session" style grants exist (`acceptForSession` in Codex, permission updates in Claude Code), or is every request decided alone?
- How is a message from the approver, which reaches the agent's model, kept from becoming an instruction channel? This overlaps with topic 5.
- Idempotency: a client-chosen id, the Idempotency-Key header, or both? The header draft's status is unconfirmed.

## Sources

All read on 2026-10-07.

- OpenID Connect Client-Initiated Backchannel Authentication Core 1.0: <https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html>
- RFC 8628, OAuth 2.0 Device Authorization Grant: <https://www.rfc-editor.org/rfc/rfc8628.txt>
- RFC 9396, OAuth 2.0 Rich Authorization Requests: <https://www.rfc-editor.org/rfc/rfc9396.txt>
- RFC 6202, Known Issues and Best Practices for Long Polling and Streaming in Bidirectional HTTP: <https://www.rfc-editor.org/rfc/rfc6202.txt>
- WHATWG HTML Standard, Server-sent events: <https://html.spec.whatwg.org/multipage/server-sent-events.html>
- IETF draft, The Idempotency-Key HTTP Header Field, draft 07: <https://www.ietf.org/archive/id/draft-ietf-httpapi-idempotency-key-header-07.txt>
- Duo Auth API: <https://duo.com/docs/authapi>
- Claude Code channels reference: <https://code.claude.com/docs/en/channels-reference.md>
- Codex hooks: <https://learn.chatgpt.com/docs/hooks.md>
