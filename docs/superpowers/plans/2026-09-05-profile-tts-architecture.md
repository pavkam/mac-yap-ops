<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Profile and Text-to-Speech Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Profiles the immutable identity of an interaction and provide a provider-neutral, profile-selectable TTS subsystem with macOS and ElevenLabs backends.

**Architecture:** Keep the two existing SwiftPM targets and organize Profile/TTS files into feature folders. Core persists platform-neutral identity and speech selections; App owns backend registry, voice catalogs, credentials, preparation, playback, Settings, and conversation pinning.

**Tech Stack:** Swift 6.2, SwiftPM, Swift Testing, Observation, SwiftUI/AppKit, AVFAudio, Security, URLSession.

**Spec:** `docs/superpowers/specs/2026-09-05-profile-tts-architecture-design.md`

## Global Constraints

- Minimum platform remains macOS 15; do not create an Xcode project or add dependencies.
- Keep `YapOpsCore` free of SwiftUI, AppKit, AVFAudio, and Security.
- Trigger phrase or profile shortcut selects one immutable profile for the complete conversation.
- TTS credentials are global per backend and never persist in a profile or diagnostics.
- Tests use fake catalogs, inert credentials, and silent players; no network, Keychain, TCC, or sound.
- Preserve FIFO playback, bounded queues, system fallback, cancellation generations, and stale-callback rejection.
- Every source/test file stays under 700 lines and includes the MIT SPDX header.

---

### Task 1: Profile identity and persisted speech selection

**Files:**
- Create: `Sources/YapOpsCore/TextToSpeech/TextToSpeechBackendID.swift`
- Create: `Sources/YapOpsCore/TextToSpeech/TextToSpeechVoiceSelection.swift`
- Create: `Sources/YapOpsCore/Profiles/ProfileIcon.swift`
- Modify: `Sources/YapOpsCore/WakeProfile.swift`
- Modify: `Sources/YapOpsCore/AppPreferences.swift`
- Modify: `Sources/YapOpsApp/WakeProfileDraft.swift`
- Test: `Tests/YapOpsCoreTests/WakeProfileTests.swift`
- Test: `Tests/YapOpsCoreTests/AppPreferencesTests.swift`
- Test: `Tests/YapOpsAppTests/WakeProfileDraftTests.swift`

**Interfaces:**
- Produces: `TextToSpeechBackendID`, `TextToSpeechVoiceSelection`, `ProfileSpeechPreference`, `ProfileIcon`.
- Produces: `WakeProfile.name`, `WakeProfile.icon`, and `WakeProfile.speechPreference` with legacy decoding defaults.
- Produces: `AppPreferences.defaultSpeechVoice` with legacy provider/voice migration.

- [ ] **Step 1: Write failing Core tests**

Add tests proving a current profile round-trips name/icon/speech, legacy JSON
derives the name and defaults to `.systemSymbol("sparkles")` plus `.inherit`, an
empty name fails validation, an emoji must be one grapheme, and old global
provider/voice keys resolve to a default `TextToSpeechVoiceSelection`.

```swift
let profile = try WakeProfile(
    name: "Research",
    icon: .emoji("🔬"),
    wakePhrase: "researcher",
    action: action,
    accent: .purple,
    speechPreference: .voice(.init(backendID: .elevenLabs, voiceID: "voice-1")))
#expect(try JSONDecoder().decode(WakeProfile.self,
    from: JSONEncoder().encode(profile)) == profile)
```

- [ ] **Step 2: Verify the tests fail for missing API**

Run: `swift test --filter 'WakeProfileTests|AppPreferencesTests|WakeProfileDraftTests'`

Expected: compile failure naming the missing profile metadata and TTS selection types.

- [ ] **Step 3: Implement platform-neutral values and migration**

Use a raw-value backend ID with static `.system` and `.elevenLabs` values. Make
`ProfileSpeechPreference` encode explicit `inherit`, `disabled`, and `voice`
cases. Normalize the profile name to 1...80 characters and validate icon payloads.
Decode missing fields without rewriting the user's defaults during a read.

- [ ] **Step 4: Mirror the values in `WakeProfileDraft`**

Round-trip all new fields and use `Computer`, `sparkles`, and `.inherit` for a
new/default profile. Preserve stable IDs when saving drafts.

- [ ] **Step 5: Verify Task 1 GREEN**

Run: `swift test --filter 'WakeProfileTests|AppPreferencesTests|WakeProfileDraftTests'`

Expected: all selected suites pass with no warning.

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/YapOpsCore Sources/YapOpsApp/WakeProfileDraft.swift Tests/YapOpsCoreTests Tests/YapOpsAppTests/WakeProfileDraftTests.swift
git commit -m "feat: add profile identity and speech preferences"
```

### Task 2: Common TTS backends and queue preparation

**Files:**
- Create: `Sources/YapOpsApp/TextToSpeech/TextToSpeechBackend.swift`
- Create: `Sources/YapOpsApp/TextToSpeech/TextToSpeechBackendRegistry.swift`
- Create: `Sources/YapOpsApp/TextToSpeech/Backends/System/SystemTextToSpeechBackend.swift`
- Create: `Sources/YapOpsApp/TextToSpeech/Backends/ElevenLabs/ElevenLabsTextToSpeechBackend.swift`
- Modify: `Sources/YapOpsApp/AgentSpeechQueue.swift`
- Modify: `Sources/YapOpsApp/AgentSpeechPlayback.swift`
- Modify: `Sources/YapOpsApp/ElevenLabsSpeechClient.swift`
- Modify: `Sources/YapOpsApp/ElevenLabsVoiceCatalogClient.swift`
- Test: `Tests/YapOpsAppTests/TextToSpeechBackendRegistryTests.swift`
- Test: `Tests/YapOpsAppTests/SystemTextToSpeechBackendTests.swift`
- Test: `Tests/YapOpsAppTests/ElevenLabsTextToSpeechBackendTests.swift`
- Test: `Tests/YapOpsAppTests/AgentSpeechQueueTests.swift`

**Interfaces:**
- Consumes: `TextToSpeechBackendID` and `TextToSpeechVoiceSelection` from Task 1.
- Produces: `TextToSpeechVoice`, `TextToSpeechBackendDescriptor`, `TextToSpeechPreparationRequest`, `PreparedTextToSpeech`.
- Produces: `TextToSpeechBackend.voices(credential:)` and `prepare(_:credential:)`.
- Produces: registry `descriptors`, `voices(for:credential:)`, and `prepare(_:selection:credential:)`.

- [ ] **Step 1: Write failing backend contract tests**

Test deterministic descriptor order, duplicate-ID rejection, unknown-ID errors,
catalog routing, preparation routing, system inventory mapping, and ElevenLabs
client forwarding with an inert API key.

```swift
let voices = try await registry.voices(for: .system, credential: nil)
#expect(voices.map(\.id) == ["com.example.a", "com.example.b"])
```

- [ ] **Step 2: Verify backend tests RED**

Run: `swift test --filter 'TextToSpeechBackendRegistryTests|SystemTextToSpeechBackendTests|ElevenLabsTextToSpeechBackendTests'`

Expected: compile failure because the registry and common backend types do not exist.

- [ ] **Step 3: Implement the backend contract and registry**

Keep descriptors and voices immutable/Sendable. Return `.systemVoice(identifier:)`
from the system backend and `.audio(Data)` from ElevenLabs. The registry owns no
credentials and records no request text.

- [ ] **Step 4: Replace provider branching in `AgentSpeechQueue`**

Inject one `TextToSpeechPreparing` dependency. Pending requests carry a resolved
selection and optional in-memory credential. Prefetch asks the registry to
prepare; success dispatches by `PreparedTextToSpeech`, while any preparation
error selects `.systemVoice(identifier: nil)` for the same text.

- [ ] **Step 5: Extend playback selection**

Change system playback to accept an optional stable voice identifier, use
`AVSpeechSynthesisVoice(identifier:)` when available, and fall back to the
request locale without failing playback.

- [ ] **Step 6: Verify queue behavior GREEN**

Run: `swift test --filter 'TextToSpeechBackend|AgentSpeechQueueTests|ElevenLabsSpeechClientTests|ElevenLabsVoiceCatalogClientTests'`

Expected: all backend, queue ordering, lookahead, fallback, cancellation, and stale-generation tests pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/YapOpsApp/TextToSpeech Sources/YapOpsApp/AgentSpeechQueue.swift Sources/YapOpsApp/AgentSpeechPlayback.swift Sources/YapOpsApp/ElevenLabsSpeechClient.swift Sources/YapOpsApp/ElevenLabsVoiceCatalogClient.swift Tests/YapOpsAppTests
git commit -m "refactor: introduce text to speech backends"
```

### Task 3: Pin profile speech for the conversation lifecycle

**Files:**
- Modify: `Sources/YapOpsApp/AgentConversationAudio.swift`
- Modify: `Sources/YapOpsApp/AgentSpeechSettingsState.swift`
- Modify: `Sources/YapOpsApp/AppModel.swift`
- Modify: `Sources/YapOpsApp/AppModel+AgentConversation.swift`
- Test: `Tests/YapOpsAppTests/AgentConversationAudioLifecycleTests.swift`
- Test: `Tests/YapOpsAppTests/AgentConversationAudioTestSupport.swift`
- Test: `Tests/YapOpsAppTests/AppModelConversationTests.swift`

**Interfaces:**
- Consumes: profile speech preference and registry preparation from Tasks 1-2.
- Produces: `ResolvedTextToSpeechConfiguration` snapshot per conversation.
- Produces: resolver `(WakeProfile) -> ResolvedTextToSpeechConfiguration?` injected into the audio presenter.

- [ ] **Step 1: Write failing pinning tests**

Start profile A, submit a follow-up, mutate the global/default settings to profile
B's voice, emit another reply segment, and assert both segments used A's original
backend/voice. Also prove disabled and master-off profiles suppress narration.

- [ ] **Step 2: Verify lifecycle tests RED**

Run: `swift test --filter 'AgentConversationAudioLifecycleTests|AppModelConversationTests'`

Expected: failure because speech configuration is still read globally for each segment.

- [ ] **Step 3: Snapshot at `.started` and clear only at terminal lifecycle**

Resolve once from the lifecycle event's profile. Follow-ups retain the snapshot.
Cancellation stops queued speech but does not switch profiles. Completed/failed
conversation clears the snapshot after terminal audio handling.

- [ ] **Step 4: Verify Task 3 GREEN**

Run: `swift test --filter 'AgentConversationAudio|AppModelConversationTests'`

Expected: all selected lifecycle, activity, presenter, and model tests pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/YapOpsApp/AgentConversationAudio.swift Sources/YapOpsApp/AgentSpeechSettingsState.swift Sources/YapOpsApp/AppModel.swift Sources/YapOpsApp/AppModel+AgentConversation.swift Tests/YapOpsAppTests
git commit -m "feat: pin profile voice to conversations"
```

### Task 4: Profile-first Settings and common voice catalogs

**Files:**
- Create: `Sources/YapOpsApp/Profiles/ProfileIconView.swift`
- Create: `Sources/YapOpsApp/Profiles/ProfileIconPicker.swift`
- Create: `Sources/YapOpsApp/TextToSpeech/TextToSpeechSettingsModel.swift`
- Create: `Sources/YapOpsApp/TextToSpeech/TextToSpeechVoicePicker.swift`
- Modify: `Sources/YapOpsApp/SettingsView.swift`
- Modify: `Sources/YapOpsApp/AppModel.swift`
- Modify: `Sources/YapOpsApp/AppModel+Configuration.swift`
- Modify: `Sources/YapOpsApp/MenuContentView.swift`
- Test: `Tests/YapOpsAppTests/ProfileIconViewTests.swift`
- Test: `Tests/YapOpsAppTests/TextToSpeechSettingsModelTests.swift`
- Test: `Tests/YapOpsAppTests/AppModelSettingsTests.swift`
- Test: `Tests/YapOpsAppTests/MenuContentViewTests.swift`

**Interfaces:**
- Consumes: backend descriptors/catalogs and persisted profile values.
- Produces: one shared picker for system and ElevenLabs voices.
- Produces: profile card controls for name, icon, trigger, accent, action, shortcut, and speech preference.

- [ ] **Step 1: Write failing presentation/settings tests**

Test curated/custom/emoji icon rendering and fallback; common voice picker state;
per-profile round-trip through save; legacy default migration; catalog failure
preserving a manual ID; and menu identity using name + icon + accent.

- [ ] **Step 2: Verify Settings tests RED**

Run: `swift test --filter 'ProfileIcon|TextToSpeechSettingsModelTests|AppModelSettingsTests|MenuContentViewTests'`

Expected: compile or assertion failure for absent profile-first controls/models.

- [ ] **Step 3: Build the feature models and controls**

Keep network/catalog work outside SwiftUI `body`. Key catalog and status state by
backend ID, reject stale generations, and preserve manual IDs on failure. Use
semantic labels so name/icon—not color alone—identifies a profile.

- [ ] **Step 4: Integrate validation and atomic save**

Validate every explicit backend through the registry. Store only selection IDs
in `UserDefaults`; save global ElevenLabs credentials through the existing
Keychain adapter. Roll back shortcut registration if credential persistence fails.

- [ ] **Step 5: Verify Task 4 GREEN**

Run: `swift test --filter 'ProfileIcon|TextToSpeech|AppModelSettingsTests|MenuContentViewTests'`

Expected: all selected UI model and adapter tests pass without opening a window or playing audio.

- [ ] **Step 6: Commit Task 4**

```bash
git add Sources/YapOpsApp/Profiles Sources/YapOpsApp/TextToSpeech Sources/YapOpsApp/SettingsView.swift Sources/YapOpsApp/AppModel.swift Sources/YapOpsApp/AppModel+Configuration.swift Sources/YapOpsApp/MenuContentView.swift Tests/YapOpsAppTests
git commit -m "feat: add profile voice and identity settings"
```

### Task 5: Feature folders, documentation, and full evidence

**Files:**
- Move: profile/TTS source and test files into the feature folders in the spec.
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/configuration.md`
- Modify: `docs/sound-design.md`
- Modify: `.agents/skills/development/references/project-architecture.md`
- Modify: `.agents/skills/voice-reading/references/architecture-and-lifecycle.md`
- Modify: `.agents/skills/voice-reading/references/macos-speech.md`
- Modify: `.agents/skills/voice-reading/references/testing-and-diagnostics.md`

**Interfaces:**
- Consumes: completed behavior from Tasks 1-4.
- Produces: discoverable feature ownership and synchronized user/agent documentation.

- [ ] **Step 1: Move files without changing declarations**

Use `git mv` only for Profile/TTS-owned files. Mirror source folders in both test
targets. Do not reorganize ACP, panels, recording, or diagnostics in this change.

- [ ] **Step 2: Update documentation and guidance**

Document profile identity, pinning, selection resolution, global credentials,
voice catalogs, migration, folder ownership, privacy, and fallback. Keep every
`.agents/skills` text file within 150 lines and route any new reference.

- [ ] **Step 3: Run focused and structural checks**

```bash
swift test --filter 'WakeProfile|TextToSpeech|AgentSpeech|AgentConversationAudio|AppModelSettings'
make check
git diff --check
```

Expected: all selected suites and repository gates pass.

- [ ] **Step 4: Run CI-equivalent verification**

```bash
swift package resolve
swift build --build-tests -Xswiftc -warnings-as-errors -v
swift test --skip-build
swift test --sanitize=thread
CONFIGURATION=debug make app
codesign --verify --deep --strict .build/YapOps.app
plutil -lint .build/YapOps.app/Contents/Info.plist
```

Expected: warnings-as-errors build succeeds, every test passes normally and under
Thread Sanitizer, and the debug bundle is valid and signed.

- [ ] **Step 5: Report manual rows honestly**

Record whether light/dark, reduced motion/transparency, VoiceOver, actual installed
system voices, paid ElevenLabs synthesis, and audible output were exercised. Do
not call an unrun row a pass.

- [ ] **Step 6: Commit Task 5**

```bash
git add README.md docs .agents Sources Tests
git commit -m "docs: document profiles and text to speech modules"
```
