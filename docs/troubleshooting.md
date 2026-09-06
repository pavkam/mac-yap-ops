<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Troubleshooting

Start with the visible symptom, then use the structured trace when the suggested
check does not identify the boundary.

## Collect the relevant diagnostics

Follow the active trace while reproducing the issue once:

```bash
voice_log_path="$HOME/Library/Logs/VoiceActivation/voice-activation.jsonl"
tail -f "$voice_log_path" | jq .
```

Do not share the raw file without reviewing it. See [Diagnostics](diagnostics.md)
for correlation, timing fields, rotation, and safe extraction.

## The menu-bar icon is missing

Voice Activation has no Dock icon. Check the right side of the menu bar, then
confirm and relaunch the built application:

```bash
pgrep -fl VoiceActivation
open .build/VoiceActivation.app
```

## The status remains Starting

**Starting** means listening is enabled but speech recognition is not ready.
Complete both the Microphone and Speech Recognition prompts. If access was
denied, enable it in **System Settings > Privacy & Security**, quit Voice
Activation, and launch it again.

## Passive listening reports an on-device error

The selected locale has no on-device speech recognizer on this Mac. Choose
another Apple locale identifier in Settings. Passive wake listening is
deliberately unavailable without on-device recognition.

## Capture ends without running a command

- Begin with a saved wake phrase; text before the phrase does not match.
- Wait for **Capturing**, then speak within the initial five-second window.
- A capture containing only `cancel`, `stop`, or `dismiss` is discarded.
- Check the menu error after capture and correlate the recognition generation in
  the trace.

Capture timing and cancellation rules are in
[Wake profiles](wake-profiles.md).

## A custom wake phrase does not trigger

- Confirm that exact profile is enabled in the menu.
- Use at least one letter or number; punctuation-only phrases are rejected.
- Save Settings so the new phrase reaches contextual recognition vocabulary.
- Test with the phrase at the beginning of the utterance. Longer, distinctive
  phrases usually beat acoustically ambiguous ones.

## The recording overlay is missing

The overlay appears only during matched wake capture or while push-to-talk is
held, not during passive listening. Confirm the menu reaches **Capturing**. On
multiple displays it appears on the pointer's screen when capture begins.

The overlay is intentionally non-activating, so keyboard focus remains with the
foreground application. Its close button discards the capture.

## A direct command does not run

Confirm the executable path is absolute and runnable and that at least one
argument contains `{text}` or `{urlText}`. A non-zero exit status becomes a
visible error. Standard input, output, and error are discarded, so reproduce a
new command and its arguments directly in Terminal.

See [Command targets](command-targets.md) for expansion and shell-safety rules.

## An agent profile does not start

- Confirm the executable and working folder are absolute and still exist. Use
  **Detect** or select the executable when a Finder-launched app cannot see the
  shell's full `PATH`.
- Complete the provider CLI's normal login in Terminal. Voice Activation does
  not collect provider credentials.
- Confirm the process supports stable ACP v1. Protocol mismatch, malformed
  frames, and oversized data fail visibly.
- If **Starting the agent** persists, wait for the startup deadline and one
  automatic fresh-process retry; the second stall becomes an error.

Provider preset and authentication details are in
[Agent providers](agent-providers.md).

## An agent lacks focused Mac context

Open **Settings… > Mac context** and confirm **Include focused Mac context in
agent requests** is on, then **Save Settings**. It defaults to on, but it only
applies to ACP agent requests; direct commands are intentionally unchanged.

The displayed Accessibility status refreshes without prompting. If it says
**Accessibility not authorized**, choose **Enable Accessibility…** and complete
macOS's prompt. Voice Activation never asks automatically. Before authorization,
the agent can still receive the frozen app name and bundle identifier with
`captureState: "accessibility_not_authorized"`; it cannot receive protected
window, selection, or resource values.

For an unavailable or slow target, the request continues with app identity and
`target_unavailable`, `accessibility_failed`, or `timed_out`. Native capture has
a 500 ms deadline, so waiting longer will not enrich that same turn. Say a new
follow-up after returning to the intended app; each admitted utterance captures
its own target and late or cancelled work cannot change a newer turn.

Context is bounded to app identity, an optional window title/document URL,
12 KiB of selected text, and eight selected resource references. Resource links
do not include file contents. Voice Activation does not resolve phrases such as
“this” or act on the snapshot; the configured ACP agent decides how to use it.
See [ACP agent harness](agent-harness.md) for the full schema and bounds.

## Agent output stops or the panel remains open

A completed turn keeps the conversation and microphone available for a
follow-up. Use **Stop turn** to cancel only current provider work or **End
conversation** to return to passive listening. After the conversation ends,
**Close** hides retained output and **Delete** releases it.

If output does not follow the bottom, scroll there once; manual upward scrolling
intentionally owns the viewport. If the follow-up queue is full, let current
work and cancellation settle before speaking again.

A provider failure preserves useful output. The next follow-up starts a fresh
session. If a provider forgot an idle session before any observable work, Voice
Activation retries once and shows a context-loss notice; it never replays a
request after output, a permission prompt, or tool activity.

Voice Activation does not persist or log focused Mac snapshot values or content;
it may record safe capture metadata. A provider may retain or replay submitted
blocks in its own session, so use that provider's retention controls when they
apply.

See [Agent conversations](agent-conversations.md) for panel controls, recovery,
and retention.

## An agent is waiting for permission

With **Ask every time**, choose one provider-supplied option in the panel or say
`allow`, `allow all`, `deny`, or `deny all`. The decision applies to the oldest
visible request. Longer utterances remain ordinary follow-ups. Cancelling the
turn settles all pending permission requests.

## Conversation speech or sounds do not play

Confirm the profile's reply-speech setting and **Agent activity sounds** are
enabled, then save. macOS speech uses a system voice for the selected locale.
For ElevenLabs, check the Keychain-backed API key, Voice ID, network access, and
**Test voice**. A failed cloud synthesis falls back to macOS speech.

Narration starts from streamed user-facing reply text; code blocks, thought,
tool, permission, and diagnostic content are not spoken. Speaking during reply
audio stops playback and becomes a follow-up. Activity sounds yield to
permissions and audible narration.

See [Agent conversations](agent-conversations.md) and
[Sound design](sound-design.md) for the complete behavior.

## Push-to-talk does not react

Confirm the shortcut shown for that profile, save any change, and keep the keys
held while speaking. Release submits through the selected profile. If another
application already owns the combination, Voice Activation reports the conflict
and restores the previous bindings.

## Listening stops after joining or leaving a call

Meeting software and audio devices can change microphone channel layout or
sample rate. Voice Activation rebuilds passive listening after the input
settles. If it does not recover, confirm the intended input device and both
privacy grants in System Settings, then inspect `recognition` audio-configuration
events in the trace.

## Launch at Login cannot be enabled

- Move Voice Activation to `/Applications` and launch that copy; do not register
  the temporary bundle under `.build`.
- Verify the bundle with `codesign --verify --deep --strict`.
- Allow Voice Activation under **System Settings > General > Login Items** if
  macOS requires approval, then toggle the setting again.

See [Packaging](packaging.md) for the signed bundle workflow.

## macOS asks for privacy access after every rebuild

The default development bundle is ad-hoc signed, so its identity can change with
the executable. Build with a stable installed development identity and launch a
consistent copy from `/Applications`:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app
```

## Related guides

- [Getting started](getting-started.md)
- [Wake profiles](wake-profiles.md)
- [Command targets](command-targets.md)
- [Agent conversations](agent-conversations.md)
- [Diagnostics](diagnostics.md)
- [Privacy and security](privacy-and-security.md)
