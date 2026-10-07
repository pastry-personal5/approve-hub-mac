# Research: iOS client constraints

Status: Active

What iOS allows and limits for an approval client (push delivery, background execution, the local network permission and discovery), and what the ApproveHub API would need to offer so an iOS app can work within them. Written for [P1-M1](archive/phases/phase-1/milestone-01-overview.md) topic 6. It is a survey only: Phase 1 builds no iOS app, and nothing here is tested on a phone.

Accepted by the owner on 2026-10-07 as the record of what was found. Where an owner decision in the [Phase 1 changelog](archive/phases/phase-1/changelog.md) conflicts with a recommendation here, the decision wins.

## Method

- **Sources:** Apple's documentation data, read on 2026-10-07 and listed under "Sources", plus the earlier research notes for the agent side.
- **Experiments:** none. No iOS device or simulator was used.
- **Scope assumptions** (owner decisions of 2026-10-07, see [the milestone overview](archive/phases/phase-1/milestone-01-overview.md)): the iOS app is a client that lives outside this repo, one owner decides on their own devices, and remote access is researched both ways.
- **Marking:** `Unverified` marks a claim without a primary source. "Design reasoning" marks my own inference.

## Questions

1. How does push delivery work, and what does it need?
2. What can an iOS app do in the background?
3. What does the local network permission and discovery add (see also [topic 5](research-security-and-exposure.md))?
4. What must the API offer so an iOS client can work within these limits?

## Findings

### 1. Push delivery (APNs)

- **A provider server is required.** Remote notifications start at "your company's server", the provider server, which forwards requests to APNs over HTTP/2 and TLS, using either token-based or certificate-based trust. Apps register device tokens with that server. For ApproveHub, the provider server is whatever relay the owner runs. [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
- **Delivery is best effort.** APNs "may reorder notifications you send to the same device token". If it cannot deliver immediately it may store the notification for 30 days or less, depending on the `apns-expiration` header. It stores only one notification per bundle ID, usually the latest, and may coalesce notifications. [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- **Payloads are small.** The JSON payload is limited to 4 KB (4096 bytes) for ordinary notifications. [Generating a remote notification](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification)
- **A service extension can transform a visible notification before display.** For example it can decrypt data sent in an encrypted format. It only runs for notifications that show an alert. [Modifying content in newly delivered notifications](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)
- **What a provider server needs from Apple** (a paid developer program, a key or certificate) was not checked in the pages read, so it is `Unverified` here.

### 2. Background execution

- **Silent pushes are unreliable.** Background notifications "[are] low priority", "the system doesn't guarantee their delivery", and may be throttled. Apple's guidance is not to send more than two or three per hour. The system keeps only the newest held one, and discards it if something force quits the app. When one arrives, the app gets 30 seconds. [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)
- **Visible, actionable notifications are the reliable path for a person.** An actionable notification lets the user respond without launching the app. When the user picks an action the system launches the app in the background and calls the notification center delegate. Action options include `authenticationRequired` (only on an unlocked device) and `foreground` (open the app). [Declaring actionable notification types](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types), [authenticationRequired](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired), [foreground](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/foreground)
- **Interruption levels.** `timeSensitive` (iOS 15+) can break through Focus and notification summary, and the user can turn it off. `critical` bypasses Do Not Disturb and requires an approved entitlement. [timeSensitive](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive), [critical](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical)
- **An app that is not running cannot hold a connection.** Remote notifications exist to reach devices "even when your app isn't running". So a long-poll or event stream works only while the app is in the foreground (design reasoning), and a push can only be a hint that something is pending.

### 3. Local network

- **Permission:** the first time a program accesses the local network, the system shows an alert, and the user's answer is remembered. `NSLocalNetworkUsageDescription` should be provided, and Bonjour use counts. [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- **Discovery:** `NWBrowser` finds Bonjour services on iOS 13+. [NWBrowser](https://developer.apple.com/documentation/network/nwbrowser)
- **Transport rules:** App Transport Security and certificate handling are in [topic 5](research-security-and-exposure.md).
- **On the LAN no push is needed while the app is open.** The event stream from the [transport note](research-transport-and-server.md) is enough. Push matters when the app is closed.

### 4. An Apple-only relay: CloudKit

A CloudKit query subscription "generates push notifications when CloudKit modifies records that match a predicate", applies only to the user who creates it, and works on the private database. Xcode adds the push entitlement when CloudKit is enabled, so no provider server is needed. Notifications are coalesced, so Apple says to treat them as "an indication of remote changes" and fetch the records. [CKQuerySubscription](https://developer.apple.com/documentation/cloudkit/ckquerysubscription)

As design reasoning, the Mac could write each pending request as a record and the phone could subscribe to it. Whether a subscription can produce a visible alert and not only a silent push, what iCloud stores of the request, and what the account and program requirements are, were not checked and are `Unverified`.

### 5. Other ways to reach a phone

- **Chat bridge:** Claude Code's channels reference shows how to build a chat bridge that relays permission prompts to another device, and Telegram, Discord and iMessage channels ship in the research preview. So a chat app can in principle be the phone client without writing an iOS app. Whether each bundled channel implements permission relay was not checked. [Channels](https://code.claude.com/docs/en/channels.md), [Channels reference](https://code.claude.com/docs/en/channels-reference.md)
- **First-party remote:** Claude Code's Remote Control and Codex's mobile remote connections are tied to each vendor's own account and app. See the [agent flow note](research-agent-approval-flows.md).
- **Third-party push services** were not researched.

## What the API must offer

These follow from the limits above, so they are design reasoning. They are requirements for the API contract, not endpoint definitions:

1. **A snapshot of pending requests,** fetched when the app opens. A push is a hint and can be late, duplicated, reordered, coalesced or lost, so the server is the source of truth.
2. **Idempotent decisions keyed by request id.** An action can fire twice, or arrive after the request expired. The server answers with the current state instead of overwriting (the late-decision rule in [topic 2](research-request-decision-interaction.md)).
3. **A resumable event stream** for the foreground, using `Last-Event-ID`. The app reconnects after suspension and resumes from the last event.
4. **Device registration and revocation:** the push token, the device public key from [topic 5](research-security-and-exposure.md) and a per-device revoke.
5. **A compact push payload** under 4 KB: the request id, a short summary, the expiry and a digest prefix. The full request is fetched on open or, with a service extension, decrypted before display. Treat all displayed text as untrusted and sanitize it.
6. **Expiry that allows for push latency.** A request that expires before a delayed push arrives must say so clearly when opened.
7. **A fast, authenticated decision call** that works from a notification action with only background time, using the device key and `authenticationRequired` so the device is unlocked.
8. **No silent pushes for approvals.** Visible notifications are the delivery path for a person.
9. **A relay that sees as little as possible.** If a relay carries the push, its payload should be opaque to it and to APNs (design reasoning, enabled by the service extension).

## Options

- **I-A. No iOS app in the first release,** with the API designed to the list above so one can be added.
- **I-B. LAN-only iOS app.** Works while the app is open, using the event stream, discovery and the local network permission. No relay and no push.
- **I-C. iOS app with an owner-run relay and APNs.** Reliable for a closed app. Needs the provider server and its upkeep.
- **I-D. iOS app with CloudKit as the relay.** No provider server of the owner's own. Apple-account dependent, and `Unverified` on alerts and privacy.
- **I-E. A chat bridge instead of an iOS app.** Not researched beyond the Claude Code precedent.

## Recommendation

Optional and not a decision. I-A for the first release, with the API contract written to the list above, so I-B to I-D remain open. Choose between I-C and I-D in a later phase with a small experiment on a real device.

## Open questions

- Does the owner want an iOS client in the first release, and is remote access needed from the start? The answer decides which of I-A to I-E applies.
- Does the owner have the Apple developer program membership that push or CloudKit needs? `Unverified` here.
- Are visible CloudKit subscription alerts possible and acceptable for this data? Not tested.
- Should the relay, if any, see request content, or only encrypted payloads?
- Is a chat bridge acceptable as an interim phone path?
- Untested here: everything on a phone, including action handling after a push, the permission flows and the time limits in practice.

## Sources

All read on 2026-10-07.

- Apple, Setting up a remote notification server: <https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server>
- Apple, Sending notification requests to APNs: <https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns>
- Apple, Generating a remote notification: <https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification>
- Apple, Pushing background updates to your App: <https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app>
- Apple, Declaring your actionable notification types: <https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types>
- Apple, UNNotificationActionOptions.authenticationRequired and .foreground: <https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired>, <https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/foreground>
- Apple, UNNotificationInterruptionLevel: <https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive>, <https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical>
- Apple, Modifying content in newly delivered notifications: <https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications>
- Apple, CKQuerySubscription: <https://developer.apple.com/documentation/cloudkit/ckquerysubscription>
- Apple, TN3179 Understanding local network privacy: <https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy>
- Apple, NWBrowser: <https://developer.apple.com/documentation/network/nwbrowser>
- Claude Code channels: <https://code.claude.com/docs/en/channels.md>
