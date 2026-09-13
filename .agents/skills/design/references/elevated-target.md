<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Elevated target

The YapOps Design System was reverse-engineered from this repository, but its
brief was "the elevated target" — so it describes several surfaces the
application does not have. Those are feature projects, not styling, and each
carries behavioural risk that a token migration does not.

This page records what was deliberately **not** adopted, so that a later agent
neither builds it by accident nor re-proposes it as an oversight.

## Adopted

The token layer, the accent environment, and the content contract in
`content-and-voice.md`. See
`docs/superpowers/specs/2026-09-12-design-token-foundation-design.md`.

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

## Sequenced backlog

| # | Project | Notes |
| --- | --- | --- |
| P2 | `EmptyState` and a recovery action on `FailureCard` | Small. The source renders empty lists as nothing, and leaves a failed turn with Delete, Copy and Close only |
| P3 | Content and voice conformance | Apply `content-and-voice.md` to existing strings. Copy and tests; no layout risk |
| P4 | Audio level metering and `VoiceBars` | There is no level metering anywhere today. Constrained by the real-time audio callback invariant in AGENTS.md |
| P5 | Conversation `Composer` | **Blocked.** See below |
| P6 | Settings master–detail and autosave | Replaces `SettingsSaveHandler`; a behavioural change deserving its own design |
| P7 | Onboarding and first run | New window and permission flow. YapOps requests Microphone and Speech Recognition lazily today |

Each needs its own spec, plan and implementation cycle. Do not batch them.

## P5 is blocked on a product decision

The design system's `Composer` puts a text input in the conversation panel. It
collides with a universal invariant.

AGENTS.md requires that the menu, recording and agent panels remain
non-activating and preserve the foreground app's focus.
`AgentRunPanelController.swift` enforces it with
`override var canBecomeKey: Bool { false }` and `becomesKeyOnlyIfNeeded = true`.
A text field needs key focus.

The design system's author worked from a read-only copy and could not have known
this. Three resolutions exist, none chosen:

1. **Remain voice-only.** The invariant wins; the composer is never built. The
   panel keeps no way to type to a conversation.
2. **Let the expanded panel become key.** The overlay and menu stay
   non-activating. Needs an explicit design for focus restoration — what happens
   to the app the user was in when the panel takes focus, and what gives it back.
3. **A separate activating input window.** Preserves the invariant on all three
   panels at the cost of another surface.

This is a product decision, not an implementation detail. Nothing else in the
backlog depends on it, so it can stay open.

## Also not adopted

- **`SaveIndicator`** — an autosave receipt, which only makes sense with P6.
  Until then the explicit save in `SettingsSaveHandler` is the model.
- **The Lucide icon set** — this is macOS; use real SF Symbols through
  `Image(systemName:)`. The substitution exists so the design system renders in a
  browser, not because Lucide is the intent.
- **The light appearance scope** — the CSS defines `[data-appearance="light"]`.
  The Swift layer names macOS system colours, which adapt on their own, so no
  parallel light palette is needed or wanted.
