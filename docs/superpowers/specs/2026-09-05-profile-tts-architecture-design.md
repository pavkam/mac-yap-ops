<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Profile and text-to-speech architecture

## Outcome

Profiles become the durable identity of an interaction. A trigger phrase or
profile shortcut selects one profile, and the complete conversation remains
pinned to that profile until it ends. The profile owns its name, icon, accent,
activation controls, action, and speech preference.

Text-to-speech becomes a feature module with a provider-neutral backend
contract. macOS speech and ElevenLabs are the first two backends. Credentials
remain global and secret; profile data stores only backend and voice identity.

## Chosen approach

Keep the existing `YapOpsCore` and `YapOpsApp` SwiftPM
targets. Organize related files into feature folders inside each target and
enforce boundaries with small protocols and value types. SwiftPM already treats
a target as the compiler module and recursively discovers its source files, so
new targets would add dependency ceremony without a present isolation benefit:
[SwiftPM target documentation](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#Target).

Rejected alternatives:

- Separate SwiftPM targets for Profiles and TTS: stronger compile boundaries,
  but premature while both features are tightly composed by one executable.
- Continue switching on a provider enum inside `AgentSpeechQueue`: smallest
  patch, but every backend would reopen queue, Settings, catalog, and preview
  code.
- A generic plugin framework: unsupported by current requirements and needless
  before a third compiled backend exists.

## Profile domain

`WakeProfile` remains the Core domain type to avoid a compatibility-only rename.
User-facing copy calls it a Profile. It gains:

```swift
var name: String
var icon: ProfileIcon
var speechPreference: ProfileSpeechPreference
```

Existing identity, trigger phrase, accent, enabled state, action, and
profile-specific push-to-talk shortcut remain authoritative.

`name` is whitespace-normalized, nonempty, and at most 80 characters.
`ProfileIcon` is a Codable enum:

```swift
case systemSymbol(String)
case emoji(String)
```

Settings offers a curated SF Symbol picker, accepts a custom symbol identifier,
and accepts one extended-grapheme emoji. Rendering validates symbol availability
on the running OS and falls back to `person.crop.circle`; individual SF Symbols
have OS-specific availability, as Apple documents in its
[SF Symbols guidance](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).

## Speech selection

Core owns provider and selection values without importing AVFAudio or AppKit:

```swift
struct TextToSpeechBackendID: RawRepresentable, Codable, Hashable, Sendable
struct TextToSpeechVoiceSelection: Codable, Equatable, Sendable {
    let backendID: TextToSpeechBackendID
    let voiceID: String?
}
enum ProfileSpeechPreference: Codable, Equatable, Sendable {
    case inherit
    case disabled
    case voice(TextToSpeechVoiceSelection)
}
```

The app retains a global `readsAgentRepliesAloud` master switch and a global
default voice selection. Resolution is deterministic:

1. master switch off means no narration;
2. profile `disabled` means no narration;
3. profile `inherit` uses the global default; and
4. profile `voice` uses its explicit backend and voice.

The resolved selection and relevant in-memory credential are snapshotted when
the `.started` lifecycle event supplies the selected profile. Follow-ups reuse
that snapshot. Saving Settings cannot change an active conversation.

## Backend contract

App owns the platform and network implementations:

```swift
protocol TextToSpeechBackend: Sendable {
    var descriptor: TextToSpeechBackendDescriptor { get }
    func voices(credential: String?) async throws -> [TextToSpeechVoice]
    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech
}
```

`TextToSpeechBackendRegistry` validates unique IDs, exposes ordered descriptors,
loads a backend's voice catalog, and routes preparation by ID. Unknown backends
produce a typed error and the queue selects the system fallback.

`PreparedTextToSpeech` describes playback capability, not provider identity:

```swift
case systemVoice(identifier: String?)
case audio(Data)
```

That preserves current delegate-driven system speech and in-memory audio
playback while allowing future cloud backends to return audio without changing
the queue. Apple exposes stable voice identifiers, names, languages, and the
device inventory through `AVSpeechSynthesisVoice`:
[voice documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice).

The system backend lists installed voices and prepares a system-voice token.
The ElevenLabs backend wraps the existing synthesis and catalog clients and
prepares audio. Both use the same catalog and preparation entry points.

## Credentials and privacy

Credentials are global per backend. ElevenLabs remains a Keychain generic
password and is loaded off the main actor through the existing store. A profile,
`UserDefaults`, diagnostics, tests, and documentation never contain credential
values. Backend requests receive only the credential needed for that call.

Diagnostics record backend ID, profile ID, voice presence, timings, counts, and
outcomes. They never record voice text, transcript content, credentials,
authorization, response bodies, or audio.

## Settings experience

The global conversation card owns the master switch, default backend/voice, and
global provider credentials. Each Profile card owns:

- icon, display name, trigger phrase, accent, and enabled state;
- command or agent action configuration;
- profile shortcut; and
- speech mode: Inherit Default, Off, macOS, or ElevenLabs, followed by the
  selected backend's common voice picker.

The same picker renders system and cloud voices. Catalog failure preserves a
saved/manual voice ID and explains the failure without invalidating unrelated
profile edits. Preview uses the selected backend and never mutates saved state.
Icon and accent accompany the profile name in Settings, the menu, recording
overlay, and conversation panel; color is never the sole identity signal.

## Persistence migration

Legacy profile JSON lacks name, icon, and speech preference. Decode it as:

- name: title-cased normalized trigger phrase;
- icon: `systemSymbol("sparkles")`; and
- speech preference: `inherit`.

The existing global provider and ElevenLabs voice ID become the new global
default voice selection. The master read-aloud setting is preserved. The old
keys remain read-only migration inputs; new saves write the new representation.
Invalid or unavailable persisted voices remain visible for correction and fall
back safely at runtime.

## Feature folders

```text
Sources/YapOpsCore/Profiles/
Sources/YapOpsCore/TextToSpeech/
Sources/YapOpsApp/Profiles/
Sources/YapOpsApp/TextToSpeech/
Sources/YapOpsApp/TextToSpeech/Backends/System/
Sources/YapOpsApp/TextToSpeech/Backends/ElevenLabs/
Tests/YapOpsCoreTests/Profiles/
Tests/YapOpsCoreTests/TextToSpeech/
Tests/YapOpsAppTests/Profiles/
Tests/YapOpsAppTests/TextToSpeech/
```

Only profile and TTS ownership moves in this change. Other features move when a
real edit crosses their boundary; a repository-wide folder shuffle would be
motion without progress.

## Verification

Tests must prove legacy decoding, validation, preference resolution, registry
routing, both catalogs, system voice identifiers, queue ordering/fallback,
profile pinning across follow-ups, stale completion rejection, Settings save,
and icon fallback. Unit tests use inert credentials, fake catalogs, and silent
players; they never contact providers or play sound.

Completion requires focused RED/GREEN cycles, the full Swift suite, Thread
Sanitizer, warnings-as-errors build, `make check`, debug app packaging, signature
and plist verification, and `git diff --check`. Manual appearance, accessibility,
and listening rows are reported rather than invented.
