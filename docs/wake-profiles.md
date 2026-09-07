<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Wake profiles

Use profiles to route different wake phrases and shortcuts to different command
or agent targets. This guide owns wake matching, passive listening,
push-to-talk, capture timing, and spoken capture cancellation.

## What a profile controls

Every profile combines:

- a user-facing name, SF Symbol or emoji, and accent color;
- one wake phrase;
- one command or agent target;
- an enabled state for passive wake; and
- an optional global push-to-talk shortcut; and
- an inherited, disabled, or explicit reply voice.

Add or remove profile cards in Settings, then select **Save Settings**. At least
one valid profile must remain.

## Match a wake phrase

A phrase matches only at the beginning of recognized speech and must end at a
word boundary. Matching ignores case, width, accents, surrounding punctuation,
and repeated whitespace. Invisible control and format marks are removed before
the phrase is saved.

For example, `computer, open calendar` matches the `computer` profile;
`supercomputer open calendar` does not. If enabled phrases overlap, the longest
matching phrase wins.

Phrases must contain at least one letter or number and must be unique after the
same canonical normalization. Saved enabled phrases are supplied to Apple
Speech as contextual vocabulary, which helps intentional names and uncommon
spellings without changing the match rules.

## Enable or pause passive wake

Each profile has an independent menu toggle. Disabling it removes only that
phrase from passive recognition; its shortcut remains available.

Use **Pause all** to stop passive wake without changing the saved profile
toggles. **Resume all** restores recognition for the profiles that are still
enabled. If every phrase is disabled, the passive microphone stops even when
**Always listen** remains on.

Passive wake always requires on-device recognition for the selected locale. If
the locale cannot provide it, listening fails closed instead of sending an
always-on stream to Apple's speech service.

## Assign push-to-talk

Select **Set shortcut** inside a profile, then press a normal key together with
Control, Option, Shift, or Command. Press Escape to abandon the recording.
Select **Save Settings** to replace the registered shortcut set.

Physical bindings must be unique across profiles. When another application has
already reserved a combination, YapOps reports the conflict and
restores every previously saved registration.

Hold a registered shortcut, speak without a wake phrase, and release the keys
to submit through that profile. The press and release keep the same profile
identity even while a macOS permission prompt is pending. During an open agent
conversation, only the selected conversation profile's shortcut contributes a
follow-up; another profile cannot take over the conversation.

The first profile receives Control-Option-Space during first-run preference
migration.

## Understand capture timing

| Boundary | Duration | Result |
| --- | ---: | --- |
| Bare partial wake phrase handoff | 350 ms | Starts dedicated command capture unless command words arrive in the same utterance. |
| Initial command silence | 5 s | Returns to passive wake if no command text arrives. |
| Unchanged command text | 1.5 s | Submits the best transcription. |
| Maximum active utterance | 30 s | Finishes the current command or conversation utterance. |
| Recoverable passive restart | 1 s | Restarts passive recognition after a recoverable failure. |
| Successful command cooldown | 250 ms | Resumes passive wake after the command finishes. |

A final Apple Speech result submits immediately. An empty final result during
command capture restarts recognition inside the existing deadline; it does not
grant another five seconds. Push-to-talk normally submits when the shortcut is
released. Agent conversation capture has no initial-silence timeout because it
stays available between turns.

Interactive command, push-to-talk, and conversation capture may use Apple's
speech service when on-device recognition is unavailable. Only passive wake is
strictly on-device.

## Cancel a capture by voice

Say only `cancel`, `stop`, or `dismiss` to discard command or push-to-talk
capture. One occurrence waits for a completion boundary because a partial word
may grow into a normal command such as `stop the music`. Repeating the same word
twice cancels immediately, even in a partial transcription.

Numbers and longer phrases remain command content. `stop 123` is submitted
normally.

Inside an agent conversation, the same three single-word commands end the whole
conversation. Use **Stop turn** when only the current agent work should stop.

## Recognition availability

The recording overlay appears only during command or push-to-talk capture. It
uses the profile accent, shows a rolling tail of recognized text, follows the
screen containing the pointer, and never takes keyboard focus from the current
application. Its close button discards the current capture.

Audio-device changes may stop Apple's current engine. YapOps rebuilds
passive recognition after the input configuration settles while rejecting late
callbacks from the retired session.

## Related guides

- [Configuration reference](configuration.md)
- [Command targets](command-targets.md)
- [Agent conversations](agent-conversations.md)
- [Troubleshooting](troubleshooting.md)
