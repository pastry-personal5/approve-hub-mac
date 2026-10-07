# UX information architecture

Status: Active

This document defines the Standard Layout: the conceptual containment model
for the early-release app. Visual and interaction rules are in
[ux-gui.md](ux-gui.md).

## Standard Layout

```text
ApproveHub Window
├── Window State
├── Request List
│   └── Request Row*
│       ├── Request Title
│       ├── Request Preview
│       └── Row Decision Controls
└── Request Detail
    ├── Request Metadata
    ├── Request Content
    ├── Detail Decision Controls
    └── Inline State or Error Message
```

The Window State owns Connecting, No Pending Requests, Disconnected, Setup
Required, and Identity Error presentation. Request List owns ordering and
selection of pending requests. Request Detail owns presentation of the selected
immutable request and its No Longer Available or Request Error content.

Only Request List and Request Detail contain decision controls. They ask the
API client to decide; they do not hold policy or alter request content. The
GUI client owns connection, verified-service identity, decider credential, and
event-stream state. The service remains the source of truth for every request
and decision.
