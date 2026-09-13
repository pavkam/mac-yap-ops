<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Tokens

The Swift files are canonical for values. This page owns the rules that govern
them; it does not restate the ladders, because two copies of a number is how a
token layer dies.

| Axis | File |
| --- | --- |
| Accent resolution, label ramp, fills, hairlines | `Design/DesignColor.swift` |
| The accent environment key | `Design/DesignAccent.swift` |
| Size ladder, glyph sizes, tracking | `Design/DesignTypography.swift` |
| Spacing scale and semantic insets | `Design/DesignSpacing.swift` |
| Radius ladder and border weights | `Design/DesignRadius.swift` |
| Glows, material tiers, accent washes | `Design/DesignElevation.swift` |
| Curves, durations, reduce-motion paths | `Design/DesignMotion.swift` |
| Fixed window and element geometry | `Design/DesignLayout.swift` |

## Provenance

Every value was transcribed from a SwiftUI literal this application already
rendered. The design system these tokens are named after was itself
reverse-engineered from `Sources/YapOpsApp/`, from a read-only copy, with no
Figma file and no prior token file. That is why the numbers are unusual, and why
"round it to 8" is always wrong.

Where the design system and the code disagree, **the code wins** and the
disagreement gets recorded. Two are known:

- The system's type ladder omits 9pt. `Design.Glyph.micro` is real and predates
  the system.
- The system records weights as 400/500/600/700. `Design.Text.artifactFallback`
  is `.light`, deliberately: a 36pt placeholder glyph at semibold reads as an
  error state.

## No hex enters Swift

`tokens/colors.css` in the design system lists `#64d2ff` for cyan because CSS
cannot ask macOS for a system colour. Swift can, and does: the six accents and
every semantic colour resolve through the system palette by name, so they keep
tracking appearance, Increase Contrast and future macOS releases.

Those hex values are the *web rendering* of this palette. Never transcribe one.
`Color(red:green:blue:)` and its siblings fail the gate for this reason.

White-alpha fills, the label ramp and hairline weights are literal in
`Design.Alpha` because they are literal in the views. Naming them was the change;
inventing them was not.

## The accent is identity

Six accents, in `WakeProfileAccent` order. The user picks one per profile and it
propagates through that profile's badge, its menu row checkmark, the menu
panel's background wash, the recording orb's gradient, its conversation panel
tint, its provider mark and its permission card border.

Read it from the environment:

```swift
@Environment(\.profileAccent) private var accent
```

Set it once at a surface root, never at a leaf:

```swift
MenuContentView(model: model)
    .profileAccent(headerAccent)
```

Where no profile is active the environment resolves to
`Design.Color.accentFallback`, which is `.secondary` — the same fallback the menu
header rendered before this layer existed.

A per-row accent is the exception that proves the rule: a profile list shows six
different identities at once, so each row uses its own
`profile.accent.swiftUIColor` rather than the surface accent. Everything that
describes *the current surface* reads the environment.

Semantic colour is fixed and never per-profile: red for failures and destructive
actions, orange for partial capture and shortcut recording, green for ready and
saved, indigo only as the app mark's fixed gradient end stop.

## The ladders encode meaning

**Radius encodes scale.** Eleven tiers, ascending, from a 7pt thumbnail clip to
the 32pt overlay capsule. The larger the surface, the softer its corner. Pick the
tier a new surface belongs to; do not add a twelfth to avoid choosing.
`DesignRadiusTests` asserts the count and the ordering.

**Spacing is deliberately off-grid.** 7, 9, 11, 13, 15 and 17 are all real
literals, and `DesignSpacingTests` asserts they stay off a 4-point grid. The odd
values are what make these panels read as native macOS rather than as a web app
in a window.

**Motion never overshoots.** Four curves and eight durations. Nothing bounces,
nothing exceeds 1.16 scale, and the only transform is a 0.98 press. These
animations run for as long as someone is speaking, so they have to be calm
enough to live with.

Route Reduce Motion through `Design.Motion.resolved(_:reduceMotion:)` for an
interactive curve and `resolvedAmbient(_:reduceMotion:)` for a repeating or
spatial one. Ambient motion means "the microphone is open, nothing said yet", so
under Reduce Motion it is removed rather than shortened.

## Materials

Four tiers, used by purpose rather than by the grey they happen to produce:
`Design.Material.floating` for the menu panel and overlay capsule,
`Design.Material.orb` for the orb's glass disc, `Design.Material.panel` for the
conversation panel and the overlay's cancel button.

Blur is for floating surfaces only; nothing inside a window is blurred. Every
tier needs an opaque substitute under `accessibilityReduceTransparency` —
raising a fill from 0.08 to 0.12 is not a substitute.

Cards never carry a drop shadow. Depth on a card comes from its fill and its
hairline. Every shadow in the application is an accent glow; the single black one
sits under the app mark's waveform bars.
