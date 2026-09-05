<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Agent providers

Configure a wake profile to start Cursor, Codex, Claude, or another local Agent
Client Protocol (ACP) version 1 process. Voice Activation launches the provider
directly and leaves authentication with its CLI.

## Before you begin

Install the provider or adapter and complete its normal command-line login. The
provider must expose stable ACP v1 over standard input and output.

In Settings, edit a profile and change **Target** to **Agent**. A fresh agent
target selects the first installed preset it can detect in this order: Cursor,
Codex, then Claude. Every suggested field remains editable.

## Choose a preset

| Provider | Executable | Adapter arguments |
| --- | --- | --- |
| Cursor | `cursor-agent` | `acp` |
| Codex | `npx` | `-y`, `@agentclientprotocol/codex-acp@1.8.0` |
| Claude | `npx` | `-y`, `@agentclientprotocol/claude-agent-acp@0.73.0` |
| Custom | User-selected absolute path | User-selected explicit arguments |

Codex and Claude adapter versions are pinned so an upstream release cannot
silently change the runtime contract. Change a pin only with the provider probe
and ACP verification matrix described in the project agent guidance.

## Find the executable

Preset selection and **Detect** resolve a command name to an executable file.
Voice Activation searches, in order:

1. The app process's inherited `PATH`.
2. `/opt/homebrew/bin` and `/usr/local/bin`.
3. `/Applications/ChatGPT.app/Contents/Resources`.
4. `~/.local/bin`.
5. Installed NVM Node `bin` directories, newest version first.

Finder-launched apps do not inherit an interactive shell's complete environment,
so a command that works in Terminal may still require detection or explicit file
selection. Use the folder button to choose the executable directly when needed.

The saved executable path must be absolute and runnable. Detection is a setup
convenience; the saved path and argument list remain authoritative.

## Choose a working folder

Select the absolute project directory the provider should use. Voice Activation
passes it as the process working directory and in ACP `session/new`. It does not
infer a repository from the current foreground application.

The directory must exist when the provider starts. Provider-specific access to
files below or outside that directory still depends on the provider and its
permission model.

## Set the permission policy

| Policy | Default response |
| --- | --- |
| Ask every time | Present every provider-supplied option for an explicit choice. |
| Allow once | Prefer `allow_once`; fall back to an offered persistent allow option. |
| Always allow | Prefer `allow_always`; fall back to an offered one-shot allow option. |
| Deny once | Use an offered one-shot rejection; otherwise cancel the request. |
| Always deny | Prefer persistent rejection, then one-shot rejection, then cancellation. |

Voice Activation never invents a permission the provider did not offer. With
**Ask every time**, choose an option in the panel or answer the oldest visible
request by voice. See [Agent conversations](agent-conversations.md).

## Add a profile system prompt

The optional system prompt is bounded profile configuration. Use it for stable
instructions such as response style, project priorities, or safety constraints,
not for a one-time task. [ACP agent harness](agent-harness.md) owns the exact
prompt limit and rejection behavior.

For Codex, Voice Activation merges the prompt into the adapter's `CODEX_CONFIG`
as `developer_instructions` before launch. Other ACP v1 providers receive it in
the harness instruction block before each recognized request because ACP v1 has
no portable system-role field.

Every provider also receives Voice Activation's Markdown presentation contract.
It asks for user-facing GitHub-flavored Markdown and one short progress sentence
per work batch instead of narration for individual tool calls.

## Authenticate with the provider CLI

Voice Activation inherits the launch environment but never asks for, copies, or
persists provider API keys. Authenticate with the provider's own CLI before
using the profile.

If ACP session creation returns `auth_required`, the conversation shows the
provider-advertised method names and directs you back to the provider CLI. Voice
Activation does not guess among multiple methods or emulate an interactive
terminal login.

The optional ElevenLabs key used for spoken replies is independent of agent
authentication and stays in macOS Keychain.

## Configure a custom ACP process

Choose **Custom**, then supply:

- a display name;
- an absolute executable path;
- one row per direct process argument;
- an absolute working folder;
- a permission policy; and
- an optional bounded system prompt.

Voice Activation does not invoke a shell, expand environment syntax, or quote
arguments. The custom process must speak newline-delimited ACP v1 JSON-RPC on
standard input and output; standard error is reserved for bounded diagnostics.

## Related guides

- [Configuration reference](configuration.md)
- [Agent conversations](agent-conversations.md)
- [ACP agent harness](agent-harness.md)
- [Privacy and security](privacy-and-security.md)
