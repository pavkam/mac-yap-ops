<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Agent conversations

Use an agent profile to hold a voice-driven conversation with a local ACP
provider. A conversation keeps one visible timeline and may contain several
sequential turns.

## Start a conversation

Trigger an agent profile by wake phrase or push-to-talk and speak the first
request. The recording overlay hands its screen and accent into a floating agent
panel. The panel accepts pointer input but does not become the key or main
window, so the foreground application keeps keyboard focus.

The trigger selects one profile for the lifetime of the conversation. Every
follow-up keeps that profile's agent session, identity, and reply voice; another
trigger or a Settings change cannot switch it mid-conversation.

The microphone remains active while the provider works, while a reply is read
aloud, and after the turn finishes. Passive wake resumes only after the
conversation ends.

## Read the timeline

The panel shows the initial request and one chronological Markdown timeline for
the whole conversation. Each work burst starts with one **Thinking** card,
including ACP startup. Provider-exposed reasoning, plans, and tool activity
collect inside that card. The next answer settles and collapses it; select the
card to inspect its retained details.

Responses render with a native GitHub-flavored Markdown parser, including
headings, nested and task lists, tables, block quotes, links, inline code, and
fenced code blocks. Text remains selectable. Agent-provided images are shown as
omitted and never trigger a network request; only user-clicked `http` and
`https` links can open externally.

Voice Activation displays only thought content the provider sends through ACP;
it does not claim access to private chain-of-thought. Token bursts publish to the
panel at most 20 times per second so streaming remains responsive without
rendering every fragment separately.

New activity follows the bottom while the view is already pinned there. A
deliberate upward scroll pauses automatic following; returning to the bottom
enables it again.

## Continue by voice or push-to-talk

Speak normally after the first request. A final recognition result or the
conversation-capture inactivity boundary submits the utterance as the next turn.
The profile's push-to-talk binding is another input method for the same
conversation. [Wake profiles](wake-profiles.md) owns the capture timing.

Speaking while a turn is still active cancels that work before the follow-up
starts. Recognized follow-ups wait in a bounded queue behind active cancellation
and work. If the queue is full, the panel shows a bounded notice and leaves the
current turn running. [Privacy and security](privacy-and-security.md) owns the
retention limit.

Speaking during narration stops playback and keeps the utterance in the normal
recognition path. Conversation capture requests Apple's best-effort input voice
processing to reduce speaker echo; unsupported devices continue with ordinary
capture.

## Resolve permissions

With **Ask every time**, the panel shows exactly the choices supplied by the
provider. Select one, say its displayed label, or use a standard spoken choice:

| Say | Preferred ACP option |
| --- | --- |
| `allow` | Allow once, then persistent allow. |
| `allow all` | Persistent allow, then allow once. |
| `deny` | Deny once, otherwise cancel. |
| `deny all` | Persistent deny, then deny once, then cancel. |

The decision applies to the oldest visible request and collapses it immediately.
Longer phrases remain normal follow-ups. Cancelling a turn settles every pending
permission request exactly once before the process is torn down.

## Stop a turn or end the conversation

**Stop turn** cancels only the current provider work. The panel enters a
cancelling phase immediately, the live conversation microphone remains
available, and another request can start the next turn.

**End conversation** cancels active work when necessary, closes conversation
recognition, and returns to passive wake after the normal cooldown. Saying only
`cancel`, `stop`, or `dismiss` has the same whole-conversation effect. When
spoken replies are enabled, Voice Activation acknowledges spoken cancellation
with “Stopped.”

Retired turns cannot update the current panel. Run, turn, request, and permission
identities reject late callbacks and stale pointer actions.

## Minimize, restore, close, and delete

Drag the provider header to move the expanded panel. The minimize button morphs
it into a movable live-status pill below the menu bar at the screen's top-right.
Restoring returns to the saved expanded location, adjusted only to stay visible
on the current screen.

After the conversation ends:

- **Close** hides the panel but keeps its bounded presentation available from
  **Open** in the menu.
- **Delete** hides the panel and releases that retained presentation from
  memory.

Starting a new conversation replaces the previously retained presentation.

## Listen to replies

Profiles can inherit the app-wide reply voice, disable narration, or select an
explicit macOS or ElevenLabs voice. The resolved backend and voice are pinned at
conversation start. An explicit profile voice remains enabled even when global
inherited narration is off. ElevenLabs credentials are global and Keychain-backed.

When narration is active, Voice Activation removes Markdown formatting and
queues user-facing agent text while it streams. Complete sentences start
immediately. An unfinished progress message is flushed when work moves to
thought, tool, plan, or permission activity, with a 350 ms fallback when no
semantic boundary arrives. ElevenLabs prepares at most two complete segments
concurrently while preserving playback order. A failed backend request falls
back to the automatic macOS voice for that segment.

The thinking cue begins when the request is accepted, including ACP startup, and
continues during cloud preparation. It pauses for permissions and audible
narration, then resumes after its delay if work continues. Tool start,
completion, and failure have distinct deduplicated cues.

## Copy retained output

**Copy output** includes the initial request, user-visible response Markdown
separated by turn, and bounded diagnostics. Provider thought updates remain
inspectable in the timeline but are excluded from the response section.

Copyable output, diagnostics, tools, timeline text, and visible activity are all
bounded. Truncation produces an explicit marker instead of silently growing
memory. See [Privacy and security](privacy-and-security.md) for the canonical
limits.

## Recover after provider failure

Each profile reuses its own initialized ACP session while its configuration is
unchanged. Voice Activation keeps a bounded least-recently-used set of idle
profile sessions and evicts an idle one under pressure.

If a provider forgets a cached session before producing output or requesting
permission, Voice Activation creates a new process and retries that prompt once.
The panel reports that earlier provider context was lost. A prompt is never
replayed after observable activity because doing so could repeat tool actions.

If a connection fails after useful output, the output remains visible and the
conversation microphone stays live. The next follow-up creates a fresh provider
session.

Startup also has a bounded deadline and one fresh-process retry. A second stall
fails visibly instead of leaving the panel on **Starting the agent**. See
[ACP agent harness](agent-harness.md) for the session, retry, and timeout
contracts.

## Related guides

- [Agent providers](agent-providers.md)
- [Configuration reference](configuration.md)
- [ACP agent harness](agent-harness.md)
- [Sound design](sound-design.md)
- [Troubleshooting](troubleshooting.md)
