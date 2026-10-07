# Research: hosting and packaging

Status: Active

Where the ApproveHub API server could run (inside the GUI app or as a separate background process), how a SwiftPM-only project becomes a macOS app, and what signing, sandbox and notarization require. Written for [P1-M1](archive/phases/phase-1/milestone-01-overview.md) topic 4. It lists options with evidence and decides nothing; P1-M2 decides.

Accepted by the owner on 2026-10-07 as the record of what was found. Where an owner decision in the [Phase 1 changelog](archive/phases/phase-1/changelog.md) conflicts with a recommendation here, the decision wins.

## Method

- **Sources:** Apple's documentation data and the local `launchd.plist(5)` man page, read on 2026-10-07, plus package facts from the [transport note](research-transport-and-server.md).
- **Experiments:** one throwaway SwiftPM executable in the session scratchpad, not in this repo, built with Swift 6.2.1 on macOS 26.7. It was run bare and then as an ad-hoc-signed `.app` bundle. Nothing was registered with the system, and no permission prompt was triggered.
- **Not tested on purpose:** registering a real launch agent, because that changes the owner's Login Items outside the scratchpad.
- **Marking:** `Unverified` marks a claim without a primary source or an experiment.

## Questions

1. Should the server run inside the GUI process, in a separate background process (launch agent or login item), or with the GUI as a pure client?
2. What happens to queued requests when the GUI is closed, and how does the GUI find and connect to the server?
3. How does a SwiftPM-only project produce an `.app`, and what needs a bundle, such as notifications?
4. What do sandbox entitlements, the hardened runtime, signing, notarization and distribution require for a listening server?
5. What minimum macOS version should ApproveHub support?

## Findings

### 1. The bundle is not optional

- **SwiftPM produces a bare executable.** Observed: `file` reports `Mach-O 64-bit executable arm64` for the scratch build, not an app bundle.
- **Notifications crash without a bundle.** Observed: the bare executable terminated on `UNUserNotificationCenter.current()` with `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil` and exit code 134.
- **A minimal bundle fixes that.** Observed: the same binary copied into `Spike.app/Contents/MacOS/`, with an `Info.plist` (`CFBundleIdentifier`, `CFBundleExecutable`, `CFBundlePackageType`, `LSUIElement`) and signed with `codesign --force --options runtime --sign -`, ran without error. `Bundle.main.bundleIdentifier` returned the identifier, `UNUserNotificationCenter` reported an authorization status with raw value 0, and `SMAppService.mainApp.status` and an agent with no plist both returned raw status 3. I did not read the enum case names in the pages fetched, so I read these as "not determined" and "not found", which fits a bundle that was never registered.
- **Consequence:** anything that touches user notifications or `SMAppService` needs the bundle, whichever hosting model is chosen. Producing the `.app` is a build step the repo does not have. Which tool does it (a project script, Xcode, or a third-party tool) is a build-tool choice that AGENTS.md says needs the owner's approval. A plain `swift run` of a bare executable is `Unverified` for a SwiftUI window and was not tried.

### 2. Hosting models

| | A. Server inside the GUI process | B. Separate background process, GUI as a client | C. B plus launchd socket activation |
|---|---|---|---|
| How it runs | The GUI app owns the listener | A helper in the app bundle registered with `SMAppService` as a launch agent. The agent plist lives in `Contents/Library/LaunchAgents` | As B, with launchd owning the listening socket and starting the server on the first connection |
| Requests while the GUI is closed | Refused. Nothing is listening | Queued. The server keeps running | Queued, and the server starts when needed |
| Matches "the GUI is one client of the API" | Only in spirit. The GUI and server share a process | Yes. Both are separate processes using the same API | Yes |
| Start at login | A login item (`SMAppService.mainApp`) | The agent can run at load | The socket is available from login, and the server starts on demand |
| Notifications | The GUI app posts them | `Unverified` which process posts them, since the helper is a separate executable in the same bundle | `Unverified`, same as B |
| Extra work | None beyond bundling | An agent plist, a helper target, and an approval step for the user | B plus the socket handoff (`launch_activate_socket`) |
| Menu-bar-only risk | A `MenuBarExtra`-only app is terminated if the user removes the extra from the menu bar, which would also stop the server | None | None |

What the sources say:

- **`SMAppService`** (macOS 13+) "control[s] helper executables that live inside an app's main bundle". The agent initializer needs a property list in the app's `Contents/Library/LaunchAgents`. The property list's `Program` key becomes `BundleProgram`, with a path relative to the bundle. Its `status` reports "registration or authorization state". [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [agent(plistName:)](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:)), [Updating helper executables](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- **launchd** supports `KeepAlive`, `RunAtLoad`, `ThrottleInterval` and `LimitLoadToSessionType`. Its `Sockets` key defines "launch on demand sockets": the job checks in with `launch_activate_socket(3)` to receive the file descriptors. Observed in the local man page, `launchd.plist(5)`.
- **A per-user agent matches the callers.** Apple describes a launch agent as providing auxiliary UI capabilities for the user, and a launch daemon as persistent background service. Requests come from the owner's own sessions, so a per-user agent is the natural scope. A system daemon was not researched further.
- **Hummingbird can listen on a Unix domain socket** as well as a host and port, per its `BindAddress` type at 2.27.0, so a socket path is a possible way for the GUI and agent to meet. [BindAddress.swift](https://github.com/hummingbird-project/hummingbird/blob/2.27.0/Sources/HummingbirdCore/Server/BindAddress.swift)

### 3. Queued requests and discovery

- **Queued requests:** under model A a request cannot be queued while the GUI is closed, because nothing is listening. The requesting app's agent then falls back to its own approval flow, as the [agent flow note](research-agent-approval-flows.md) found. Under B and C requests wait, which also means a persistence decision for P1-M2: what survives a restart of the server.
- **Finding the server, options only:** a fixed loopback port (a conflict is possible), a Unix socket path in a known directory, or a socket handed over by launchd. A well-known path avoids port collisions. The exposure choices for iOS and the LAN belong to [topic 5](research-security-and-exposure.md).

### 4. Signing, sandbox, notarization and distribution

- **App Sandbox:** required to distribute through the Mac App Store. Whether it is optional outside the store is not stated in the pages read, so that is `Unverified`. A sandboxed app that accepts connections needs `com.apple.security.network.server`. For TCP, the network entitlements restrict only who initiates a connection, not the flow of data. [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [network.server](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server)
- **Hardened Runtime:** required to upload a macOS app for notarization. Observed: ad-hoc signing with `--options runtime` produced a signature with flags `adhoc,runtime`. [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- **Notarization:** Apple's notary service checks Developer ID-signed software for malicious content and code-signing issues, using `notarytool`. It applies to Developer ID-signed software. Enrollment requirements and cost were not researched. [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- **Menu bar and agent apps:** `MenuBarExtra` is macOS 13+, and `LSUIElement` hides the Dock icon. [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- **Local use versus distribution:** an ad-hoc-signed bundle ran here. Whether Gatekeeper accepts such a build on another Mac, or after download, was not tested.

### 5. Minimum macOS version

Each row is a floor that some choice imposes. All values are from the sources above and the [transport note](research-transport-and-server.md).

| If ApproveHub uses | It needs at least |
|---|---|
| `UNUserNotificationCenter` | macOS 10.14 |
| `SMAppService` (agents, login items) and `MenuBarExtra` | macOS 13 |
| Hummingbird core | macOS 11 |
| `hummingbird-websocket` or `swift-openapi-hummingbird` | macOS 14 |
| swift-openapi-runtime with the URLSession client | macOS 10.15 (streaming bodies: macOS 12) |

The build host needs the Swift 6 toolchain from AGENTS.md, which is separate from the deployment target. Hosting model B or C needs macOS 13. Adding `swift-openapi-hummingbird` or `hummingbird-websocket` raises the floor to macOS 14.

## Options

- **A. Server inside the GUI app, with a login item.** Least moving parts. Requests are refused whenever the GUI is not running.
- **B. Server as a launch agent in the app bundle, GUI as a client.** Meets the owner's "the GUI is one client" decision literally, and keeps queueing independent of the GUI. Costs an agent plist, a helper target and a user approval step.
- **C. B with launchd socket activation.** Adds on-demand start and a stable socket, at the cost of the `launch_activate_socket` handoff in the server.
- **Out of scope:** a system-wide launch daemon, which was not researched.

## Recommendation

Optional and not a decision. B, because it satisfies the decided architecture directly and avoids the menu-bar termination risk, with C as a later refinement. Whichever is chosen, plan for the `.app` build step now, since notifications and `SMAppService` both need it.

## Open questions

- Which tool builds the `.app` from a SwiftPM package? This is a build-tool decision for the owner.
- Which process posts notifications under B and C? `Unverified`. It needs a launch-agent experiment, which would change the owner's Login Items, so it needs permission first.
- Is distribution limited to the owner's own Macs, or shared? That decides whether Developer ID signing and notarization are needed at all.
- Is the App Sandbox wanted? It is required only for the Mac App Store, and a sandboxed server needs the network server entitlement.
- What survives a server restart: pending requests, decided requests, an audit log? This overlaps with persistence in P1-M2.
- What minimum macOS version? The table gives the floors: macOS 13 for B or C, and macOS 14 if the OpenAPI server transport or the Hummingbird WebSocket package is added.

## Sources

All read on 2026-10-07.

- Apple, SMAppService: <https://developer.apple.com/documentation/servicemanagement/smappservice>
- Apple, SMAppService agent(plistName:): <https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:)>
- Apple, Updating helper executables from earlier versions of macOS: <https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos>
- Apple, UNUserNotificationCenter: <https://developer.apple.com/documentation/usernotifications/unusernotificationcenter>
- Apple, MenuBarExtra: <https://developer.apple.com/documentation/swiftui/menubarextra>
- Apple, LSUIElement: <https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement>
- Apple, App Sandbox: <https://developer.apple.com/documentation/security/app-sandbox>
- Apple, com.apple.security.network.server: <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server>
- Apple, Hardened Runtime: <https://developer.apple.com/documentation/security/hardened-runtime>
- Apple, Notarizing macOS software before distribution: <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
- `launchd.plist(5)`, the local man page on macOS 26.7.
- Hummingbird 2.27.0, `BindAddress.swift`: <https://github.com/hummingbird-project/hummingbird/blob/2.27.0/Sources/HummingbirdCore/Server/BindAddress.swift>
