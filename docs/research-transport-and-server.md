# Research: transport and server technology

Status: Active

Which wire protocol and which Swift server stack could carry the ApproveHub API between requesting apps, the Mac GUI and an iOS app. Written for [P1-M1](archive/phases/phase-1/milestone-01-overview.md) topic 3. It lists options with evidence; it adds no dependency to the repo, and any dependency needs the owner's approval in P1-M2.

Accepted by the owner on 2026-10-07 as the record of what was found. Where an owner decision in the [Phase 1 changelog](archive/phases/phase-1/changelog.md) conflicts with a recommendation here, the decision wins.

## Method

- **Package facts:** read from the GitHub API on 2026-10-07: licenses, latest releases and push dates, and each `Package.swift` on `main` and at the cited release tag. The environment's Swift toolchain is 6.2.1.
- **API facts:** Context7 documentation for Hummingbird, Hummingbird WebSocket, Swift OpenAPI Generator and gRPC Swift 2, plus Apple's documentation data for the Apple APIs cited.
- **Spike:** one throwaway Hummingbird server in the session scratchpad, not in this repo. It checks the two interaction patterns from [topic 2](research-request-decision-interaction.md): a request held open, and Server-Sent Events. The only measured results are the ones marked "Observed".
- **Marking:** `Unverified` marks a claim without a source or an experiment.

## Questions

1. Which wire protocol fits: HTTP/JSON with SSE or WebSocket, gRPC, or something else?
2. Which Swift server options exist, such as SwiftNIO, Hummingbird, Vapor and Network.framework?
3. How would OpenAPI and client generation work for Swift, and can API types be shared between macOS and iOS?
4. How do the options fit Apache-2.0, how are they maintained, and how do they handle Swift 6 concurrency?

## Findings

### 1. What the callers constrain

These come from the earlier notes and bound the protocol choice before any framework comparison:

- **Codex hooks run a command or an MCP tool, not an HTTP call.** A hook shim therefore shells out to something that can reach the API. `curl` is enough for HTTP/JSON. gRPC would need a dedicated client binary. [Codex hooks](https://learn.chatgpt.com/docs/hooks.md)
- **Claude Code's `http` hook posts its own JSON and expects its own output schema back.** The response body "uses the same JSON output format as command hooks". An endpoint can be a direct hook target only if it speaks the agent's schema, so a generic API needs either an agent-specific route or a command shim that translates. [Claude Code hooks](https://code.claude.com/docs/en/hooks.md)
- **The server must hold a request open or stream.** Topic 2 found that both agents wait for a hook, and that deciding clients need live updates.
- **iOS is a client only.** It needs a streaming read and a way to send a decision.

### 2. Protocol options

| | HTTP/JSON, resumable event stream (SSE) | HTTP/JSON, WebSocket | gRPC |
|---|---|---|---|
| Reachable from `curl` or a shell hook shim | Yes | No, needs a WebSocket client | No, needs a gRPC client |
| Server push to the GUI and iOS | One-way stream. The standard `Last-Event-ID` header lets a client resume | Two-way. No resume mechanism in the protocol | Server and bidirectional streaming |
| Held-open request for a blocking requester | Yes. Observed in the spike | Not the natural fit | Unary RPC with a deadline |
| Swift client on iOS | `URLSession` async bytes, iOS 15 and later, macOS 12 and later. Reconnecting is the app's job | `URLSessionWebSocketTask`, iOS 13 and later, macOS 10.15 and later | gRPC Swift 2 needs macOS 15 and iOS 18 as the minimum deployment versions |
| Code generation | OpenAPI. The runtime has Server-Sent Events, JSON Lines and JSON Sequence helpers | Not covered by OpenAPI | Protobuf service definitions |

Sources: [WHATWG SSE](https://html.spec.whatwg.org/multipage/server-sent-events.html), [URLSession.AsyncBytes](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes), [URLSessionWebSocketTask](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask), [gRPC Swift 2 compatibility](https://github.com/grpc/grpc-swift-2/blob/main/Sources/GRPCCore/Documentation.docc/Articles/Compatibility.md).

Reading this against section 1: gRPC fails the shell-shim constraint and needs the newest OS releases on both clients, and WebSocket fails the shell-shim constraint. HTTP/JSON with a resumable event stream is the only column that meets every caller constraint.

### 3. Swift server options

All facts below are from the manifests and releases listed in "Method". The tools version is the `swift-tools-version` of the cited tag.

| Option | License | Latest release | Tools version and minimum platforms | WebSocket | TLS |
|---|---|---|---|---|---|
| **Hummingbird** | Apache-2.0 | 2.27.0, 2026-09-21 | 6.2. macOS 11, iOS 15 for the core package | Separate `hummingbird-websocket` 2.8.0 (Apache-2.0), macOS 14 and iOS 17 | `HummingbirdTLS` and `HummingbirdHTTP2` products, built on swift-nio-ssl and swift-nio-http2 (both Apache-2.0) |
| **Vapor 4** | MIT | 4.122.2, 2026-09-17 | 6.0. macOS 10.15, iOS 13 | `Unverified`, not read | `Unverified`, not read |
| **Vapor 5** | MIT | 5.0.0-beta.3, 2026-10-01 | The beta.3 tag needs tools 6.4 and macOS and iOS 26.2. Newer than the installed toolchain | `Unverified` | `Unverified` |
| **FlyingFox** | MIT | 0.27.1, 2026-07-16 | 6.0, with `swiftLanguageMode(.v6)` set. macOS 10.15, iOS 13 | Documented in its README | Not mentioned in its README (`Unverified` whether it supports it) |
| **SwiftNIO alone** | Apache-2.0 | 2.104.0, 2026-10-06 | 6.1 | `NIOWebSocket` library in the same package | Via swift-nio-ssl |
| **Network.framework** (`NWListener`) | Apple SDK | n/a | macOS 10.15 and iOS 13 for the WebSocket protocol | `NWProtocolWebSocket` | Built in (`Unverified` here, not read) |

Notes:

- **Vapor 5 is not usable today.** Its latest tag, beta.3, needs a newer toolchain than the installed Swift 6.2.1, and it is a beta. Vapor 4 has a compatible manifest (tools 6.0) but was not spiked.
- **SwiftNIO alone and Network.framework mean writing the HTTP layer.** I found no HTTP server API in Network.framework, which is `Unverified`. That is the cost of a zero-framework design, and it needs a strong reason.
- **FlyingFox** is small (687 GitHub stars) and runs on iOS. I did not check its maintainer count. TLS support is the open gap, and that matters if the LAN or iOS path needs it ([topic 5](research-security-and-exposure.md)).
- **Vapor** is a full-stack framework (`Unverified` here beyond the manifest). Most of it would go unused for this API.

### 4. OpenAPI and client generation

- **Generator:** Swift OpenAPI Generator 1.14.0 (Apache-2.0, tools 6.2) generates Swift client and server code from an OpenAPI document. It runs as a SwiftPM plugin, so adopting it adds a build tool, which AGENTS.md says needs approval. [swift-openapi-generator](https://github.com/apple/swift-openapi-generator)
- **Streaming and events:** its runtime 1.13.0 (Apache-2.0, macOS 10.15 and iOS 13) supports streaming bodies, and the runtime source includes `ServerSentEvents`, `JSONLines` and `JSONSequence` encoders and decoders. Streaming bodies work in the URLSession client transport only on macOS 12+ and iOS 15+. [swift-openapi-runtime](https://github.com/apple/swift-openapi-runtime), [swift-openapi-urlsession](https://github.com/apple/swift-openapi-urlsession)
- **Server transport for Hummingbird:** `swift-openapi-hummingbird` 2.1.0 (Apache-2.0) declares macOS 14 and iOS 17 as platforms. A Vapor server transport exists in the same ecosystem (`Unverified`, not checked).
- **Sharing types:** the generator can emit a types-only module that both a server and a client link against, which is how API types would be shared between macOS and an iOS client. That follows from its client, server and middleware split, and was not tried here.

### 5. Spike results (Observed)

A throwaway Hummingbird 2.27.0 server in the scratchpad, built with the installed Swift 6.2.1, `-c release`:

- **Build:** 61 s cold, with 23 transitive packages resolved and a 19.6 MB arm64 binary.
- **Held-open request:** a request that sleeps 5 s on the server returned after 5.09 s, with `200` and a JSON body.
- **Event stream:** three events written one second apart arrived about one second apart on a `curl -N` client, so the response is not buffered.
- **Client disconnect:** a `curl` that gave up after 2 s on a 6 s wait exited on time and the server stayed up. Whether the server's handler task is cancelled on disconnect was not measured.

### 6. License, maintenance and Swift 6

- **Licenses:** Hummingbird, SwiftNIO, swift-nio-ssl, swift-nio-http2, the OpenAPI packages and gRPC Swift 2 are Apache-2.0. Vapor and FlyingFox are MIT. MIT is a permissive license, but AGENTS.md requires the owner to approve any dependency, so confirm there.
- **Maintenance:** every repository above had a push within the six weeks before 2026-10-07. The oldest was gRPC Swift 2, on 2026-09-01, 36 days earlier. FlyingFox's latest release is older, 2026-07-16. None is archived.
- **Swift 6 concurrency:** manifests for FlyingFox and gRPC Swift 2 set `.swiftLanguageMode(.v6)` explicitly, and the Hummingbird and OpenAPI manifests use tools 6.1 or 6.2, where Swift 6 mode is the default. The Hummingbird spike compiled in that mode with no errors. I did not audit the libraries' concurrency annotations beyond that.

## Options

- **A. HTTP/JSON described by OpenAPI, with an SSE stream for live updates.**
  - Server: Hummingbird. Clients: OpenAPI-generated Swift clients over URLSession for the Mac GUI and iOS. Shell shims: `curl`.
  - Pro: meets every caller constraint, and the spike confirms the two interaction patterns.
  - Con: adds Hummingbird, swift-nio and the OpenAPI plugin and runtime, which is 23 transitive packages at the server alone.
- **B. A, but with WebSocket instead of SSE.**
  - Pro: two-way messages on one connection.
  - Con: needs a WebSocket client in shims, has no standard resume, and is not covered by OpenAPI.
- **C. gRPC.**
  - Pro: strongly typed streaming.
  - Con: not reachable from a shell hook shim, and needs macOS 15 and iOS 18 minimum.
- **D. A hand-built HTTP layer on Network.framework or SwiftNIO.**
  - Pro: fewer or no third-party packages.
  - Con: the HTTP parsing, routing, streaming and TLS handling become project code.
- **Server choice inside A:** Hummingbird is the only candidate here that was both current, built on the installed toolchain and spiked. Vapor 4 and FlyingFox are viable alternatives that were not spiked.

## Recommendation

Optional and not a decision. A, with Hummingbird, subject to the owner approving each new dependency and the OpenAPI build plugin. C and D are the options I would drop first, on the evidence above.

## Open questions

- Does the owner accept the dependencies and the build plugin that A needs? The server alone resolves 23 transitive packages.
- What minimum macOS and iOS versions will ApproveHub support? Hummingbird's core runs on macOS 11 but its WebSocket and OpenAPI-server packages need macOS 14 and iOS 17, and the choice interacts with [topic 4](research-hosting-and-packaging.md).
- Does the GUI talk to the server over HTTP like every other client, or in-process? Topic 4 covers the hosting model.
- Should TLS terminate in the server itself? If so FlyingFox needs a TLS check, and Hummingbird's `HummingbirdTLS` is the documented route. [Topic 5](research-security-and-exposure.md) decides the exposure.
- Is a Claude-specific `http` hook route worth providing, or is a command shim for both agents enough?
- Untested here: Vapor 4, FlyingFox, handler cancellation on client disconnect, and SSE reconnection from an iOS client.

## Sources

All read on 2026-10-07.

- Hummingbird: <https://github.com/hummingbird-project/hummingbird> (2.27.0), <https://github.com/hummingbird-project/hummingbird-websocket>, <https://github.com/hummingbird-project/swift-openapi-hummingbird>
- Vapor: <https://github.com/vapor/vapor> (4.122.2 and 5.0.0-beta.3)
- FlyingFox: <https://github.com/swhitty/FlyingFox>
- SwiftNIO: <https://github.com/apple/swift-nio>, <https://github.com/apple/swift-nio-ssl>, <https://github.com/apple/swift-nio-http2>
- Swift OpenAPI: <https://github.com/apple/swift-openapi-generator>, <https://github.com/apple/swift-openapi-runtime>, <https://github.com/apple/swift-openapi-urlsession>
- gRPC Swift 2: <https://github.com/grpc/grpc-swift-2>
- Apple documentation: <https://developer.apple.com/documentation/network/nwprotocolwebsocket>, <https://developer.apple.com/documentation/foundation/urlsessionwebsockettask>, <https://developer.apple.com/documentation/foundation/urlsession/asyncbytes>
- WHATWG Server-sent events: <https://html.spec.whatwg.org/multipage/server-sent-events.html>
- Claude Code hooks: <https://code.claude.com/docs/en/hooks.md>
- Codex hooks: <https://learn.chatgpt.com/docs/hooks.md>
