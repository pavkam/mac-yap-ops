<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Privacy and security

Voice Activation has no application server or account. It runs as the signed-in
macOS user, keeps ordinary configuration on the Mac, and communicates only with
services or processes needed for the action the user selected.

## Data boundaries

| Action | Data that crosses the boundary | Destination |
| --- | --- | --- |
| Passive wake listening | Microphone audio | Apple Speech, forced to on-device recognition |
| Command, conversation, or push-to-talk capture | Microphone audio | Apple Speech; these modes allow the recognizer's normal macOS policy and are not guaranteed to remain on-device |
| Direct command | Recognized command text | The configured executable, as one or more explicit arguments |
| Agent request | Recognized request and saved profile instructions; when enabled, one bounded Mac app/window/document/selection block and one resource-link block per selected resource | The configured local ACP process |
| ElevenLabs reply speech | Formatted user-facing agent reply text | `api.elevenlabs.io` over HTTPS |

The local ACP process may read files, modify the working folder, or contact its
own services according to that provider's implementation and authentication.
Voice Activation does not proxy, inspect, or replace those provider policies.

Only user-facing agent reply text is eligible for speech synthesis. Thoughts,
plans, tool payloads, permissions, diagnostics, code-block contents, prompts,
and raw ACP messages are excluded. macOS speech stays local to the system speech
synthesizer; selecting ElevenLabs sends the eligible spoken segment to that
service.

## Direct-process trust

Command and agent targets run directly through `Foundation.Process` with an
absolute executable and an explicit argument array. Voice Activation does not
invoke a shell, expand wildcards or environment syntax, or interpret recognized
punctuation as shell code.

That removes shell evaluation; it does not make an executable safe. A configured
command receives the recognized text, and an ACP provider runs with the current
macOS user's access. Treat executable paths, working folders, custom URL schemes,
and provider permission policies as trusted configuration.

## What is persisted

- `UserDefaults` stores application settings and encoded wake profiles. A
  profile can contain its wake phrase, shortcut, target executable, arguments,
  working folder, permission policy, and system prompt. Saved speech choices and
  the ElevenLabs Voice ID are configuration too.
- macOS Keychain stores the optional ElevenLabs API key as a device-local
  generic-password item. It is never stored in preferences or process arguments.
- The structured diagnostic trace is stored under
  `~/Library/Logs/VoiceActivation/` and rotates locally.
- One strict schema-1 `UserDefaults` value stores identifier-only ACP
  continuity: profile/session bookmarks, a provider compatibility fingerprint,
  access ordinals, and exact work markers made from profile, session,
  occurrence, optional turn/provider-task identifiers, and local lifecycle
  state. It contains no conversation content or authorization.

Preferences and diagnostic files use the signed-in user's normal filesystem
protection; Voice Activation does not add application-level encryption to them.
Do not put credentials in a profile system prompt, executable argument, or
working-folder path.

## What remains in memory

Live transcripts, queued follow-ups, agent output, reasoning exposed by the
provider, tool state, permission requests, narration text, synthesized audio,
reusable ACP processes, and Mac-context snapshot values are held only for the
active application process. Opaque ACP bookmarks can restore provider-owned
context or bounded replay, but Voice Activation does not maintain a durable
conversation-history database or write captured audio to disk. The provider
owns the actual conversation content and its retention.

Focused Mac context is on by default for admitted ACP requests and can be
disabled in Settings; direct commands never receive it. The normal status check
does not prompt for Accessibility. Only **Enable Accessibility…** can request
that grant. Until then, a request can carry frozen app identity but not protected
window, document, selection, or resource values. Voice Activation does not
persist or log those snapshot values or content, though it records safe capture
metadata. A provider may independently retain or replay submitted context blocks
as part of its session or account history; use the provider's controls when that
matters.

An initial request begins only after an explicit matched wake phrase or a
profile's push-to-talk release. An active ACP conversation may accept its own
follow-ups; Voice Activation does not continuously observe the Mac.

Closing a completed panel hides its retained presentation. Deleting it releases
that presentation; starting another conversation replaces it. **Copy output**
writes the bounded request, response, and diagnostics to the system clipboard,
after which clipboard retention is owned by macOS and any clipboard manager.

An ACP provider may independently retain sessions, files, submitted prompt
blocks, or account history. Use that provider's controls when its retention
matters.

## Retention bounds

User-visible conversation state is bounded in memory:

| Retained state | Limit |
| --- | ---: |
| Copyable response output | 512 KiB |
| Copyable diagnostics | 16 KiB |
| Timeline text | 64 KiB |
| Timeline entries | 256 |
| Current tools | 32 |
| Details in one thinking group | 128 |
| Lifecycle notices | 16 |
| Pending recognized follow-ups | 16 |
| ACP session bookmarks | 64 |
| ACP interrupted-work markers | 64 |
| One persisted ACP identifier | 4 KiB UTF-8 |
| Complete continuity envelope | 512 KiB encoded JSON |

When presentation text or activity is removed to satisfy a bound, the panel
shows an omission marker or count. Narration queues, provider sessions, ACP
frames, event delivery, standard-error tails, and permission collections have
separate protocol-level bounds documented in
[ACP agent harness](agent-harness.md).

A 65th bookmark evicts the deterministic least-recently-used bookmark. A 65th
unique work marker is rejected atomically. Unknown schema versions or fields,
malformed JSON, duplicates, invalid identifiers or fingerprints, excessive
records, and oversized continuity data are quarantined as empty in memory. A
read does not rewrite quarantined bytes; a later explicit valid mutation
replaces them.

## Diagnostics and redaction

The app records local operational metadata such as categories, event names,
timestamps, identifiers, counts, durations, provider kinds, configured
executable and working-folder paths, and error types. It must not record prompts,
transcripts, credentials, authorization values, raw provider content, response
text, audio, or Mac-context snapshot values or content (including app names,
bundle identifiers, window titles, document URLs, selections, and resource
names).

Continuity events additionally exclude stored session, turn, provider-task,
occurrence, restoration-token, and fingerprint values. They retain only fixed
operation and activation categories, capability booleans, counts, error types,
and timings. Provider-owned replay remains content and is never diagnostic data.

Fields whose names suggest sensitive content are replaced with `<redacted>` at
the file boundary. That is defense in depth, not a content filter: paths and
other operational metadata can still reveal usernames or project names. Review
and minimize a trace before sharing it. Voice Activation does not upload the
trace automatically.

## Security limitations

- The app is not a sandbox around direct commands or ACP providers.
- Provider authentication and remote data handling belong to the provider CLI.
- Apple Speech and ElevenLabs data handling are governed by their respective
  platform or service policies when those boundaries are used.
- Voice Activation does not provide remote administration, account isolation,
  encrypted conversation archives, or a permission model beyond the choices
  exposed by the configured ACP provider.

## Related guides

- [Command targets](command-targets.md)
- [Agent providers](agent-providers.md)
- [Agent conversations](agent-conversations.md)
- [Diagnostics](diagnostics.md)
- [ACP agent harness](agent-harness.md)
