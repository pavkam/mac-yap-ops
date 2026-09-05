<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# ACP agent harness

This reference defines Voice Activation's technical contract with local Agent
Client Protocol (ACP) version 1 providers. Use it for transport, initialization,
session, prompt, permission, cancellation, recovery, and delivery behavior.

Provider installation belongs in [Agent providers](agent-providers.md). The
user-visible panel and voice workflow belong in
[Agent conversations](agent-conversations.md).

## Contract and ownership

`ACPAgentRunner` owns reusable provider processes, initialized sessions, active
turn serialization, cancellation deadlines, recovery, and least-recently-used
cache eviction. `ACPClientConnection` owns JSON-RPC request identity, one ACP
session, one active prompt, permission settlement, update decoding, and terminal
connection state. `ACPProcessTransport` owns direct process launch and the three
standard streams.

One unchanged profile configuration maps to one cached process and session. A
conversation may submit several sequential prompts to that session, but a
connection never runs two prompts concurrently.

## Process and transport

The runner launches the configured absolute executable with its explicit
argument array and working directory. It never invokes a shell. Provider
authentication remains in the provider CLI's ambient configuration.

ACP uses UTF-8 JSON-RPC 2.0 over standard input and output:

- exactly one compact JSON value per newline-delimited frame;
- no embedded literal newline bytes inside a frame;
- nonblocking writes to child standard input;
- independently drained standard output and standard error; and
- standard error treated only as diagnostics, never as protocol input.

The transport disables `SIGPIPE` for child input. Termination closes the parent
write side, marks an exited process unavailable immediately, drains current
output for a bounded grace period, then closes inherited pipe handles and fails
pending requests. Standard-error decoding is incremental, so a multibyte UTF-8
sequence split across reads is not corrupted.

Incoming request identifiers preserve ACP's full `int64 | string | null` union.
Permission responses therefore use exactly the wire identifier sent by the
provider instead of converting large integers through floating point.

## Initialize and authenticate

Startup sends `initialize` with:

- `protocolVersion: 1`;
- Voice Activation implementation metadata; and
- no filesystem, terminal, terminal-authentication, or elicitation capability.

The provider must select version 1. Any other version closes the connection and
fails with an incompatibility error.

Voice Activation then sends `session/new` with the profile's absolute working
directory and an empty MCP server list. If session creation returns
`auth_required`, the client retains at most eight bounded advertised method
names, closes cleanly, and directs the user to authenticate with the provider
CLI. It does not select a method or emulate an interactive terminal.

## Create and cache sessions

The runner caches at most four idle profile sessions. Reusing a profile moves
its record to the most-recently-used end. When a fifth profile needs a session,
the least recently used idle record is closed before the new connection is
retained. An active record is never evicted underneath its turn.

Changing a profile's agent configuration discards only that profile's cached
record. Application shutdown closes every connection and terminates every
retained process.

Session identifiers are opaque UTF-8 strings bounded to 4 KiB. An update for a
different session identifier is ignored and recorded as a bounded diagnostic;
it never enters the current conversation.

## Submit prompts and receive updates

Every initial request and follow-up becomes one `session/prompt`. The prompt
contains two text blocks in order:

1. Voice Activation's Markdown presentation instruction.
2. The untouched recognized request.

The instruction asks for user-facing GitHub-flavored Markdown, at most one short
progress sentence per work batch, and no narration of individual tool calls or
routine intermediate results.

For Codex, a profile system prompt is merged into the adapter's existing
`CODEX_CONFIG` as `developer_instructions` before process launch. It is not
duplicated as user text. ACP v1 has no portable system-role field, so other
providers receive the profile instruction in the harness block before every
request.

`session/update` messages stream until the prompt response supplies a stable
stop reason. The client converts all stable ACP v1 update discriminators into
typed events:

- user and agent message chunks;
- provider-exposed thought chunks;
- tool calls and tool-call updates;
- complete plan replacements;
- available commands;
- mode and configuration changes;
- session metadata; and
- usage updates.

Unknown update types and provider extensions do not end the turn. They become
bounded metadata diagnostics without retaining raw provider payloads. A
structurally invalid stable update fails the connection instead of guessing at
its meaning.

Prompt completion does not publish success until every accepted event has
drained through both delivery stages. This preserves wire order even when the
consumer is slower than the provider.

## Resolve permissions

`session/request_permission` is an inbound JSON-RPC request. Each decoded
permission keeps:

- the exact wire request identifier;
- the active connection and opaque turn token;
- the tool identity and bounded description; and
- only the provider-supplied option identifiers, labels, and semantic kinds.

Automatic policies choose only an option the provider supplied. **Ask every
time** publishes the choices and suspends that request without blocking receipt
of other protocol messages. A selection is accepted only while its connection,
turn token, and request still match.

A provider may reuse a wire request identifier after its earlier request has
settled. The opaque turn token prevents a delayed click or spoken decision from
resolving that later request. Cancelling or closing the connection answers every
pending permission with a cancelled outcome exactly once.

The client retains at most 32 simultaneous unanswered permissions. Each may
offer at most 64 options. An excess request is cancelled without admitting its
untrusted content.

## Cancel work

Cancellation stops new event admission and settles permissions before process
teardown. If the prompt frame has been published and its response has not
arrived, the client sends `session/cancel` for the active session.

The runner waits up to two seconds for the provider to finish with
`stopReason: cancelled`. Another stop reason after cancellation invalidates the
connection. A provider that does not settle in time is terminated and removed
from the session cache.

If cancellation arrives while the prompt write is in flight, the client lets
that single serialized write finish before sending `session/cancel`. If the
prompt response already completed, it does not send a cancellation for finished
work.

Forced cancellation discards queued delivery after invalidation. Natural prompt
completion drains delivery. At most a callback already in flight can finish
after forced discard, and downstream run and turn identities reject it.

## Recover or discard a session

A cached session is revocable provider state, not durable application state. A
typed missing-session error may create a fresh process and replay the prompt
once only when the provider has emitted no session activity and requested no
permission. The conversation receives a context-loss notice.

Ambiguous errors, a second missing-session failure, and failures after observable
activity are never replayed. The failed record is discarded. Output already
delivered remains visible, and the next turn starts a fresh connection.

Connection initialization has a 12-second deadline. A stall terminates that
process and retries startup once with a new process. A second stall fails with a
bounded error.

After a successful prompt response, the runner keeps a 25 ms settlement window
for a child process that exits immediately and a 500 ms stream-drain grace for
current-generation output. These windows preserve cross-pipe diagnostics without
allowing a dead process to remain reusable.

Malformed JSON, an oversized or unterminated frame, incompatible protocol,
unexpected EOF, non-zero process exit, JSON-RPC error, or delivery overflow
makes the connection terminal. A terminal connection is never returned to the
cache.

## Bound untrusted input and delivery

| Boundary | Limit | Overflow behavior |
| --- | ---: | --- |
| Profile system prompt | 8 KiB UTF-8 | Reject configuration. |
| Recognized ACP prompt | 8 KiB UTF-8 | Reject before writing. |
| One newline-delimited frame | 1 MiB | Fail the connection. |
| Opaque remote identifier | 4 KiB UTF-8 | Reject the event or response. |
| Remote diagnostic summary | 256 bytes UTF-8 | Retain a bounded prefix. |
| Advertised authentication methods | 8 | Ignore additional names. |
| Simultaneous pending permissions | 32 | Cancel the excess request. |
| Options in one permission | 64 | Cancel the request. |
| Entries in one plan update | 64 | Retain a bounded plan. |
| Pending output delivery | 512 KiB UTF-8 | Discard oldest valid UTF-8 and publish a typed notice. |
| Pending diagnostic delivery | 16 KiB UTF-8 | Discard oldest valid UTF-8 and publish a typed notice. |
| Pending control delivery | 512 KiB | Fail explicitly rather than lose required control. |
| Pending delivery entries | 256 | Evict lossy text first; fail if required control still exceeds the cap. |
| Retained process standard error | 16 KiB UTF-8 | Keep the newest valid tail. |
| Cached idle profile sessions | 4 | Close the least recently used idle record. |

The frame limit bounds parser input. Decoding one accepted frame may
transiently allocate its JSON representation before typed normalization applies
the delivery limits. Control text is bounded before queue admission, so changing
event kinds or identifiers cannot evade the byte and entry caps.

## Compatibility boundaries

Voice Activation implements stable ACP v1 only. It does not advertise terminal,
filesystem, MCP, elicitation, or terminal-authentication capabilities.

Unknown inbound requests receive JSON-RPC `method not found`. Cursor's blocking
question and plan-approval extensions receive their documented cancelled result
and a bounded diagnostic instead of remaining pending forever. Unknown
notifications are ignored after bounded metadata is recorded.

The app does not claim to expose private chain-of-thought. It presents only
typed content that the provider emits through ACP.

## Protocol references

- [ACP overview](https://agentclientprotocol.com/protocol/overview)
- [ACP standard I/O transport](https://agentclientprotocol.com/protocol/transports)
- [Prompt lifecycle](https://agentclientprotocol.com/protocol/prompt-turn)
- [Session setup](https://agentclientprotocol.com/protocol/v1/session-setup)
- [Tool permissions](https://agentclientprotocol.com/protocol/tool-calls)
- [Cursor ACP server](https://prod.cursor.com/docs/cli/acp)
- [Codex ACP adapter](https://github.com/agentclientprotocol/codex-acp)
- [Claude ACP adapter](https://github.com/agentclientprotocol/claude-agent-acp)

## Related guides

- [Agent providers](agent-providers.md)
- [Agent conversations](agent-conversations.md)
- [Concurrency and lifecycle](concurrency-and-lifecycle.md)
- [Privacy and security](privacy-and-security.md)
- [Diagnostics](diagnostics.md)
