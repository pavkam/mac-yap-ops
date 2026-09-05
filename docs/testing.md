<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Testing

Voice Activation uses Swift Testing in separate Core and App test targets. Put
each test at the lowest boundary that exposes the behavior, run the focused
regression first, and widen verification according to the risk of the change.

## Test boundaries

| Behavior | Test target and preferred boundary |
| --- | --- |
| State transitions, wake matching, validation, command expansion, ACP wire and lifecycle, bounded queues | `VoiceActivationCoreTests` with pure values or controlled protocol fakes |
| `AppModel`, presentation, layout, Settings, Keychain, Service Management, hotkeys, audio, SwiftUI and AppKit | `VoiceActivationAppTests` with injected adapters |
| ACP framing, ordering, permissions, cancellation, and recovery | `FakeACPTransport` and the focused ACP test-support types |
| Real process and pipe behavior | A short explicit executable in a UUID temporary directory |
| Speech and coordinator behavior | `FakeSpeechSession`, `ControlledAgentRunner`, and injected `ActivationTiming` |
| UI copy, state, and geometry | Pure presentation or layout tests before window-level tests |

Use `@MainActor` when the production owner is main-actor isolated. A
`@Suite(.serialized)` constraint serializes only that suite; it does not isolate
process-global AppKit state from other suites. A real window or intermediate
animation test that touches global state belongs in an isolated child process.

## Find and run a focused test

Discover the actual suite and test identifiers before filtering:

```bash
swift test list | rg 'RelevantType|RelevantBehavior'
swift test --filter 'VoiceActivationCoreTests.WakePhraseMatcherTests'
swift test --filter 'VoiceActivationAppTests.AgentRunPresentationTests'
swift test --filter 'VoiceActivationCoreTests.WakePhraseMatcherTests/command_WhenPhraseStartsTranscript_ReturnsFollowingText'
```

For a behavior fix, first confirm that the smallest regression fails because the
defect is present. After the fix, rerun that test, its owning suite, and then the
required broader rows below. `swift test --skip-build` is valid only immediately
after a successful build with matching sources, flags, configuration, and
toolchain.

## Core suites

Core tests cover coordinator state, capture timing, cancellation, profile and
command validation, direct-process execution, ACP JSON-RPC framing, event
decoding, permissions, session caching and recovery, bounded delivery, and
shutdown races.

Asynchronous suites use controlled continuations, actor-backed recorders, fake
clocks or sleepers, explicit gates, and observable terminal state. A wall-clock
delay is appropriate only when elapsed time is the behavior; it must remain
short and bounded by a test time limit.

## App suites

App tests cover Settings and lifecycle composition, non-activating panels,
presentation and layout, Markdown rendering policy, hot-key conversion, speech
request policy, audio orchestration, narration, Keychain and login-item
adapters, diagnostics, resources, and visible state mapping.

Audio and speech tests use silent players and controlled clients. Network clients
use injected transports. Tests of Keychain and Service Management use stores or
services that cannot mutate the developer Mac.

## Environment-free test contract

Automated tests must not require or alter:

- a microphone, audible output, installed system voice, or global hotkey;
- Microphone or Speech Recognition privacy state;
- a real Keychain secret, login item, or user preferences domain;
- a provider installation, authentication, live session, network, or paid
  request; or
- files outside a unique temporary directory.

Never put prompts, transcripts, credentials, authorization, provider content,
raw ACP payloads, or audio into test logs or fixtures. Child-process fixtures use
an explicit executable and arguments, not a shell.

## Proportional verification

| Change | Verification after the focused test |
| --- | --- |
| Pure Core, model, or presentation behavior | Owning suite, then `swift test` |
| SwiftUI, AppKit, or macOS adapter | `swift test`, `CONFIGURATION=debug make app`, affected manual flow |
| Actor, callback, queue, pipe, timer, cancellation, or audio delegate | Above plus Thread Sanitizer |
| Memory or lifetime corruption | Focused reproduction plus Address Sanitizer; use Allocations or Leaks for runtime-only behavior |
| ACP | ACP-focused matrix, full tests, and a local client probe only when compatibility, a preset, pin, or startup contract changes |
| Resources, plist, signing, permissions, Keychain identity, or login item | Real bundled flow from a stable path plus bundle verification |
| Public Core API, repository structure, or documentation | `make check` and `git diff --check` |

## Sanitizers

Use Thread Sanitizer for concurrency boundaries and Address Sanitizer for memory
lifetime defects:

```bash
swift test --sanitize=thread
swift test --sanitize=address
```

Sanitizers change timing and performance. Reproduce without instrumentation too
before drawing a latency conclusion.

## Continuous integration

The `🎙️ Swift CI` workflow runs four gates for pushes and pull requests to
`main`: repository quality, warning-as-error build plus tests, Thread Sanitizer,
and app packaging after the first three pass.

The local CI-equivalent sequence is:

```bash
swift package resolve
swift build --build-tests -Xswiftc -warnings-as-errors -v
swift test --skip-build
swift test --sanitize=thread
make app
make check
git diff --check
```

## Report evidence

Report the focused regression and why its failing result was correct, every
command actually run, the fresh result, and any manual or environment-bound row
not exercised. An unrun command is not a pass. Separate unrelated pre-existing
failures with concrete output instead of adopting them as part of the change.

## Related guides

- [Development](development.md)
- [Packaging](packaging.md)
- [Diagnostics](diagnostics.md)
- [ACP agent harness](agent-harness.md)
- [Documentation](documentation.md)
