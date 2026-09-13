<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Elevated target

The YapOps Design System was reverse-engineered from this repository, but its
brief was "the elevated target" — so it described several surfaces the
application did not have. All of them are now built; this page is the record
of what changed, why each one landed the way it did, and the one place a
repository invariant had to be reinterpreted rather than obeyed literally.

## Adopted

The token layer, the accent environment, and the content contract in
`content-and-voice.md`. See
`docs/superpowers/specs/2026-09-12-design-token-foundation-design.md` for the
original design; the sections below cover what it deferred.

Every "Intentional addition" the design system's readme lists is now built:

| Addition | Where | Notes |
| --- | --- | --- |
| `EmptyState` | `Settings/SettingsEmptyState.swift` | One recipe, used where the Profiles detail column has no selection |
| Recovery on `FailureCard` | `AgentRunPanelContent.swift` `failureCard` | "Retry turn" resends the run's original prompt through `.retry` |
| `VoiceBars` and level metering | `VoiceBars.swift`, `SpeechAudioLevelMeter.swift` | Menu capture strip and the recording overlay; the conversation composer's mic button does not yet carry live levels — see below |
| `Composer` | `AgentRunComposer.swift` | Required reinterpreting a panel invariant; see below |
| `SaveIndicator` and autosave | `Settings/SaveIndicator.swift`, `Settings/SettingsAutosave.swift` | Replaces the explicit "Save Settings" button |
| First-run flow | `Onboarding/FirstRunView.swift`, `Onboarding/FirstRunPresenter.swift` | Gated by `AppPreferences.hasCompletedFirstRun` |

Also built beyond that list: the Profiles pane's master–detail restructure
(`Settings/ProfilesPane.swift`, `Settings/SidebarProfileRow.swift`), the curated
glyph picker (`Settings/ProfileGlyphPicker.swift`), and the artifact count chip
on the Results shelf (`AgentRunArtifactView.swift`).

## Not vendored

The archive's 265 files stay outside the repository. Every binary asset in it
already exists here: the six interface cues and `YapOps.icns` live in
`Sources/YapOpsApp/Resources/` and are annotated in `REUSE.toml`;
`assets/yapops-mark.svg` is a transcription of `YapOpsMark.swift`, which draws
the mark in code; and the 74 Lucide icons are a substitution the system's own
readme tells consumers to discard on macOS, where the real SF Symbols exist.

Vendoring would add a second copy of assets we own plus ~200 files of React and
CSS that a SwiftPM repository cannot build, test or lint, and an ISC obligation
for icons we will not use.

## The `Composer` reinterpreted a panel invariant

The design system's `Composer` puts a text input in the conversation panel.
That collided with AGENTS.md's requirement that the menu, recording and agent
panels remain non-activating and preserve the foreground app's focus, which
`AgentRunPanelController.swift` had enforced with a hard
`override var canBecomeKey: Bool { false }`. A text field needs key focus; a
panel that can never take it cannot host one.

The resolution: the panel now returns `true`, but the constraint that made the
original override necessary — the app must never activate, and a stray click
must never steal focus — is preserved by the mechanism already in place rather
than by the blanket refusal. The panel stays `.nonactivatingPanel` with
`becomesKeyOnlyIfNeeded = true`, so AppKit hands over key status only when the
user clicks a control that actually requires it (the composer's field), never
for a click on chrome, a drag, or a button; the application itself still never
activates, so the foreground app keeps its state. `canBecomeMain` stays false —
YapOps still has no main window. `AgentRunPanelPresenterTests` asserts this
narrower contract by name
(`panel_WhenConstructed_TakesKeyOnlyOnDemandAndNeverBecomesMain`).

## Known gap: the composer's microphone has no live level

`VoiceBars` reads real levels in the menu capture strip and the recording
overlay, both fed from `AppleSpeechSession`'s recognition tap through
`SpeechAudioLevelMeter`. The conversation composer's microphone button does not
carry the same live signal — turn-level agent-conversation audio is a separate
subsystem from the passive/push-to-talk capture path metered today, and
threading levels through it needs its own look at that subsystem's real-time
constraints rather than being folded into this pass.

## Also not adopted

- **The Lucide icon set** — this is macOS; use real SF Symbols through
  `Image(systemName:)`. The substitution exists so the design system renders in a
  browser, not because Lucide is the intent.
- **The light appearance scope** — the CSS defines `[data-appearance="light"]`.
  The Swift layer names macOS system colours, which adapt on their own, so no
  parallel light palette is needed or wanted.
