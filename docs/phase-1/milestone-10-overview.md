# P1-M10: Early-release acceptance

Status: Planned

Exercise and document the complete early Mac release. Write this milestone's technical approach before activation.

## Goal

Demonstrate that an owner-registered requester can obtain an ordinary approval outcome from the Mac GUI.

## Scope

In: fresh setup, pin and credential distribution, requester-to-GUI-to-requester approval and denial, failures and restart behavior, bundled-app E2E, manual checks, release limitations, and milestone closeout.

Out: rules, grants, notifications, menu-bar badge, history, sensitive approvals, agent adapters, and iOS.

## Completion checklist

- [ ] **E2E:** The bundled-app suite runs rather than skips and covers requester create/wait, GUI Approve and Deny, returned outcome, wrong pin, sensitive rejection, and service interruption.
- [ ] **Manual checks:** Fresh owner setup, token shown once, pin transfer, window accessibility, foreground service, and GUI launch are checked and recorded.
- [ ] **Release docs:** User setup and limitations state that the window must stay open, pending requests and outcomes disappear on restart, requesters fail closed, and deferred features are unavailable.
- [ ] **Closeout:** M3–M10 checklists have evidence, the phase exit criteria hold, the full validation gate passes, and roadmap, phase, changelog, and index statuses are updated.
