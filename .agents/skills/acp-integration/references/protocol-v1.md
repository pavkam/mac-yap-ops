<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# ACP v1 and YapOps

Validated against the stable ACP v1 documentation on 2026-09-05.

## Wire and lifecycle

YapOps is the ACP client. Cursor or an adapter process is the ACP
agent. Communication is UTF-8 JSON-RPC 2.0 over child-process stdin and stdout,
with one compact JSON value per line. A protocol line cannot contain a literal
newline. Stdout is protocol-only; stderr is a separate diagnostic stream.

The supported lifecycle is:

1. `initialize` with `protocolVersion: 1`, empty `clientCapabilities`, and
   client metadata.
2. `session/new` with an absolute `cwd` and `mcpServers: []`.
3. One `session/prompt` at a time in the current session.
4. Ordered `session/update` notifications until the prompt response supplies a
   stop reason.
5. `session/cancel` for authoritative cancellation.
6. `session/request_permission` responses that return the agent's exact option
   identifier or a cancelled outcome.

The app relies on ambient provider authentication. It does not currently issue
`authenticate`. A `session/new` JSON-RPC error with code `-32000` is mapped to
provider authentication guidance.

ACP capabilities are negotiated during initialization. An omitted capability
means unsupported. The stable baseline includes text and resource-link prompt
content plus session creation, prompt, cancel, and updates; optional loading,
terminal, filesystem, MCP, elicitation, and authentication features must be
gated by the advertised capability before use.

## Conversational input extension boundary

Stable ACP v1 has no portable operation for adding input to an active prompt.
Ordinary language remains opaque agent input; YapOps does not infer
whether it adds, corrects, pauses, repeats, or replaces anything. Exact local
stop and pending-permission controls are handled before this transport path.

Safe `_session/steering` is an exact-pin compatibility contract, not a general
ACP capability. It is enabled only for preset `claude` when that process's
`initialize` result reports agent name
`@agentclientprotocol/claude-agent-acp`, version `0.73.0`, and
`_meta.steering.supported: true`. The request sets
`idleBehavior: "promptRequired"`. Only `injected` and `promptRequired` are safe
results; only `promptRequired` permits one later ordinary prompt. Every
ambiguous result or failure closes the connection and forbids replay.

Cursor and Codex ACP 1.8.0 use the bounded FIFO `session/prompt` fallback.
Codex advertises steering, but its idle path may start a detached turn that the
standard client cannot own to completion. Capability advertisement alone is
therefore insufficient.

## Async-task extension boundary

Stable ACP v1 has no detached-task lifecycle. The project enables JetBrains AIR
async tasks only for preset `claude` when the current initialize exchange proves
adapter `@agentclientprotocol/claude-agent-acp` version `0.73.0` and both peers
advertise AIR version 1 with `asyncTasks`. Only then may the client retain typed
spawn/progress/state events between turns or send `_session/async_task/stop`.

The stop response is transport acknowledgement, not terminal task state. Keep
the exact session/task identities, wait for the provider state update, retain no
more than 32 task rows per session, and pin at most four active sessions. Process
exit marks opaque work interrupted; never replay a prompt or claim a task resumed.
Codex ACP 1.8.0, Cursor 2026.01.23, custom providers, and version drift do not
enter this path.

## Project implementation contract

- `ACPLineFramer` rejects frames over 1 MiB.
- `ACPMessage` and `ACPJSONValue` preserve JSON-RPC IDs as `int64`, string, or
  null. Never round-trip them through a floating-point value.
- `ACPClientConnection` accepts protocol version 1 only and routes updates only
  for its current session ID.
- `ACPEventDecoder` handles `user_message_chunk`, `agent_message_chunk`,
  `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`,
  `available_commands_update`, `current_mode_update`, `config_option_update`,
  `session_info_update`, and `usage_update`.
- Negotiated Claude AIR additionally decodes bounded `async_task_spawned`,
  `async_task_progress`, and `async_task_state_update` events.
- Unknown updates become bounded diagnostics. Unknown inbound requests receive
  JSON-RPC method-not-found.
- Cursor blocking requests `cursor/ask_question` and `cursor/create_plan`
  receive cancelled results so the provider cannot wait forever.
- `ACPProcessTransport` launches an absolute executable directly with an
  argument array. Do not introduce a shell.
- A missing session may be recreated and the prompt retried once only before
  output, permissions, or other observable activity. Activity forbids replay.
- Pending conversation input is capped at 16 entries and 8,192 UTF-8 bytes per
  request. Each input keeps a stable transport identity through routing,
  injection, queueing, prompting, or failure.

The profile system prompt is placed in Codex `CODEX_CONFIG` as
`developer_instructions`, preserving other object keys. ACP v1 has no portable
system-role field; other providers receive the instruction in a separate text
block.

## Primary sources

- [ACP v1 overview](https://agentclientprotocol.com/protocol/v1/overview)
- [ACP transports](https://agentclientprotocol.com/protocol/v1/transports)
- [Initialization](https://agentclientprotocol.com/protocol/v1/initialization)
- [Session setup](https://agentclientprotocol.com/protocol/v1/session-setup)
- [Prompt turns](https://agentclientprotocol.com/protocol/v1/prompt-turn)
- [Tool calls and permissions](https://agentclientprotocol.com/protocol/v1/tool-calls)
- [ACP v1 mid-turn input discussion](https://github.com/orgs/agentclientprotocol/discussions/1220)
- [Claude 0.73.0 AIR implementation](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/air-extension.ts)
- [Claude 0.73.0 async tasks](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/async-tasks.ts)
