<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Design token foundation design

## Purpose

A YapOps Design System was produced from a read-only copy of this repository.
Its own readme records the provenance: every colour, radius, padding, duration
and type size was transcribed from `Sources/YapOpsApp/` SwiftUI literals, and no
Figma file, brand book or token file existed beforehand. The system is therefore
a mirror of this application rather than a new visual language, and its unusual
numbers — 7, 9, 11, 13, 17 point insets, eleven distinct radii, white alphas at
3.5%, 5.5% and 11% — are already the values this application renders today.

What the application lacks is a place to keep them. There is no token layer in
Swift. Styling literals are spread across 254 call sites in 18 view files, with
61% concentrated in `MenuContentView`, `AgentHarnessSettingsView`,
`RecordingOverlayView` and `AgentRunPanelContent`. The same 0.075 fill is typed
in several files with no relationship between the copies, the eleven radii are
indistinguishable from ad-hoc numbers at their call sites, and the profile
accent — which the system names as identity, not decoration — is threaded by
hand and falls back to `.secondary` when absent.

This project gives those values one home, migrates every call site onto it, and
adds a gate that keeps them there. It is the enabling phase for the wider
adoption recorded in `.agents/skills/design/references/elevated-target.md`; it
changes no pixels.

## Goals

- Establish `Sources/YapOpsApp/Design/` as the single owner of colour,
  typography, spacing, radius, elevation, motion and layout values.
- Migrate all 254 styling call sites onto that layer with no intended visual
  change.
- Make the profile accent structurally available instead of manually threaded,
  so that "never hard-code blue" becomes enforceable rather than aspirational.
- Add `scripts/check-design-tokens.sh` to `make check` so new raw literals fail
  the build.
- Publish the design system as a project skill at `.agents/skills/design` and a
  user-facing guide at `docs/design-system.md`.
- Reconcile the existing UX guidance, which currently forbids parts of this
  work, so that a later agent cannot cite it to revert the token layer.
- Record the unadopted parts of the design system as a decomposed backlog with
  their open questions intact.

## Non-goals

- Changing any rendered appearance. This phase is a substitution.
- Vendoring the design system. The zip's 265 files stay outside the repository;
  see "Why nothing is vendored" below.
- Building the design system's elevated-target surfaces — level metering, the
  conversation composer, onboarding, Settings master–detail, autosave,
  `EmptyState`, `FailureCard` recovery. Each is its own project.
- Changing user-visible copy. The content and voice contract is recorded in this
  phase and enforced in a later one.
- Introducing a cross-platform or web rendering of the token layer.

## Why nothing is vendored

Every binary asset in the design system already exists in this repository. The
six interface cues and `YapOps.icns` live in `Sources/YapOpsApp/Resources/` and
are already annotated in `REUSE.toml`; the system copied them out of here.
`assets/yapops-mark.svg` is a transcription of `YapOpsMark.swift`, which draws
the mark in code. The 74 Lucide icons are a substitution the system's own readme
instructs consumers to discard on macOS, where the real SF Symbols are
available.

Vendoring would therefore add a second copy of assets we own, plus ~200 files of
React and CSS that a SwiftPM repository cannot build, test or lint — and an ISC
licensing obligation for icons we will not use. The CSS token files and the 18
specimen cards are the only material worth keeping, and their content is
transcribed into the Swift layer and the skill references instead.

The archive remains the historical source. This document and
`.agents/skills/design/references/tokens.md` are the durable record of what it
contained.

## Architecture

### Placement

AGENTS.md requires framework-independent policy in `YapOpsCore` and SwiftUI,
AppKit, Security, Speech, Carbon and Service Management adapters in
`YapOpsApp`. Tokens resolve to `Color`, `Font`, `Animation` and `Material`
values, so they belong in the App target. `AgentRunPanelLayout` already
establishes the precedent of presentation geometry living there.

One file per axis keeps each inside the 700-line Swift limit:

| File | Owns |
| --- | --- |
| `Design/DesignColor.swift` | Accent resolution, the label ramp, white-alpha fills, hairlines |
| `Design/DesignTypography.swift` | The twelve-step size ladder and the semantic type roles |
| `Design/DesignSpacing.swift` | The spacing scale and the semantic insets |
| `Design/DesignRadius.swift` | The eleven-radius ladder and the five border weights |
| `Design/DesignElevation.swift` | Accent glows, the four material tiers, the three accent washes |
| `Design/DesignMotion.swift` | Four curves, eight durations, the reduce-motion paths |
| `Design/DesignLayout.swift` | Fixed window sizes and element sizes |

Values are namespaced as `Design.Radius.menuRow`, `Design.Motion.panel`,
`Design.Color.fillRow`.

### The radius ladder stays a ladder

The system's central claim about geometry is that eleven radii encode scale:
the larger the surface, the softer its corner. Naming one constant per call site
would grow that to roughly thirty names within a release and destroy the
property being preserved.

`Design.Radius` therefore declares exactly eleven constants, using the tier
names from the system's own readme:

```
thumbnail 7 · field 8 · notice 9 · innerCard 10 · artifact 11 · row 12
hero 13 · message 15 · panelCompact 18 · panelExpanded 22 · capsule 32
```

Adding a twelfth requires a deliberate edit to a file whose doc comment explains
why there are eleven. That is the intended friction.

The same reasoning applies to spacing: the scale is the off-grid set the
application already uses, and it must not be snapped to a 4- or 8-point grid.
The semantic insets (`menuGutter`, `cardTight`, `panelGutter`,
`settingsCard`) name the recurring groupings rather than every occurrence.

### No hex enters Swift

`tokens/colors.css` lists `#64d2ff` for cyan because CSS cannot ask macOS for a
system colour. Swift can. `Design.Color` resolves the six `WakeProfileAccent`
cases through `NSColor.systemCyan` and its siblings, exactly as
`WakeProfileAccentSwatch` does today, so the accents continue to track the
system palette across appearance, increased contrast and future macOS releases.

The hex values are recorded in the skill reference as the web rendering only,
with an explicit instruction never to transcribe them into Swift.

White-alpha fills, the label ramp and the hairline weights are literal in this
layer because they are literal in the views today. The migration gives them
names; it does not invent them.

### Accent becomes environment

This is the only structural change in the phase.

Today the accent is passed by hand — `snapshot.accent.swiftUIColor`,
`profile.accent.swiftUIColor` — and `MenuContentView` falls back to `.secondary`
when no profile is active. The extension providing `swiftUIColor` currently
lives inside `Settings/SettingsView.swift`, which is not its subject.

The migration adds a `\.profileAccent` key to `EnvironmentValues`, set once at
each surface root: the menu panel, the recording overlay, the conversation panel
and the Settings detail pane. `Design.Color` reads the accent from the
environment, so accent-derived values — the menu wash, the orb gradient, the
permission border, the provider mark glow — are correct in any descendant
without threading a parameter through it.

`WakeProfileAccent.swiftUIColor` moves from `SettingsView.swift` to
`DesignColor.swift`. The existing `.secondary` fallback is preserved verbatim as
a named token rather than changed, because this phase alters no appearance.

The payoff is enforceability: once accent flows through the environment, a
literal accent colour at a call site is unambiguously a defect, and the gate can
say so.

## The gate

`scripts/check-design-tokens.sh` joins `check-license`, `check-agent-guidance`,
`check-structure`, `check-documentation` and `check-packaging` in `make check`.
It is the Swift analogue of the design system's `_adherence.oxlintrc.json`.

It scans `Sources/YapOpsApp` excluding `Sources/YapOpsApp/Design/`, and starts
deliberately narrow — three rules with a high signal-to-noise ratio:

1. a numeric literal in `cornerRadius:`;
2. a numeric literal in `.system(size:)`;
3. colour construction from components or hex, such as `Color(red:green:blue:)`.

A broader scan for `.opacity(` is rejected for this phase because the views use
it for animated state as well as for styling, and a gate with false positives
gets disabled rather than obeyed. Rules widen once the layer has settled and the
remaining exceptions are understood.

An inline `// design-token-exempt: <reason>` comment on the preceding line
suppresses a finding. The reason is mandatory, and the script fails on an
exemption with an empty reason, so the escape hatch stays auditable.

## Verification

Proving that 254 substitutions changed nothing needs evidence, and snapshot
tests cannot supply it here. AGENTS.md records the failure mode directly: a UI
test that passes alone but crashes in the suite has usually touched
process-global AppKit state, and serialising within one suite does not isolate
it from others.

Two mechanisms instead:

- **`DesignTokenTests`** asserts every token equals the literal it replaces —
  `#expect(Design.Radius.menuRow == 12)` and so on across all seven axes. The
  actual risk in this work is transcription error, and this catches exactly that,
  deterministically, with no AppKit involvement.
- **File-by-file migration.** The implementation plan sequences one view file
  per step, so each diff is reviewable against its origin. The four dense files
  are split across their own steps rather than batched.

Beyond those: `make check` must pass with the new gate active, `swift test` must
pass, and the four dense view files are manually exercised in the built bundle,
since `swift run` does not validate bundle resources, `Info.plist` or privacy
grants.

## Skill and documentation

### Project skill

`.agents/skills/design/SKILL.md` is a second-stage router, subject to the
150-line limit, with `name: design`, a description beginning "Use when", and a
routing row in AGENTS.md. AGENTS.md currently stands at 145 lines, so the row
fits within its own limit without restructuring.

| Reference | Owns |
| --- | --- |
| `references/tokens.md` | The rules: the ladders, accent propagation, what must not be rounded, why no hex enters Swift |
| `references/content-and-voice.md` | The copy contract: status message rhythm, the middle-dot separator, curly quotes for spoken phrases, sentence case, the words the product owns |
| `references/adoption.md` | Adding or changing a token, the gate, the exemption process |
| `references/elevated-target.md` | The unadopted backlog, the non-adoption record, the open question on the composer |

The Swift files stay canonical for values; the references own the rules and
point at the source. Two copies of a number is how a token layer dies, so no
reference restates the ladders in full.

### Cross-linking, not duplicating

`.agents/skills/ux` already claims colour, materials, typography, symbols,
spacing and reusable styling. The design skill owns *what the values are and
where they come from*; the ux skill continues to own *how to build a surface*.
Each routing table gains a row pointing at the other, and neither restates the
other's material.

### Guidance reconciliation

Three pieces of existing guidance currently contradict this work and must be
amended in the same change, or they remain grounds to revert it:

| Location | Today | Becomes |
| --- | --- | --- |
| `ux/references/visual-language.md` | "Never hard-code the apparent RGB value of a macOS system color." | Name macOS system colours through `Design.Color`; the rule against apparent RGB values is retained and strengthened, since the token layer is what makes it checkable. |
| `ux/references/visual-language.md` | "Do not assign a different radius to every view." | Points at the eleven-radius ladder. The intent is unchanged — today's scattered literals are the violation this rule was written against. |
| `ux/SKILL.md` quality gate | "Do not create a generic design system for one use." | Narrowed to forbid a bespoke abstraction for a single call site, which is what it meant, rather than the shared token layer. |

### User-facing documentation

`docs/design-system.md` is added and registered in `docs/index.md` under
"Understand the system" and in the ownership table in `docs/documentation.md`.
It owns the token ladders, accent propagation, the content and voice contract,
and the record of what was deliberately not adopted.

## Risks

- **A migration that claims to be a no-op but is not.** Mitigated by the value
  tests and per-file diffs; a token whose value differs from the literal it
  replaces fails a test rather than shipping a quiet visual change.
- **A gate that cries wolf gets switched off.** Mitigated by starting at three
  rules and requiring a written reason for each exemption.
- **AGENTS.md is five lines below its limit.** The routing row fits, but any
  later addition in the same change will not. Keep the row to one line.
- **The skill and the ux skill drifting into two accounts of the same subject.**
  Mitigated by the ownership split above and by keeping values in Swift only.

## Open question, carried forward

The design system's `Composer` — a text input in the conversation panel —
conflicts with a universal invariant. AGENTS.md requires that the menu,
recording and agent panels remain non-activating and preserve the foreground
app's focus, and `AgentRunPanelController.swift:10` enforces it with
`override var canBecomeKey: Bool { false }`. A text field needs key focus.

The system's author worked from a read-only copy and could not have known. This
is a product decision, not an implementation detail, and nothing in P1 depends
on it. It is recorded in `references/elevated-target.md` with the three known
resolutions — remain voice-only; allow the expanded panel alone to become key;
or introduce a separate activating input window — and left undecided.

## Sequenced backlog

Recorded in `references/elevated-target.md`. P1 is this document.

| # | Project | Notes |
| --- | --- | --- |
| P2 | `EmptyState` and `FailureCard` recovery action | Small; exercises the token layer under real use |
| P3 | Content and voice conformance | Copy and tests; no layout risk |
| P4 | Audio level metering and `VoiceBars` | Constrained by the real-time audio callback invariant |
| P5 | Conversation `Composer` | Blocked on the open question above |
| P6 | Settings master–detail and autosave | Replaces `SettingsSaveHandler`; a behavioural change |
| P7 | Onboarding and first run | New window and permission flow |
