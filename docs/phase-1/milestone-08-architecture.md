# P1-M8: Mac approval window, technical approach

Status: Planned

Implement the owner-approved single-window interface as a SwiftUI decider
client. M8 connects to an already-running service; bundled helper launch and
real setup-state detection remain P1-M9 responsibilities.

## Boundaries and state

`ApproveHub` gains the ordinary `ApproveHub Window` while retaining its
existing owner-command dispatch. A main-actor observable window model owns the
connection state, newest-first pending snapshots, selection, retained terminal
detail, inline request error, and event-stream task. SwiftUI views observe that
model and forward owner intents only: request ordering, authorization, request
content, and terminal transitions stay in the service.

The model represents the terms and transitions in [UX GUI](../ux-gui.md):
Connecting, No Pending Requests, Pending Request, No Longer Available,
Disconnected, Setup Required, Identity Error, and Request Error. M8 renders
Setup Required through its injected state for coverage, but an unreachable
listener is Disconnected in production until M9 supplies the bundled-helper
probe and launch path. Retry performs a new safe connection and refresh; it
never bypasses identity verification.

The Request List displays only pending snapshots in service-provided newest
first order. A new event does not replace an existing selection; when no
selection exists, the newest request is selected. A terminal event or completed
decision removes its pending row. If it was selected, its immutable snapshot
remains as disabled No Longer Available content until selection changes or the
next refresh, then the newest remaining request is selected. A disconnected
list is stale and has no enabled decision control.

## Decider client and trust boundary

Add a small injected decider-client surface for refresh, decision, and event
stream operations, backed by the generated OpenAPI client and a cancellable
URLSession `text/event-stream` reader. Each authenticated operation generates a
new 32-byte challenge, obtains and verifies the identity proof with the
installed pin, consumes the resulting authorization immediately before adding
the decider bearer credential, and discards it after one use. The same sequence
applies to every list, decision, stream connection, retry, and reconnect. A
pin or proof failure sends no bearer credential and produces Identity Error.

Move the shared local-identity Keychain service and account names to a public,
nonsecret `ApproveHubContract` definition. The service and GUI adapters use
that definition for the setup-created service pin and decider token; the GUI
does not read service files or service actors. The GUI loads the installed pin
and decider credential only through its Keychain adapter.

The window opens with an authoritative pending-list request and keeps the
returned event cursor. It connects SSE with that cursor, applies ordered
`request.created` and `request.terminal` snapshots, and stores each received
cursor. A `409 event_cursor_unavailable`, stream gap, or restart loss triggers
an authoritative list refresh before reconnecting. Other stream failures leave
the last list visible but stale as Disconnected. A missing or rejected decider
credential after a successful proof enables an explicit repair action only;
that action invokes the existing local owner-helper reset command, prints no
credential, and starts a fresh verified connection. Identity failure never
enables repair.

## Window behavior and accessibility

Render the two-column Request List and Request Detail layout with the complete
immutable requester, action type, submitted text, identifier, expiry, and
digest. Both row and detail actions submit the exact selected request identifier
and digest. They are enabled only for a pending request with verified identity
and a decider credential; they have no keyboard shortcuts or confirmation.
Decision conflicts and not-found results refresh the authoritative list and
never leave uncertain content approvable.

Expose Request List, Request Detail, state messages, Retry, Approve, and Deny
with the canonical labels from [UX terms](../ux-terms.md). Decision controls
include the request digest in their accessible labels and visible tooltips.
Standard keyboard navigation reaches all controls, color is not the only state
indicator, and focus moves to the state message when selection becomes
unavailable.

## Implementation sequence and evidence

1. Add the shared Keychain-name definition, GUI Keychain adapter, proof-gated
   decider client, and fakeable HTTP/event seams. Verify that failed proof
   paths cannot add a bearer credential.
2. Build the observable window model and its refresh, decision, selection, and
   reconnect transitions before adding SwiftUI presentation.
3. Implement the approved list, detail, controls, states, accessibility, and
   explicit decider-repair interaction. Keep service launch and live setup
   probing out of this milestone.
4. Add GUI-target tests with fake Keychain, transport, clock/randomness, and
   event source. Cover proof-before-bearer ordering; initial refresh and empty
   state; selection preservation; decisions; terminal, expired, and cancelled
   selections; reconnect replay; replay-loss refresh; stream cancellation;
   identity and credential failure; repair; and stale disconnected state.
5. Run the full validation gate, record completion evidence in the overview,
   and mark M8 Done only when every checklist item passes. M10 retains the
   bundled requester-to-GUI-to-requester end-to-end test.
