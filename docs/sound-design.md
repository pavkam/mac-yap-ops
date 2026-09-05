<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Sound design

Use this reference to identify each bundled cue and the runtime edge that owns
its playback. Audio supplements visible state; it is never the only indication
that capture, work, permission, narration, completion, or failure changed.

## Cue map

| Event | Asset | Duration | Playback |
| --- | --- | ---: | --- |
| Capture begins | `CaptureStart.wav` | 0.68 s | Once when state enters capture. |
| Capture ends | `CaptureEnd.wav` | 0.64 s | Once when state leaves capture. |
| Agent is working | `AgentThinking.wav` | 0.64 s | Immediately when work begins, then every 3.2 s. After a tool cue or spoken reply, it resumes after 1.6 s if work continues. |
| Tool becomes active | `ToolStart.wav` | 0.52 s | Once for that tool's active phase. |
| Tool completes | `ToolComplete.wav` | 0.52 s | Once when that tool reaches completion. |
| Tool fails | `ToolFailed.wav` | 0.60 s | Once when that tool reaches failure. |

Capture cues are independent of **Agent activity sounds**. The setting controls
the thinking and tool cues. Disabling reply speech does not disable activity
sounds, and disabling activity sounds does not change visible agent state.

## Playback ownership

`CaptureSoundPresenter` compares the previous and current activation state, so
repeated updates within capture do not replay its edges. `SystemCaptureSoundPlayer`
loads the two bundled files through `NSSound` and falls back to the macOS `Pop`
or `Tink` sound if an asset cannot start.

`AgentConversationAudioPresenter` normalizes repeated provider tool updates into
active, completed, and failed phases per tool and turn. A duplicate phase is
silent. `AgentActivitySoundLoop` owns one current effect plus one scheduled
thinking pulse; playing a tool cue stops the current effect and restarts the
thinking delay.

The loop cancels its scheduled generation before stopping or rescheduling. A
late pulse therefore cannot play after the turn, run, or application has ended.
AppKit event-tracking and modal run-loop modes still receive an eligible pulse
through the mode-aware main-run-loop scheduler.

## Narration and permission arbitration

Cloud synthesis preparation leaves the thinking pulse active. The loop becomes
silent before playback starts and throughout audible narration, then waits 1.6
seconds before resuming if agent work is still active. A permission request also
silences working cues; resolving it starts the current work phase again.

Tool sounds follow the same suppression state, so a tool transition cannot talk
over narration. Ending or failing a conversation stops activity and speech
playback together.

## Bundled assets

All six committed effects are mono, 48 kHz, 16-bit PCM WAV files. Runtime cue
playback never contacts a network service. The bundle script copies each file
into `VoiceActivation.app/Contents/Resources`; missing agent effects fall back
to the mapped macOS system sound.

The effects were generated once with the ElevenLabs
[Sound Effects API](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert)
using `eleven_text_to_sound_v2`, explicit sub-second durations, non-looping
output, and `0.65` prompt influence. The source request asked for subtle glass
and air interface cues without voices, percussion, heavy bass, alarms, or long
reverb. Generated 44.1 kHz MP3 files were converted before commit; no generation
credential or source response is stored in the repository.

Optional ElevenLabs reply narration is a separate path and does contact that
service when selected.

## Silent-test contract

Capture, activity, narration, synthesis, and playback tests inject silent
players, controlled clocks, and network-free transports. They verify capture
edges, phase deduplication, pulse timing, permission silence, narration
arbitration, event-tracking delivery, cancellation generations, and fallback
selection without playing a speaker sound or making a paid request.

## Related guides

- [Agent conversations](agent-conversations.md)
- [Privacy and security](privacy-and-security.md)
- [Diagnostics](diagnostics.md)
- [Testing](testing.md)
- [Packaging](packaging.md)
