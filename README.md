<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Voice Activation

## What it does

Voice Activation is a native macOS menu-bar app for named assistant profiles,
wake phrases, push-to-talk commands, and voice-driven conversations with local
coding agents through Agent Client Protocol (ACP).

It transcribes an utterance, routes it to a direct executable or ACP provider,
and keeps the foreground application focused while capture and conversation
state remain visible. It has no Voice Activation server or account.

## Requirements

- macOS 15 or later
- Swift 6.2 or later
- Xcode Command Line Tools or Xcode

## Quick start

From the repository root:

```bash
make test
make run
```

The app bundle is written to `.build/VoiceActivation.app`. Voice Activation has
no Dock icon; use its menu-bar icon and grant Microphone and Speech Recognition
access when prompted.

Wait for **Ready**, say `computer`, then speak a query. The initial profile opens
the recognized text as a Google search. For clone, permission, signing, and
push-to-talk details, see [Getting started](docs/getting-started.md).

## Core capabilities

- Multiple named profiles, each with an icon, color, wake phrase, command or
  agent target, passive-wake toggle, and optional push-to-talk shortcut.
- Explicit direct-process arguments with literal or URL-encoded recognized text
  and no shell evaluation.
- Cursor, Codex, Claude, and custom ACP v1 providers with editable executable,
  working folder, system prompt, and permission policy.
- Focused Mac-context snapshots for ACP requests: one bounded snapshot per
  admitted utterance, enabled by default, with an explicit Accessibility action
  in Settings. Direct commands never receive this context.
- A non-activating, result-first conversation panel with native previews for
  generated images, PDFs, documents, and local resources; ordered turns,
  bounded voice follow-ups, per-input delivery state, provider-exposed thinking
  and tools, spoken permission choices, cancellation, retained output controls,
  and capability-gated ACP session restoration across application launches.
- Ordinary follow-up speech stays opaque agent input. The exact validated
  Claude ACP pin can add it to an active turn; Cursor, Codex, and unsupported
  providers retain it in a bounded FIFO for the next ordinary turn.
- Selectable GitHub-flavored Markdown responses with safe link handling and
  bounded HTTPS image loading; typed ACP results use the local preview shelf.
- Agent-authored spoken and display response channels. ACP v1 has no standard
  spoken channel, so current adapters receive an exact marker compatibility
  instruction and supporting providers may use optional namespaced metadata.
  Ordinary unmarked replies keep the existing visible Markdown and narration
  behavior.
- Optional macOS or ElevenLabs reply speech with a global default or per-profile
  voice, plus barge-in, activity cues, and profile-aware follow-ups. Spoken
  responses remain visible and copyable even when reply reading is disabled.
- Structured local diagnostics, Launch at Login, and signed SwiftPM app-bundle
  packaging.

## Privacy and safety

Passive wake recognition is forced on-device. Interactive command,
push-to-talk, and conversation capture may use Apple's normal speech service
policy. Voice Activation has no application server or account.

Direct commands and ACP providers launch as explicit processes without a shell.
They run with the signed-in user's access, and a provider may contact its own
services. Provider authentication stays with its CLI. The optional ElevenLabs
key stays in macOS Keychain.

Reply speech is derived only from agent-authored response text. Voice Activation
never synthesizes raw tool payloads, plans, thoughts, permissions, diagnostics,
or ACP frames. The macOS backend uses the local system synthesizer. Selecting
ElevenLabs sends only admitted response text to ElevenLabs for synthesis. Typed
spoken text remains visible in the conversation panel without being rewritten.

The app does not maintain a conversation-history database or audio archive. It
persists only bounded ACP session identifiers, compatibility fingerprints, and
identifier-only interrupted-work markers. Conversation content remains with the
provider. Diagnostics exclude continuity identifiers and fingerprints as well
as prompts, transcripts, credentials, provider content, audio, and Mac-context
snapshot values or content. See
[Privacy and security](docs/privacy-and-security.md) for the complete data,
persistence, and retention boundaries.

When focused Mac context is enabled, Voice Activation can send the selected ACP
provider a one-shot description of the focused app, window or document,
selection, and selected resource references. Accessibility is checked without
prompting during normal use; the system prompt appears only after choosing
**Enable Accessibility…** in Settings. Voice Activation does not persist or log
snapshot values or content; it records safe capture metadata only. The provider
may retain or replay submitted prompt blocks under its own session policy. See
[Privacy and security](docs/privacy-and-security.md) for the complete authority,
then [Configuration](docs/configuration.md),
[ACP agent harness](docs/agent-harness.md), and
[Troubleshooting](docs/troubleshooting.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Documentation index](docs/index.md)
- [Configuration reference](docs/configuration.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Privacy and security](docs/privacy-and-security.md)

## Development

```bash
make build
make test
make app
make check
```

See [Development](docs/development.md), [Testing](docs/testing.md), and
[Packaging](docs/packaging.md) for the contributor workflows and verification
matrix.

## License

Voice Activation is available under the [MIT License](LICENSE).
Copyright © 2026 Alexandru Ciobanu
([alex+git@ciobanu.org](mailto:alex+git@ciobanu.org)).
