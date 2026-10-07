# Research: product scope proposal

Status: Superseded by [product-behavior.md](../product-behavior.md)

Proposed text for [product-behavior.md](../product-behavior.md), assembled from the owner's statements in the [Phase 1 changelog](phases/phase-1/changelog.md) and from what the P1-M1 research implies. Nothing here is decided until the owner accepts text into `product-behavior.md`, which AGENTS.md lists as a Decided doc.

## Where each statement comes from

| Kind | What it covers | Owner action |
|---|---|---|
| **Owner statement** | Said by the owner on 2026-10-07 and recorded in the changelog | Confirm the wording |
| **Derived from research** | Follows from one of the research notes, not from anything the owner said | Accept or reject |
| **Open** | A product question that only the owner can answer | Answer |

## Proposed text for `product-behavior.md`

> **ApproveHub** is a Mac app for approving what your AI agents ask to do. AI asks. You decide. Your agent continues. *(owner statement, from the README tagline)*
>
> **How it works.** A requesting app, which is a custom app and not an AI agent directly, submits an approval request to ApproveHub's API server. The owner sees the request in a deciding client and approves or denies it. The requesting app gets the outcome and continues or stops. *(owner statement)*
>
> **The server and its clients.** ApproveHub runs an API server. The Mac GUI is one client of that server, and an iOS app can be another. The first release is Mac only. *(owner statement)*
>
> **Who uses it.** One person, the owner, on their own devices. Requesting apps are written only by the owner for now. *(owner statement)*
>
> **Where it runs.** The server runs in the background. When the GUI launches it finds out whether the server is running. If it is, the GUI is a true client of it. If it is not, launch logic starts the server in the background and also starts the GUI. A human starts the server. It does not start at login, and requesting apps do not start it. *(owner statement)*
>
> **Platform.** macOS 26 or later, on the owner's own Macs only. *(owner statement)*
>
> **What it protects against.** ApproveHub is a consent tool for cooperative agents. It does not claim to be a boundary against a malicious process running as the same user. *(owner statement)*
>
> **Agents.** ApproveHub ships the API only, and custom apps bridge to agents. Integration with Claude Code CLI and Codex CLI is deferred to later phases. *(owner statement)*
>
> **Expiry.** A request waits 2 minutes for a decision by default. A requesting app may ask for up to 10 minutes. A request nobody decided in time expires. *(owner statement)*
>
> **Approving on the Mac.** A click approves a request. A sensitive request requires Touch ID. A request is sensitive if the owner's rules say so, where the owner can mark requesting apps or action types as sensitive, or if the requesting app flags it. A rule matches a requesting app or an action type and nothing else, and only marks requests as sensitive. *(owner statement)*
>
> **Action types.** The requesting app names an action type in free text, such as `shell.command`, and ApproveHub matches the exact string. *(owner statement)*
>
> **Approvals never change a request.** The owner approves or denies exactly what was asked. *(owner statement)*
>
> **Approve for the session.** The owner can approve a requesting app's action type for the session. A later request from the same requesting app with the same action type is then approved without asking. Each request carries a session id from the requesting app, and the app may send an explicit end call. A grant ends at that call or after 1 hour, whichever comes first. A request approved by a grant is recorded in the history, marked as approved by grant and with its full text, and does not notify the owner. A sensitive request is never approved by a grant, and a grant is never created from one. *(owner statement)*
>
> **History.** ApproveHub keeps decided requests with their full request text, the outcome and the time, until the owner clears them. *(owner statement)*
>
> **Outcomes.** A request ends as approved, denied, expired or cancelled (the requester withdrew or went away). The first decision wins, and a later decision is told the request's current state. *(derived from [topic 2](../research-request-decision-interaction.md))*
>
> **Who may decide.** Only a deciding client can approve or deny. A requesting app can create, wait on and cancel its own requests, and can never decide. *(derived from [topic 5](../research-security-and-exposure.md))*
>
> **Not in scope for now.** Several people approving, with roles or a quorum. A public API for other developers' apps. These follow from "one owner" and "written only by the owner" and are written as exclusions so they are visible. *(derived from the owner statements above)*

## Open product questions

These are not answered by anything the owner has said:

1. **History limits.** Is there any automatic limit on how much history is kept, or does it grow until the owner clears it?
2. **Unreachable ApproveHub.** What should a requesting app's action do when ApproveHub is down or a request times out? Deferred together with agent integration (see the changelog), so no default exists yet. It matters more now: the server starts only when a human starts it, so a request sent before then finds nothing listening.
3. **Where requests are shown.** What the GUI does when a request arrives while the Mac is locked or the owner is away is a UX question for [ux-gui.md](../ux-gui.md), and has not been asked.

## How to accept this

Mark which statements are wrong or missing, and answer the open questions you want settled now. Accepted text is moved into `product-behavior.md`, this doc's status becomes `Archived`, and the acceptance is logged in the [changelog](phases/phase-1/changelog.md).
