# Product behavior

Status: Active

Product scope: what the app does and what it deliberately does not do. Accepted by the owner on 2026-10-07 from the P1-M1 interview and research. The decisions and their dates are in the [Phase 1 changelog](archive/phases/phase-1/changelog.md).

## What ApproveHub is

ApproveHub is a Mac app for approving what your AI agents ask to do. AI asks. You decide. Your agent continues.

## How it works

- A requesting app, which is a custom app and not an AI agent directly, submits an approval request to ApproveHub's API server.
- The owner sees the request in a deciding client and approves or denies it.
- The requesting app gets the outcome and continues or stops.

## The server and its clients

- ApproveHub runs an API server. The Mac GUI is one client of that server, and an iOS app can be another.
- The first release is Mac only. The API stays client-agnostic so an iOS client can be added later.

## Where it runs

- The server runs in the background as its own process.
- When the GUI launches it finds out whether the server is running. If it is, the GUI is a true client of it. If it is not, launch logic starts the server in the background and also starts the GUI.
- A human starts the server, either by launching the GUI or with a command. It does not start at login, and requesting apps do not start it. A crashed server is not restarted automatically.
- Platform: macOS 26 or later, on the owner's own Macs only.

## Who uses it and what it protects against

- One person, the owner, on their own devices. Requesting apps are written only by the owner for now.
- ApproveHub is a consent tool for cooperative agents. It does not claim to be a boundary against a malicious process running as the same user.

## Agents

- ApproveHub ships the API only. Custom apps bridge to agents.
- Integration with Claude Code CLI and Codex CLI is deferred to later phases.

## Requests

- **Action type.** The requesting app names an action type in free text, such as `shell.command`, and ApproveHub matches the exact string.
- **Expiry.** A request waits 2 minutes for a decision by default. A requesting app may ask for up to 10 minutes. A request nobody decided in time expires.
- **Outcomes.** A request ends as approved, denied, expired or cancelled (the requester withdrew or went away). The first decision wins, and a later decision is told the request's current state.
- **Waiting.** A requesting app can submit and wait for the decision in one call, or create a request and then wait in short steps.
- **When ApproveHub is unreachable.** If ApproveHub is down, not started yet, or a request times out, the requesting app blocks its action (fail-closed). ApproveHub cannot enforce this itself, so it is each requesting app's duty, and the API documents it.

## Deciding

- **Who may decide.** Only a deciding client can approve or deny. A requesting app can create, wait on and cancel its own requests, and can never decide.
- **Alerting.** When a request arrives, ApproveHub shows a macOS notification with Approve and Deny, and a badge in the menu bar until the request is handled.
- **Approving on the Mac.** A click approves a request.
- **Sensitive requests.** A sensitive request requires Touch ID, however it is approved. A request is sensitive if the owner's rules say so or if the requesting app flags it. A rule matches a requesting app or an action type and nothing else, and only marks requests as sensitive.
- **Approvals never change a request.** The owner approves or denies exactly what was asked. A decision is tied to the exact request: it names a digest of the request, and the server rejects a decision whose digest does not match.
- **Approve for the session.** The owner can approve a requesting app's action type for the session. A later request from the same requesting app with the same action type is then approved without asking. Each request carries a session id from the requesting app, and the app may send an explicit end call. A grant ends at that call or after 1 hour, whichever comes first. A request approved by a grant is recorded in the history, marked as approved by grant and with its full text, and does not notify the owner. A sensitive request is never approved by a grant, and a grant is never created from one.

## History

ApproveHub keeps decided requests with their full request text, the outcome and the time. Entries older than 90 days are removed automatically, and the owner can clear the history at any time. After a server restart the history and the owner's rules remain. Pending requests and session grants are dropped.

## Not in scope for now

- Several people approving, with roles or a quorum.
- A public API for other developers' apps.
- An iOS app in the first release.
