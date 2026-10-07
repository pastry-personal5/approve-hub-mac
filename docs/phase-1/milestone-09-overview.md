# P1-M9: Bundle and launch

Status: Planned

Package the service and GUI for the owner's Mac. Write this milestone's technical approach before activation.

## Goal

Ship an ad-hoc-signed `.app` that can launch an absent service and support foreground service operation.

## Scope

In: repository bundle script, bundled helper, GUI launch of an absent service, `approve-hub service` foreground command, service-identity verification during connection, and fail-closed occupied-port behavior.

Out: login launch, automatic crash restart, App Sandbox, Developer ID, notarization, and remote exposure.

## Completion checklist

- [ ] **Bundle:** The `.app` builds and signs ad-hoc, contains the helper, and runs on the approved macOS floor.
- [ ] **Launch smoke tests:** Foreground and GUI launch, already-running service, occupied port, absent or failed service, and credential-safe identity failure behave as documented.
- [ ] **Docs and gate:** The technical approach and user setup docs are current, M9 status is updated after evidence exists, and the full validation gate passes.
