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

The microphone accepts follow-ups while the provider works and after a normal
turn finishes. It pauses during spoken output and stays off after **Stop turn**.
Passive wake resumes only after the conversation ends.

## Read the timeline

The panel shows the initial request and one chronological Markdown timeline for
the whole conversation. Each work burst starts with one **Thinking** card,
including ACP startup. Provider-exposed reasoning, plans, and tool activity
collect inside that card. The next answer settles and collapses it; select the
card to inspect its retained details.

The initiating profile's name, icon, and accent identify the conversation in
the menu, panel header, compact pill, and response cards. The ACP provider name
is implementation detail except while reporting connection progress.

Responses render with a native GitHub-flavored Markdown parser, including
headings, nested and task lists, tables, block quotes, links, inline code, and
fenced code blocks. Text remains selectable. HTTPS Markdown images load directly
from their remote host into a bounded picture surface; failed or unsupported
images show an unavailable state. Only user-clicked `http` and `https` links can
open externally.

YapOps displays only thought content the provider sends through ACP;
it does not claim access to private chain-of-thought. Token bursts publish to the
panel at most 20 times per second so streaming remains responsive without
rendering every fragment separately.

New activity follows the bottom while the view is already pinned there. A
deliberate upward scroll pauses automatic following; returning to the bottom
enables it again.

## Use generated results

Generated images, PDFs, documents, and resource links appear in a result shelf
immediately after the request, ahead of the conversation details. Each card uses
a native image or Quick Look preview when local data is available and otherwise
shows a quiet file-type treatment. Preview work stays off the main actor and
never downloads remote content.

Use **Open** for an embedded result, local file, or `http`/`https` resource.
Local linked files also offer **Reveal in Finder**. Embedded results are written
only when opened, into an owner-only temporary run directory. Closing preserves
them with retained output; deleting the result, replacing the run, or quitting
removes app-owned temporary files.

## Continue by voice or push-to-talk

Speak normally after the first request. A final recognition result or the
conversation-capture inactivity boundary submits the utterance as the next turn.
The profile's push-to-talk binding is another input method for the same
conversation. [Wake profiles](wake-profiles.md) owns the capture timing.

Speaking while a turn is still active offers the follow-up through the provider's
validated input route or queues it for the next turn. Recognized follow-ups wait
in a bounded queue behind active cancellation and work. If the queue is full,
the panel shows a bounded notice and leaves the current turn running. [Privacy and security](privacy-and-security.md) owns the
retention limit.

Hands-free listening pauses while replies are queued or playing, then resumes
with a fresh microphone capture when speech finishes. This prevents speaker
output from becoming another request, including on devices without reliable echo
cancellation. Press and hold push-to-talk to interrupt narration and speak;
**Stop turn** and **End conversation** remain available in the panel.

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

**Stop turn** cancels current provider work and narration, discards queued
follow-ups, and clears unfinished microphone input. Discarded follow-ups show
**Cancelled before next turn**. The panel stays visible as **Paused · Microphone
off** after cancellation settles. Choose **Resume listening** or use push-to-talk
to continue this conversation. Empty push-to-talk capture leaves it paused.
**Stop listening** offers the same pause when the provider is already idle.

**End conversation** cancels active work when necessary, closes conversation
recognition, and returns to passive wake after the normal cooldown. Saying only
`cancel`, `stop`, or `dismiss` has the same whole-conversation effect. When
spoken replies are enabled, YapOps acknowledges spoken cancellation
with “Stopped.”

Retired turns cannot update the current panel. Run, turn, request, and permission
identities reject late callbacks and stale pointer actions.

## Minimize, restore, close, and delete

Drag the profile header to move the expanded panel. The minimize button morphs
it into a movable live-status pill below the menu bar at the screen's top-right.
Restoring returns to the saved expanded location, adjusted only to stay visible
on the current screen.

After the conversation ends:

- **Close** hides the panel but keeps its bounded presentation available from
  **Open** in the menu.
- **Delete** hides the panel and releases that retained presentation from
  memory.

Starting a new conversation replaces the retained presentation and creates a new
provider session. End the current conversation before triggering the profile
again. Reopening a minimized or hidden panel keeps its existing conversation.

## Listen to replies

Profiles can inherit the app-wide reply voice, disable narration, or select an
explicit macOS or ElevenLabs voice. The resolved backend and voice are pinned at
conversation start. An explicit profile voice remains enabled even when global
inherited narration is off. ElevenLabs credentials are global and Keychain-backed.

**Test voice** in either the global default or an individual profile uses the
same backend and credential path as conversation narration. The control shows
preparing, stop, success, and actionable failure states only on the row that
started the preview. A 402 response means ElevenLabs needs credits or payment;
an invalid or missing API key is a 401 response.

When narration is active, YapOps removes Markdown formatting and
queues user-facing agent text while it streams. Complete sentences start
immediately. An unfinished progress message is flushed when work moves to
thought, tool, plan, or permission activity, with a 350 ms fallback when no
semantic boundary arrives. Image labels and destinations are silent, so reply
speech never narrates a picture URL. ElevenLabs prepares at most two complete
segments concurrently while preserving playback order. A failed backend request
falls back to the automatic macOS voice for that segment.

The thinking cue begins when the request is accepted, including ACP startup, and
continues during cloud preparation. It pauses for permissions and audible
narration, then resumes after its delay if work continues. Tool start,
completion, and failure have distinct deduplicated cues.

## Copy retained output

**Copy output** includes the initial request, user-visible response Markdown
separated by turn, result names and linked URIs, and bounded diagnostics. It
never includes embedded result bytes. Provider thought updates remain
inspectable in the timeline but are excluded from the response section.

Copyable output, diagnostics, tools, timeline text, and visible activity are all
bounded. Truncation produces an explicit marker instead of silently growing
memory. See [Privacy and security](privacy-and-security.md) for the canonical
limits.

## Recover after provider failure

Follow-ups within a conversation reuse its initialized ACP session. Starting a
new conversation creates a fresh session without loading saved history or
previous provider context. If the profile still has active background tasks,
finish or stop those tasks first; YapOps preserves their session and explains
why a new conversation cannot start yet.

YapOps keeps a bounded least-recently-used set of profile sessions and evicts
an idle one under pressure.

If a provider forgets a cached session before producing output or requesting
permission, YapOps creates a new process and retries that prompt once.
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
