# Research: security and network exposure

Status: Active

How each kind of client could authenticate to the ApproveHub API, how far the API could be exposed (this Mac only, the local network, or beyond), and how approvals could resist spoofing and replay. Written for [P1-M1](archive/phases/phase-1/milestone-01-overview.md) topic 5. It lists threats, options and evidence, and decides nothing; P1-M2 decides.

Accepted by the owner on 2026-10-07 as the record of what was found. Where an owner decision in the [Phase 1 changelog](archive/phases/phase-1/changelog.md) conflicts with a recommendation here, the decision wins.

## Method

- **Sources:** vendor docs, Apple documentation data, the local `unix(4)` man page and IETF and MCP specifications, read on 2026-10-07 and listed under "Sources".
- **Experiment:** one throwaway Unix-socket server in the session scratchpad, not in this repo. It asked the OS who was on the other end of each connection. Nothing was registered with the system and no credential was touched.
- **Scope assumptions** (owner decisions of 2026-10-07, see [the milestone overview](archive/phases/phase-1/milestone-01-overview.md)): requesting apps are written only by the owner, one owner decides on their own devices, and remote access for iOS is researched both ways.
- **Not tested:** TLS and certificate pinning, Bonjour, device pairing, Keychain access rules against other apps, and anything that needs a launch agent or a phone.
- **Marking:** `Unverified` marks a claim without a primary source or an experiment. "Design reasoning" marks my own inference.

## Questions

1. How does each role authenticate: requesting apps, the Mac GUI and the iOS app?
2. Loopback only, or the local network with TLS and Bonjour? How does iOS pair, and what about access away from home?
3. How do spoofed or replayed approvals happen, and how can a decision be bound to the exact request content?
4. What about the audit log and secret storage?

## Findings

### 1. The trust boundary: the gated agent is the same user

The agent whose requests ApproveHub approves runs as the same macOS user as ApproveHub. The sources show what that means:

- **Hooks run as the user.** Claude Code: "Command hooks execute shell commands with your full user permissions." [Claude Code hooks](https://code.claude.com/docs/en/hooks.md)
- **A sandboxed agent command can read most of the machine by default.** Claude Code's sandbox defaults list reads as "Most of the machine, including credential files such as `~/.ssh` and `~/.aws/credentials`", and environment variables as "Inherited from Claude Code, including any secrets in its environment". Both are changeable with settings. [Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing.md)
- **Codex's sandbox modes also let the agent read files.** `read-only` lets it inspect files and `workspace-write` lets it read files and edit in the workspace. [Codex sandboxing](https://learn.chatgpt.com/docs/sandboxing.md)
- **The vendors call hooks a guardrail.** Codex: "Treat tool hooks as a useful guardrail, not a complete enforcement boundary." [Codex hooks](https://learn.chatgpt.com/docs/hooks.md)
- **The socket cannot tell the agent from the GUI by user (Observed).** A Unix-socket server on macOS 26.7 saw three different client binaries (`/usr/bin/curl`, a Python interpreter, `/usr/bin/nc`). `LOCAL_PEERCRED` reported the same uid, 501, for all of them, the same as the server. `LOCAL_PEERPID` plus `ps` identified each executable. The socket file was `srw-------` (mode 0600), which excludes other users and not the same user. `unix(4)` also limits `sun_path` to 104 characters, and the scratchpad's absolute path exceeded that, so a real socket location has to be short.

Consequences, as design reasoning:

- **A credential the requesting side can read, the agent can read too.** An API token in a file or an environment variable proves "something holding this token", not "the intended app and not the agent".
- **ApproveHub works as a consent mechanism and not as a boundary against a malicious same-user process.** It can reliably stop a cooperative but fallible agent, for example one steered by prompt injection, from acting without a person deciding. It cannot stop a process that already runs as the user and decides to edit settings or kill ApproveHub, which the [agent flow note](research-agent-approval-flows.md) already found for the hooks.
- **Deciding must need something an unprivileged same-user process cannot do alone.** That means separating the capabilities: requesters may create and read their own requests, and may never decide. The decide path then needs a user action, optionally with user presence.

### 2. Authentication per role

| Role | Options | Evidence and cost |
|---|---|---|
| **Requesting app** | A per-app random token in an `Authorization` header, with scope limited to creating, waiting on and cancelling its own requests | Claude Code `http` hooks send `headers` with `$VAR` interpolation limited to `allowedEnvVars`, and settings can restrict hook URLs and variables (`allowedHttpHookUrls`, `httpHookAllowedEnvVars`, which the settings reference lists as valid in any settings file). A Codex command shim can read a token from a file or the environment. Whether Claude Code's `http` hook can target a Unix socket is `Unverified`. The documented example is an `http://localhost` URL, so TCP loopback is assumed for that route |
| **Mac GUI** | In-process (no API credential), or a decider credential held in the Keychain with an access-control flag | Keychain access control can require `userPresence` (biometry or passcode) or `biometryCurrentSet`. Behavior against another same-user app was not tested |
| **iOS app** | A paired device key, a client certificate, or a bearer token | See section 4 |

Local transport adds its own rules:

- **A loopback or localhost HTTP server needs more than a token.** The MCP specification, which covers local servers that browsers might reach, says servers MUST validate the `Origin` header to prevent DNS rebinding, SHOULD bind only to localhost, and SHOULD authenticate every connection. The same attacks apply to an ApproveHub listener on loopback. [MCP transports, security warning](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
- **A Unix socket adds file-permission protection** at the cost of the 104-character path limit, and `curl --unix-socket` worked for a shell shim (Observed).
- **Sender-constrained tokens.** DPoP (RFC 9449) binds a token to a proof key, and its proofs carry a `jti` for replay detection and an `iat`. Mutual TLS (RFC 8705) binds tokens to a client certificate. Both make a stolen token less useful, at the cost of more machinery. [RFC 9449](https://www.rfc-editor.org/rfc/rfc9449.txt), [RFC 8705](https://www.rfc-editor.org/rfc/rfc8705.txt)

### 3. Exposure options

| Option | What it allows | Notes |
|---|---|---|
| **This Mac only** (Unix socket or loopback) | Requesting apps and the Mac GUI | Smallest attack surface. iOS cannot connect |
| **Local network** | Adds iOS at home | Needs TLS, discovery, pairing and the iOS permission described below |
| **Beyond the local network** | Adds iOS away from home | Options, none tested: a VPN or mesh the owner runs, a relay the owner runs, an Apple push route (see [topic 6](research-ios-client.md)). Forwarding a port to the internet exposes the approval API and is a poor fit. Each route is extra attack surface. An untrusted relay needs end-to-end protection between the phone and the Mac (design reasoning) |

Local-network facts from Apple:

- **Local network privacy** shows the user an alert the first time a program accesses the local network, and the system remembers the answer. It exists on iOS, and on macOS since the 2024 releases. Apps should provide `NSLocalNetworkUsageDescription`. [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [NSLocalNetworkUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)
- **App Transport Security:** since iOS 17 and macOS 14 it no longer allows connections to bare IP addresses by default. `NSAllowsLocalNetworking` covers unqualified and `.local` domains, and IP addresses need entries in `NSExceptionDomains`. A `.local` Bonjour name avoids the IP problem. [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- **Discovery:** `NWBrowser` browses for services on iOS 13+ and macOS 10.15+. [NWBrowser](https://developer.apple.com/documentation/network/nwbrowser)
- **Certificates:** a self-signed server certificate would need pinning or a trusted local authority on the phone. How the pinning is done in `URLSession` was not researched. The pairing step below could deliver the fingerprint (design reasoning).

### 4. Pairing the iOS app

Design options, from reasoning plus the cited primitives and not from a pairing standard:

- **P1. One-time code and a device key.** The Mac GUI shows a QR code carrying the server address, the server certificate fingerprint and a one-time secret. The phone then enrolls a public key generated in the Secure Enclave (P-256 signing via CryptoKit, iOS 13+). Later decisions are signed by that key and can require biometrics. A stolen token is not enough. [SecureEnclave.P256](https://developer.apple.com/documentation/cryptokit/secureenclave/p256), [LAPolicy biometrics](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics)
- **P2. A client certificate at pairing, with mutual TLS** (RFC 8705). Standard, but certificate handling on iOS is more work.
- **P3. A bearer token after entering a code.** Simplest, and a stolen token acts as the owner.

### 5. Spoofed and replayed approvals

| Threat | What it looks like | Mitigations seen in sources or reasoning |
|---|---|---|
| **Fake request** | A rogue local process submits a plausible request | Authenticate the requester and show its identity. Sanitize the displayed text: Claude Code's relay neutralizes direction-override and invisible characters, folds whitespace, truncates around a counted marker so the end of a long command stays visible, and masks recognizable credentials. A short code shown on both sides, like CIBA's `binding_message` or Duo's verification code, ties the request to what the approver sees |
| **Replayed decision** | An old approval is sent again | Unguessable single-use request ids, server-side expiry, and a nonce or `jti` plus timestamp on signed decisions (the DPoP pattern, RFC 9449 §11.1) |
| **Content swap** | The request changes between display and decision | Bind the decision to a digest of the request. RFC 8785 defines a canonical JSON form so the producer and the server compute the same hash, and a decision carries `{request_id, digest, outcome}` (design reasoning) |
| **Modified input** | An allow decision rewrites the tool input | Claude Code accepts `updatedInput` on allow and Codex rejects it today. Show any change to the approver, or leave it out of the first API |
| **Approver text steers the agent** | A deny message reaches the model | Observed in both agents that the message reaches the model. Treat it as a channel to the agent and keep it plain text |

References: [RFC 9449](https://www.rfc-editor.org/rfc/rfc9449.txt), [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785.txt), [CIBA](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html), [Duo Auth API](https://duo.com/docs/authapi), [Channels reference](https://code.claude.com/docs/en/channels-reference.md).

### 6. Audit log and secret storage

- **Audit log content (design reasoning):** a digest of the request, the requester identity, the decider and device, the outcome and timestamps, with the full text if the owner wants it.
- **A same-user log is not tamper-proof.** The agent runs as the same user and could delete or edit a file the user owns. A hash chain makes edits detectable and does not prevent them. Treat the log as accountability, not as protection against a hostile agent.
- **Secrets:** requester tokens are stored hashed on the server (design reasoning). Decider credentials belong in the Keychain with an access-control flag. Apple's flags include `userPresence` (biometry or passcode) and `biometryCurrentSet`, which invalidates the item when enrolled fingers change. [SecAccessControlCreateFlags](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags)
- **Keep secrets out of display and logs.** Claude Code's relay masks recognizable provider tokens before relaying a prompt, and does not mask a secret without a recognizable prefix, so ApproveHub should do its own masking and not depend on the agent's.

## Options

- **S1. This Mac only.** A Unix socket or loopback with token authentication, no TLS, and no iOS in the first release. Smallest surface.
- **S2. Add the local network.** TLS with a pinned certificate, a Bonjour name, iOS pairing with a device key (P1), and the local network permission.
- **S3. Add remote access.** S2 plus a relay, a VPN or a push route chosen in topic 6, with end-to-end protection if the relay is untrusted.

Whatever is chosen, these hold in all three (design reasoning):

- Requesters and deciders hold different capabilities.
- Decisions are bound to a digest of the request.
- Requests expire and are single-use.
- Displayed text is sanitized.

## Recommendation

Optional and not a decision. Design for S2 and ship S1 first if the schedule needs a smaller first release, so the API does not assume loopback. Make "requesters cannot decide" and "decisions carry a digest" part of the first API.

## Open questions

- **What is the threat model?** Is ApproveHub a consent tool for cooperative agents, or a boundary against a malicious same-user process? The first needs far less machinery. This is the owner's decision.
- **Can a same-user process drive the GUI** (for example through Accessibility automation) to approve its own request? `Unverified`, not tested. It decides whether a click is enough or approvals on the Mac need Touch ID.
- **Should approvals on the Mac require user presence?** A click, a biometric or a passcode.
- **How does a Claude Code `http` hook reach a Unix socket, if at all?** `Unverified`. If it cannot, TCP loopback or a command shim is needed for that route.
- **Where does the requester's token live?** Environment variables are inherited by the agent's own commands, and files are readable by default. Whether to deny the agent read access to it is a setting the owner would apply per agent.
- **Which remote route**, if any, and who operates it?
- **Which audit data is kept**, and for how long?

## Sources

All read on 2026-10-07.

- Claude Code hooks reference: <https://code.claude.com/docs/en/hooks.md>
- Claude Code sandboxing: <https://code.claude.com/docs/en/sandboxing.md>
- Claude Code channels reference: <https://code.claude.com/docs/en/channels-reference.md>
- Codex hooks: <https://learn.chatgpt.com/docs/hooks.md>
- Codex sandboxing: <https://learn.chatgpt.com/docs/sandboxing.md>
- Model Context Protocol, transports (2025-06-18): <https://modelcontextprotocol.io/specification/2025-06-18/basic/transports>
- RFC 9449, OAuth 2.0 Demonstrating Proof of Possession (DPoP): <https://www.rfc-editor.org/rfc/rfc9449.txt>
- RFC 8705, OAuth 2.0 Mutual-TLS Client Authentication and Certificate-Bound Access Tokens: <https://www.rfc-editor.org/rfc/rfc8705.txt>
- RFC 8785, JSON Canonicalization Scheme: <https://www.rfc-editor.org/rfc/rfc8785.txt>
- OpenID CIBA Core 1.0: <https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html>
- Duo Auth API: <https://duo.com/docs/authapi>
- Apple, TN3179 Understanding local network privacy: <https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy>
- Apple, NSLocalNetworkUsageDescription: <https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription>
- Apple, NSAllowsLocalNetworking: <https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking>
- Apple, NWBrowser: <https://developer.apple.com/documentation/network/nwbrowser>
- Apple, SecureEnclave.P256: <https://developer.apple.com/documentation/cryptokit/secureenclave/p256>
- Apple, LAPolicy.deviceOwnerAuthenticationWithBiometrics: <https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics>
- Apple, SecAccessControlCreateFlags: <https://developer.apple.com/documentation/security/secaccesscontrolcreateflags>
- `unix(4)`, the local man page on macOS 26.7.
