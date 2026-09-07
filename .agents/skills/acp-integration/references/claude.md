<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Claude Agent ACP adapter

Validated from the official adapter repository, its pinned release, npm
metadata, the cached package, and the installed CLIs on 2026-09-05.

## Project contract

| Item | Value |
| --- | --- |
| Preset executable | `npx` |
| Arguments | `-y @agentclientprotocol/claude-agent-acp@0.73.0` |
| ACP adapter pin | `0.73.0` |
| Required Node version | `>=22` |
| Adapter executable | `claude-agent-acp` |

The native `claude` CLI is not the configured ACP server and had no ACP
subcommand in the validated environment. The adapter is a stdio server built on
the Claude Agent SDK. Provider authentication remains outside YapOps.

The adapter advertises features beyond YapOps's current client,
including MCP, session loading, terminals, slash commands, and extensions.
Advertised support does not authorize sending optional requests: add client
behavior only after capability gating, lifecycle design, bounds, and tests.

Claude's permission extension adds optional `_meta` presentation data while the
standard `session/request_permission` request remains authoritative. Preserve
option IDs exactly, settle cancellation, and do not infer persistent provider
effects merely from a label or option kind.

## AIR async-task contract

The pinned adapter's JetBrains AIR extension is nonstandard ACP. YapOps enables it only when preset, initialized package name, exact version
`0.73.0`, client advertisement, and provider advertisement all match AIR version
1 with `asyncTasks`. It then accepts typed spawn/progress/state events between
turns and may send `_session/async_task/stop` with exact opaque IDs.

The adapter process owns the task. Quitting YapOps or losing that
process marks identifier-only work interrupted; it does not prove task survival.
Any pin upgrade must review the tagged AIR sources, rerun capability, decoder,
and connection fixtures, then rerun the initialize-only probe before changing
the allowlist.

## Host-owned steering contract

The pinned 0.73.0 adapter advertises top-level
`_meta.steering.supported: true` and accepts `_session/steering`. YapOps enables that extension only when the current process's `initialize`
result also reports the exact package name and version and the profile preset is
Claude. The request supplies `idleBehavior: "promptRequired"`, which keeps idle
input locally owned instead of starting an unowned turn.

`injected` means the active turn accepted the opaque input. `promptRequired`
means YapOps may retain it for one normal `session/prompt`. A legacy
`startedNewTurn`, `failed`, unknown or malformed result, cancellation, or
transport failure is ambiguous: close the connection and never replay the
utterance automatically. Tagged-source fixtures prove this steering contract;
an initialize-only probe proves only the current handshake and bounded
capability shapes, not model behavior.

The project pin remains authoritative. The npm `latest` tag was `0.75.1` on the
validation date. Its Node requirement and dependency graph can move, so a pin
upgrade needs release review, tests, and a handshake.

## Manual validation

```bash
.agents/skills/acp-integration/scripts/probe-local-clients.sh claude
.agents/skills/acp-integration/scripts/probe-local-clients.sh claude --online
```

The default probe uses npm's offline cache and sends only `initialize`. `--online`
also reads current registry metadata; it still does not prompt a model.

## Primary sources

- [Claude Agent ACP adapter](https://github.com/agentclientprotocol/claude-agent-acp)
- [Pinned v0.73.0 release](https://github.com/agentclientprotocol/claude-agent-acp/releases/tag/v0.73.0)
- [Pinned v0.73.0 steering implementation](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/acp-agent.ts)
- [Pinned v0.73.0 AIR negotiation](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/air-extension.ts)
- [Pinned v0.73.0 async tasks](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/async-tasks.ts)
- [Permission extension](https://github.com/agentclientprotocol/claude-agent-acp/blob/main/docs/permission-extension.md)
