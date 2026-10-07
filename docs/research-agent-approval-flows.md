# Research: agent approval flows and integration points

Status: Active

How Claude Code and Codex CLI raise an approval, how they block and resume, and where a third-party app can intercept or connect to that flow. Written for [P1-M1](archive/phases/phase-1/milestone-01-overview.md) topic 1. It recommends nothing final; decisions are made in P1-M2.

Accepted by the owner on 2026-10-07 as the record of what was found. Where an owner decision in the [Phase 1 changelog](archive/phases/phase-1/changelog.md) conflicts with a recommendation here, the decision wins.

## Method

- **Versions examined:** Claude Code 2.1.292 and codex-cli 0.160.1, both installed locally on macOS 26.7.
- **Sources:** the vendors' raw Markdown docs, read on 2026-10-07 (listed under "Sources"). Summaries from the web-fetch tool were not used for any claim here, because one of them invented a `PermissionRequest` output field (`applyRule`) that the raw docs don't contain.
- **Experiments:** 18 short runs, in the session scratchpad, not in this repo. Each result is marked "Observed" below.
  - Claude Code: 6 runs of `claude -p` with `--model haiku` (A1 to A4, F1, F2), each asking for a single `touch` command.
  - Codex: 12 runs of `codex exec` with the owner's logged-in Codex session and its default model (C0 to C4, D0 to D3, E1 to E3), each asking for the same `touch`.
  - Both used the owner's API credits and logged-in sessions. Each run was a few short model turns.
- **Marking:** a claim with no primary source or experiment behind it is marked `Unverified`.

## Questions

1. How does each agent raise an approval, what does it wait on, how does it resume, and what happens on timeout or no answer?
2. Where can a third-party app intercept or connect to that flow?
3. For each integration point: can it block, can it allow, deny or modify, what context does it expose, does it fail open or closed, and what trust or installation does it need?
4. How can a requesting app bridge an agent into ApproveHub's API?
5. Should ApproveHub ship agent adapters, or only the API?

## Findings

### 1. How each agent raises, waits and resumes

**Claude Code**

- **Interactive:** a tool call that no rule or permission mode approves opens a terminal dialog, and the session waits for the answer. The docs describe no timeout for the dialog, which is `Unverified` beyond that. A `Notification` hook of type `permission_prompt` fires only after the prompt has waited about six seconds. [hooks, PermissionRequest](https://code.claude.com/docs/en/hooks.md)
- **Evaluation order:** deny and ask rules are still evaluated after a hook returns allow, so a hook cannot override a matching deny rule. [hooks, PermissionRequest decision control](https://code.claude.com/docs/en/hooks.md)
- **Non-interactive (`claude -p`):** there is no terminal to prompt. `PermissionRequest` hooks still run. If none decides, and no permission host answers, the call is denied. A permission host is an MCP tool passed with `--permission-prompt-tool`, or the Agent SDK's `canUseTool` callback. [hooks](https://code.claude.com/docs/en/hooks.md), [headless](https://code.claude.com/docs/en/headless.md), [CLI reference](https://code.claude.com/docs/en/cli-reference.md)
- **Resume:** the tool call proceeds or is rejected at the point it was raised. `PreToolUse` also has a `defer` decision, honored only in `-p` mode and only when the turn makes a single tool call, which exits the process and resumes later with no timeout. [hooks, defer](https://code.claude.com/docs/en/hooks.md)

**Codex CLI**

- **Policy:** `approval_policy` is `on-request`, `never` or a `granular` table. The old `untrusted` value is retired. A sandbox mode (`read-only`, `workspace-write` and so on) sets what runs without approval. [agent approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security.md)
- **Reviewer:** `approvals_reviewer` is `user` or `auto_review`. With `auto_review`, a separate reviewer agent answers eligible escalation requests instead of a person. [auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review.md)
- **App-server hosts:** when Codex runs under `codex app-server`, the server sends the host client a JSON-RPC request for each approval and resumes or declines the work when the client answers. [app-server, Approvals](https://learn.chatgpt.com/docs/app-server.md)
- **`codex exec`:** takes sandbox and approval settings up front and streams JSONL events. The docs describe no third-party approval channel for it. [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode.md)

### 2 and 3. Integration points

| Mechanism | Agent | Can block while a human decides | Decisions | Context exposed | If the integration fails or times out | Trust and install |
|---|---|---|---|---|---|---|
| `PermissionRequest` hook, `command` or `http` | Claude Code | Yes (Observed: held 5 s, then ran) | allow, deny with message; optional `updatedInput`, `updatedPermissions`, `interrupt` | `tool_name`, `tool_input` (with `description`), `permission_suggestions`, `session_id`, `cwd`, `permission_mode` | Falls back to the normal permission flow. Observed: denied in `-p`. Interactively that flow is the terminal prompt (inferred, not tested) | A settings file, run as the user. Held back in interactive sessions until workspace trust is accepted. Anyone who can edit settings can disable hooks unless managed settings forbid it |
| `PreToolUse` hook | Claude Code | Yes | allow, deny, ask, defer; `updatedInput` | Same plus `tool_use_id` | Exit code 2 blocks. For `command`, `http` and `mcp_tool` hooks, any other exit code, a crash, a missing script, bad JSON, a non-2xx response, a connection failure or a timeout lets the call proceed through the normal flow | As above |
| `--permission-prompt-tool` | Claude Code | Yes (Observed: held 4 s) | allow with `updatedInput`, or deny with `message`, as text JSON | `tool_name`, `input`, `tool_use_id` (Observed) | `Unverified` when the tool errors or never answers. Documented only: at startup Claude Code waits up to 30 s by default for the MCP server to connect | `-p` mode only. The MCP server is started by the launching process |
| Agent SDK `canUseTool` | Claude Code | Yes | `{behavior: "allow", updatedInput}` or `{behavior: "deny", message}` | Tool name, input, suggestions | `Unverified` when the callback errors or never answers. Separately, an Agent SDK callback *hook* that exceeds its timeout blocks the call | The host app embeds the SDK. Calls approved earlier by a rule or mode never reach it |
| Channels permission relay | Claude Code | Yes, in parallel with the terminal. The first answer wins | allow or deny per call | `request_id`, `tool_name`, `description`, `input_preview` (sanitized, 3,500 code points, credentials masked) | The terminal dialog stays open, so a missing relay changes nothing | Research preview. Needs `--channels` per session and a claude.ai or Console API-key login. Not on Amazon Bedrock, Google Cloud's Agent Platform or Microsoft Foundry. Team and Enterprise plans need `channelsEnabled` |
| `PermissionRequest` hook, `command` or `mcp_tool` | Codex CLI | Yes, within the hook timeout (default 600 s) | allow, deny with message. `updatedInput`, `updatedPermissions` and `interrupt` are reserved and fail closed | `tool_name`, `tool_input` (`command`, `description`), `turn_id`, `session_id`, `cwd`, `model`, `permission_mode` | Observed: a crash, a timeout (the hook process was killed), or no decision all fall through to the normal approval flow. A deny always wins | Hooks need a trust review by hash, or `--dangerously-bypass-hook-trust` for one run. Project hooks need a trusted project. Managed hooks come from `requirements.toml` |
| `PreToolUse` hook | Codex CLI | Yes | deny, or allow with `updatedInput`. `ask` is parsed but unsupported, so the hook is marked failed and the call continues | `tool_name`, `tool_input`, `tool_use_id` | A callback error, timeout or malformed response can fail the hook without blocking the tool | As above. Hosted tools such as `WebSearch` are not covered |
| `codex app-server` host client | Codex CLI | Yes | `accept`, `acceptForSession`, `decline`, `cancel`, or `acceptWithExecpolicyAmendment` | `command`, `cwd`, `reason`, `commandActions`, `networkApprovalContext`, `availableDecisions`, `threadId`, `turnId` | `Unverified`. The app-server's own timeout behavior is not described in the pages read | The host launches and owns the Codex process. The WebSocket transport is documented as experimental and unsupported, and non-loopback listeners are unauthenticated by default during rollout |
| ACP client, via an adapter | Both | Yes | `selected` option (`allow_once`, `allow_always`, `reject_once`, `reject_always`) or `cancelled` | `sessionId`, `toolCall` update, `options` | `Unverified` | Needs a third-party adapter for these two: Zed's `claude-agent-acp` and ACP's `codex-acp`. The ACP agents page also lists many other agents, such as Gemini CLI, Cursor, OpenCode and GitHub Copilot (public preview), and the host must launch the agent |

Terminal or PTY wrapping, and a wrapper process around the CLI, are `Unverified` design options. Neither vendor documents them as supported, and neither was tested.

**Observed, Claude Code** (print mode, `--model haiku`; scripts in the scratchpad):

- **A1, HTTP hook that holds 5 s, then allows:** the hook received the full request as JSON. Claude Code waited for the response and then ran the command.
- **A2, hook denies with a message:** the command did not run, and the message reached the model verbatim.
- **A3, server not running:** the call was denied in `-p` mode. The request was never delivered.
- **A4, hook timeout 2 s, server delays 6 s:** the hook was cancelled and the call was denied in `-p` mode.
- **F1 and F2, `--permission-prompt-tool` with a stdio MCP server:** the tool received `{tool_name, input, tool_use_id}`. Returning `{"behavior":"allow","updatedInput":…}` ran the command after the 4 s delay, and `{"behavior":"deny","message":…}` blocked it.

**Observed, Codex CLI** (`codex exec`, read-only sandbox, `approval_policy="on-request"`):

- **C1, command hook allows after 4 s:** the hook received the request as JSON on stdin, and the command ran.
- **C2 and E3, hook denies:** the command did not run, and the message reached the model. A deny won even with `approvals_reviewer="auto_review"`.
- **C3, hook crashes with exit 1:** the command ran.
- **E1, hook timeout 2 s while the hook sleeps 6 s:** the hook process was killed at the timeout, and the command ran.
- **E2, hook declines (exit 0, no output) with `auto_review` set:** the command ran.
- **D0 to D3, `approvals_reviewer="user"`:** the model never requested escalation and the hook never fired.
- **Reading the results:** crash, timeout and no decision all fell through to the normal flow. In these runs that flow ended in the reviewer approving a harmless `touch`. What happens with a human reviewer is `Unverified`, because `codex exec` offered no way to reach one. The owner's default reviewer is also `Unverified`, since the user-level Codex config was not read.

### 4. Failure and bypass

- **Neither agent fails closed on its own.** For Claude Code hooks, only exit code 2 blocks by code alone, and only on events that can block, such as `PreToolUse`. On `PermissionRequest`, exit 2 is not honored at all. The docs warn that exit 1 is a non-blocking error, and that a mistyped hook path leaves the gate silently disabled. [hooks, exit codes](https://code.claude.com/docs/en/hooks.md)
- **The difference is the fallback.** When an integration fails, the agent falls back to its normal approval flow. That is a person at the terminal when interactive, a denial in Claude Code `-p`, and whatever reviewer is configured in Codex. So ApproveHub being down degrades to the agent's own behavior. It does not approve by default, but it can end up approving if that behavior is permissive.
- **A fail-closed gate needs a wrapper.** A `command` hook script can catch its own errors and print an explicit deny. An `http` hook cannot, because Claude Code treats every HTTP failure as non-blocking, so a Claude Code `http` hook is fail-to-normal-flow by construction.
- **The gate can be removed by whoever controls settings.** Claude Code has `disableAllHooks`. Managed settings add `allowManagedHooksOnly`, `allowedHttpHookUrls` and `permissions.disableBypassPermissionsMode`. Codex has `--dangerously-bypass-hook-trust` and managed hooks via `requirements.toml`. Both vendors call hooks a guardrail and not a complete enforcement boundary. [settings reference](https://code.claude.com/docs/en/settings-reference.md), [Codex hooks](https://learn.chatgpt.com/docs/hooks.md)
- **Allow rules skip the callback.** Calls approved by a rule, `acceptEdits` or `bypassPermissions` never reach `canUseTool`, and a `PermissionRequest` hook fires only when a prompt would otherwise appear. A `PermissionRequest` hook or permission host therefore sees only what the agent would have asked a person about, while a `PreToolUse` hook sees every tool call.

### 5. First-party remote approval exists

Claude Code's Remote Control continues a local session from a phone or browser through claude.ai, and Codex has remote connections for mobile. [Remote Control](https://code.claude.com/docs/en/remote-control.md), [Codex remote connections](https://learn.chatgpt.com/docs/remote-connections.md) Both are tied to the vendor's own account and app, so they are prior art for the iOS client rather than an integration point for a custom app.

### 6. What supporting a third agent would take

For any further agent, the work is the same two checks, and the second one is the cheaper route if it holds:

1. **Does it have a blocking approval hook?** Both agents examined have a `PermissionRequest` hook with the same allow-or-deny shape, so a shim (Option A below) is a small script that maps the agent's JSON onto the request fields. Whether another agent has such a hook is `Unverified` for every other agent.
2. **Does it speak ACP?** The ACP agents page lists many agents. Where one does, a single ACP client can answer `session/request_permission` for all of them, so the mapping to the request fields is written once. That page is the ACP project's own list, and I did not check any listed agent's claim. [ACP agents](https://agentclientprotocol.com/overview/agents.md)

Either way, adding an agent should change the requesting app, not ApproveHub's API, as long as the request fields below are enough.

## Options

How a requesting app can bridge an agent into ApproveHub's API:

- **A. Hook shim.** The agent runs a small hook (an `http` hook for Claude Code, a `command` hook for both agents) that posts the request to ApproveHub and waits for the decision.
  - Pro: no process wrapping, and the user keeps the normal agent UI.
  - Con: the hook runs as the user and can be disabled, and the failure fallback is the agent's own flow unless a command-hook wrapper handles errors.
- **B. Host app.** A custom app launches the agent as a library or subprocess and answers its approval requests: `canUseTool`, `--permission-prompt-tool`, the Codex app-server, or an ACP client. The ACP client is the one variant that is not tied to a single vendor.
  - Pro: the host owns the process, so a crash can fail closed (deny), and the request carries structured context.
  - Con: it changes how the user runs the agent, and the Codex app-server transports are marked experimental.
- **C. Channel relay (Claude Code only).** A channel MCP server forwards prompts while the terminal dialog stays open.
  - Pro: ApproveHub is an additional approver and cannot make things worse than the terminal.
  - Con: it is a research preview with login and per-session opt-in constraints, and it covers tool-use approvals only.
- **D. PTY or wrapper process.** `Unverified`, with no vendor support.

## Recommendation

Optional and not a decision. Shape the requesting-app contract (topic 2) around the fields all of A and B can supply, so either style works:

- **Request fields:** agent kind, session id, tool name, tool input, a human-readable description, `cwd`, and a request id.
- **Decision:** allow, deny, with a message.
- **Later:** optionally `updatedInput`, and a durable "allow for session" style grant.

Treat fail-closed behavior as the requesting app's responsibility, and treat ApproveHub itself as unable to enforce it.

## Open questions

- Which mechanism should owner-written adapters use first? ApproveHub ships only the API, and adapter style remains in [AGENTS.md](../AGENTS.md#undecided--ask-before-inventing).
- Should ApproveHub support only first-party-documented mechanisms (hooks, `--permission-prompt-tool`, `canUseTool`, app-server) and treat ACP, channels and PTY wrapping as later options?
- Untested here: interactive-session behavior of a failed hook (documented but not run), the Codex app-server's behavior when a client never answers, and the Codex human-reviewer fall-through.
- The owner's default Codex reviewer is `Unverified`. It matters only for interpreting the Codex failure runs.

## Reproducing the experiments

The scripts lived in the session scratchpad and are not kept. These are enough to recreate every "Observed" result. Use a scratch directory and expect each run to use a few short model turns.

**Claude Code, `PermissionRequest` over HTTP (A1 to A4).** Run a local HTTP server on `127.0.0.1:48901` that logs each request body, sleeps for a chosen number of seconds, then answers with `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`, or `"behavior":"deny"` with a `"message"`. For A3, don't start it. For A4, set the hook `timeout` below the server's delay. Settings file:

```json
{"hooks":{"PermissionRequest":[{"matcher":"Bash","hooks":[{"type":"http","url":"http://127.0.0.1:48901/hook","timeout":30}]}]}}
```

```sh
claude -p "Use the Bash tool to run exactly this command: touch marker.txt   Then reply with the single word DONE." \
  --model haiku --settings ./settings.json --permission-mode default \
  --output-format json --no-session-persistence < /dev/null
```

Check whether `marker.txt` exists and what `result` and `permission_denials` say in the JSON.

**Claude Code, `--permission-prompt-tool` (F1, F2).** A stdio MCP server, speaking newline-delimited JSON-RPC (`initialize`, `tools/list`, `tools/call`), exposes one tool `approve` whose input schema has `tool_name`, `input` and `tool_use_id`. On `tools/call` it sleeps, then returns one text content item containing `{"behavior":"allow","updatedInput":<the input it received>}` or `{"behavior":"deny","message":"..."}`. Pass it as `--mcp-config ./mcp.json --permission-prompt-tool mcp__<server name>__approve` on the same `claude -p` command, with `< /dev/null`.

**Codex, `PermissionRequest` command hook (C0 to E3).** The hook script reads the event JSON on stdin and logs it. After an optional sleep it prints `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`, or deny with a `"message"`. For the failure cases it exits 1 with no JSON (crash), or exits 0 with no output (declines). Run:

```sh
codex exec --skip-git-repo-check --ephemeral --json -C <scratch dir> -s read-only \
  -c 'approval_policy="on-request"' \
  -c 'hooks.PermissionRequest=[{matcher="Bash",hooks=[{type="command",command="python3 -I <abs path>/hook.py",timeout=30}]}]' \
  --dangerously-bypass-hook-trust \
  "Run the shell command: touch marker.txt . If the sandbox blocks it, retry the same command requesting escalated permissions. If it is still not allowed, reply with the exact reason you were given. Otherwise reply DONE." < /dev/null
```

Add `-c 'approvals_reviewer="auto_review"'` or `"user"` to reproduce E2, E3 and D0 to D3. Log a second line when the hook's sleep finishes, to see whether Codex killed it at the timeout (E1).

## Sources

All read on 2026-10-07. Claude Code 2.1.292 and codex-cli 0.160.1 are the installed versions; the docs carry their own version notes.

- Claude Code hooks reference: <https://code.claude.com/docs/en/hooks.md>
- Claude Code CLI reference: <https://code.claude.com/docs/en/cli-reference.md>
- Claude Code headless mode: <https://code.claude.com/docs/en/headless.md>
- Claude Code permissions: <https://code.claude.com/docs/en/permissions.md>
- Claude Code settings reference: <https://code.claude.com/docs/en/settings-reference.md>
- Claude Code channels: <https://code.claude.com/docs/en/channels.md> and <https://code.claude.com/docs/en/channels-reference.md>
- Claude Code Remote Control: <https://code.claude.com/docs/en/remote-control.md>
- Claude Agent SDK, handle approvals and user input: <https://code.claude.com/docs/en/agent-sdk/user-input.md>
- Claude Agent SDK, permissions: <https://code.claude.com/docs/en/agent-sdk/permissions.md>
- Codex hooks: <https://learn.chatgpt.com/docs/hooks.md>
- Codex agent approvals and security: <https://learn.chatgpt.com/docs/agent-approvals-security.md>
- Codex auto-review: <https://learn.chatgpt.com/docs/sandboxing/auto-review.md>
- Codex app-server: <https://learn.chatgpt.com/docs/app-server.md>
- Codex non-interactive mode: <https://learn.chatgpt.com/docs/non-interactive-mode.md>
- Codex SDK: <https://learn.chatgpt.com/docs/codex-sdk.md>
- Codex remote connections: <https://learn.chatgpt.com/docs/remote-connections.md>
- Agent Client Protocol, tool calls: <https://agentclientprotocol.com/protocol/tool-calls.md>
- Agent Client Protocol, agents: <https://agentclientprotocol.com/overview/agents.md>
