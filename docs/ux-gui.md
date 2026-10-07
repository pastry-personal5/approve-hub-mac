# UX GUI

Status: Active

This document defines the owner-approved behavior of the early-release approval window. It describes interaction and accessible behavior; [layout](ux-information-architecture.md) defines containment and [terms](ux-terms.md) defines the component names.

## Approval window

ApproveHub has one ordinary macOS window. It remains open to show live pending requests; the release has no notification or menu-bar alert. The window is an inbox-style two-column layout: the **Request List** at left and **Request Detail** at right.

The Request List contains only ordinary pending requests, newest first. A row shows the requester, action type, and one line of submitted-text preview. Selecting its title opens Request Detail. If nothing is selected, the newest request is selected. New arrivals update the list but never replace the current selection.

Each row has accessible Approve and Deny icon controls on its right. They decide that row immediately, need no confirmation, and have visible tooltips and complete VoiceOver labels. Request Detail repeats Approve and Deny at its top-right. Neither decision has a keyboard shortcut. A control is enabled only for a selected or represented pending request when the GUI has both a verified service identity and its decider credential. Every decision names the request's immutable digest.

Request Detail presents the full immutable request: requester, action type, submitted text, request identifier, expiry, and digest. After a decision, the newest remaining request is selected. If a request expires, is cancelled, or is decided elsewhere while selected, its detail remains visible as non-actionable **No Longer Available** content until selection changes or the next refresh; it is not history.

## Window states

- **Connecting:** The GUI obtains a fresh service proof and connects its event stream. No request action is available.
- **No Pending Requests:** The connected empty state says that ApproveHub is ready and waiting.
- **Pending Request:** The list and selected detail are available.
- **No Longer Available:** The selected request is terminal and all decisions are disabled.
- **Disconnected:** Any last-known list is marked stale and non-actionable. Retry is available; this is distinct from identity failure.
- **Setup Required:** The bundled helper reports that explicit owner setup has not occurred. The window provides the owner CLI next step.
- **Identity Error:** A missing or wrong pin, malformed proof, reused or expired challenge, or unknown listener sends no credential and provides recovery guidance. A missing or rejected decider credential can recover only through the local-helper flow after successful pin verification.
- **Request Error:** A recoverable refresh or decision failure appears inline in the affected detail. It never makes uncertain state approvable.

## Accessibility and keyboard behavior

VoiceOver exposes **Request List**, **Request Detail**, the state message, **Retry**, **Approve**, and **Deny** by those names. Standard keyboard navigation reaches every control; there is no dedicated approval shortcut. When a selection becomes unavailable, focus moves to the state message; otherwise focus remains where the owner was working. Color is never the sole indication of connection, error, or destructive action.
