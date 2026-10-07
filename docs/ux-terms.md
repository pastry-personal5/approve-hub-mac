# UX terms

Status: Active

This is the canonical vocabulary for visible user interface components, and their code-facing names. Use the exact component terms in UI text and accessibility-visible names; use the mapped lower-camel or snake-case names in implementation identifiers when a component is represented there.

## Canonical components

| Visible term | Code-facing name | Meaning |
|---|---|---|
| ApproveHub Window | `approveHubWindow` | The single ordinary macOS window. |
| Request List | `requestList` | The newest-first sidebar of pending requests. |
| Request Row | `requestRow` | One pending request in the list. |
| Request Title | `requestTitle` | The selectable requester, action, and submitted-text preview. |
| Request Detail | `requestDetail` | The full immutable selected request. |
| Approve | `approveAction` | An action that approves the named request and digest. |
| Deny | `denyAction` | An action that denies the named request and digest. |
| Retry | `retryAction` | An action that retries a safe connection or refresh operation. |
| No Pending Requests | `emptyState` | The connected empty inbox state. |
| No Longer Available | `unavailableState` | The disabled detail for a terminal request. |
| Disconnected | `disconnectedState` | The stale, non-actionable connection-loss state. |
| Setup Required | `setupRequiredState` | The helper's unconfigured state. |
| Identity Error | `identityErrorState` | The fail-closed service-identity state. |
| Request Error | `requestErrorState` | An inline refresh or decision error. |
