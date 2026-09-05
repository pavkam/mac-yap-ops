<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Concurrency and lifecycle

This reference owns Voice Activation's isolation, identity, callback, ordering,
cancellation, and shutdown contracts. Use it when a correct result arrives late,
work outlives its owner, or a framework callback crosses an actor boundary.

## Isolation model

`VoiceActivationCoordinator`, `AppModel`, and `SpeechSessionProtocol` are
main-actor isolated. Menu state, Settings drafts, active profile state,
recognition transitions, and panel presentation therefore mutate in one ordered
UI domain.

`ACPAgentRunner` and `ACPClientConnection` are actors. The runner serializes
profile-session and active-turn state; each connection serializes JSON-RPC
requests, prompt state, permissions, and terminal lifecycle. Bounded delivery
uses lock-protected queues plus one detached consumer so slow UI work cannot
hold transport ingestion or grow memory without limit.

Framework delegates, process callbacks, network completions, and dispatch queues
do not mutate UI state directly. They re-enter through an explicit main-actor or
mode-aware run-loop boundary and revalidate their identity after suspension.

## Speech-session generations

The coordinator owns one speech session. Starting or stopping recognition
advances its generation and stops the previous framework task, audio engine, and
input tap. Every recognition callback carries the generation it was created
under; a callback from a retired session is ignored.

Capture has narrower identity for initial-silence, inactivity, hard-stop, and
bare-wake handoff tasks. Agent conversation capture has its own generation and
deadlines, so an empty final result or playback restart cannot extend or finish
another utterance.

Push-to-talk press and release callbacks carry the profile identity across
asynchronous permission requests. A delayed release cannot stop a different
profile's capture.

## Execution and conversation identities

Command and agent work capture `executionGeneration`. Completion publishes only
when it still matches the coordinator's current generation.

An agent conversation receives one `runID` that spans all of its turns and the
retained presentation. Each runner turn receives a fresh `AgentTurnToken`.
Permissions retain that token together with the exact JSON-RPC request ID and
connection identity. Presentation, panel actions, narration, synthesis, voice
catalog requests, and previews maintain equivalent run or generation checks at
their own boundaries.

Identity narrows as work moves inward:

```text
profile ID
  └─ speech/capture generation
      └─ execution generation
          └─ conversation run ID
              └─ ACP turn token
                  └─ connection + JSON-RPC request ID
```

A callback must match every identity owned by the state it wants to change.

## Ordered main-run-loop delivery

AppKit may enter nested modal and event-tracking loops while a menu is open, a
panel control tracks the pointer, or a window is dragged. Ordinary main-actor
task continuations can wait for the default loop and make otherwise correct
output appear late.

`MainRunLoopScheduler` keeps latency-sensitive work live by registering one
ordered drain in four modes:

- default;
- common;
- `NSModalPanelRunLoopMode`; and
- `NSEventTrackingRunLoopMode`.

`schedule` delivers short main-actor operations in submission order. `perform`
suspends the producer until delivery completes, preserving upstream ACP
backpressure. Delayed work sleeps off the main actor and still validates its
generation when the operation runs.

Recognition updates, ACP events, presentation publications, narration flushes,
speech synthesis results, activity pulses, audio-device recovery, and capture
deadlines use this bridge where latency across AppKit modes matters.

## Cancellation order

Cancellation is authoritative and follows one order:

1. Mark the owner cancelled or advance its generation.
2. Stop admission and cancel owned tasks, transports, or framework work.
3. Settle permissions, continuations, delegates, and resources exactly once.
4. Reject callbacks carrying the retired identity.
5. Verify terminal state rather than assuming a cancellation request succeeded.

The coordinator changes visible turn state before awaiting the ACP runner. The
connection answers pending permissions with cancellation, sends
`session/cancel` only for a published active prompt, and closes an unresponsive
process after its grace period. Ending a conversation additionally retires live
conversation recognition and resumes passive wake after the configured cooldown.

Speaking a new follow-up while work is active uses the same path: admit the
bounded request, invalidate current execution, cancel the turn, then start the
next prompt only after cancellation settles.

## Bounded queues and backpressure

ACP bytes, typed delivery, main-actor presentation, follow-up prompts, narration,
speech synthesis, diagnostics, and cached sessions each have an explicit owner
and bound. Bounds apply before appending untrusted content.

Lossy streams such as output text or diagnostics may discard their oldest valid
UTF-8 and publish a typed notice. Required control events and permissions fail
closed when they cannot be retained. Natural completion stops admission and
drains accepted events; forced cancellation invalidates the turn and discards
queued delivery.

The transport, runner, coordinator, presentation, and audio layers preserve
causal order. A faster upstream producer cannot bypass a slower bounded consumer
by spawning an untracked task per event.

Canonical sizes and counts live in [ACP agent harness](agent-harness.md) and
[Privacy and security](privacy-and-security.md).

## Audio callback boundary

The real-time `AVAudioEngine` tap performs only buffer handoff through
`SpeechAudioBufferSink`. It does not enter main-actor application state or run
blocking work. Recognition callbacks later cross through the mode-aware bridge.

Speech playback uses framework delegate completion rather than polling
`isSpeaking` or `isPlaying`. The speech queue maintains a cancellation epoch and
ordered request state so an old synthesis or delegate callback cannot start or
finish a replacement request. Playback state arbitrates activity sounds without
rebuilding the conversation microphone immediately before the first sample.

## Process and foreign API isolation

Potentially blocking foreign work stays off the main actor and Swift cooperative
executor:

- Keychain access uses a dedicated user-initiated serial dispatch queue.
- JSONL diagnostic writes use their own user-initiated serial queue.
- Service Management registration uses a dedicated utility queue.
- ACP process reads, writes, exit handling, and stream drain use explicit
  process and dispatch boundaries.
- ElevenLabs requests and prepared-audio delivery cross typed asynchronous
  adapters before returning to the main actor.

Diagnostics record queue delay, operation duration, main-delivery delay,
priority, and run-loop mode where relevant. A long operation and a delayed UI
handoff are separate failure boundaries.

## Shutdown and stale work

Application shutdown marks `AppModel` shut down before cancelling startup,
catalog, preview, narration, speech, shortcut, and recognition work. A delayed
microphone permission response cannot restart passive wake or a held shortcut.

The coordinator invalidates speech and execution identities, cancels deadlines,
stops the active speech session, and requests runner shutdown. The runner rejects
new work, cancels its active turn, closes every cached connection, and terminates
owned provider processes.

Saving changed agent configuration discards affected cached sessions. Closing or
deleting a panel presentation changes only retained UI state; it cannot revive a
completed turn or mutate the coordinator.

## Verification invariants

Regression tests for lifecycle work prove terminal state, not merely that a
cancel method was called:

- retired speech callbacks cannot change state or transcript;
- a stop before provider startup suspension prevents prompt publication;
- a cancelled ACP turn settles every permission once;
- a reused request ID cannot accept an earlier turn's decision;
- natural completion drains accepted events in order;
- forced cancellation cannot publish stale success;
- AppKit event tracking does not delay presentation or audio delivery;
- shutdown prevents delayed permission or callback resurrection; and
- process exit, standard output, and standard error settle independently.

Use [Testing](testing.md) for the proportional verification matrix and
[Diagnostics](diagnostics.md) to locate a delayed boundary before changing
concurrency.

## Related guides

- [Architecture](architecture.md)
- [ACP agent harness](agent-harness.md)
- [Privacy and security](privacy-and-security.md)
- [Diagnostics](diagnostics.md)
- [Testing](testing.md)
