<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Design system

Use this guide to find the value a surface should use, understand why the numbers
are unusual, and know what the design system describes that YapOps deliberately
does not build.

`Sources/YapOpsApp/Design/` owns every colour, radius, spacing, type, motion and
layout value in the application. A view names the token it wants; it does not
restate the number.

## Where a value lives

| Axis | File | Holds |
| --- | --- | --- |
| Colour | `Design/DesignColor.swift` | Accent resolution, opacity ladder, semantic colours |
| Accent | `Design/DesignAccent.swift` | The `\.profileAccent` environment key |
| Type | `Design/DesignTypography.swift` | Size roles, glyph sizes, tracking |
| Spacing | `Design/DesignSpacing.swift` | Padding and stack spacing |
| Radius | `Design/DesignRadius.swift` | The eleven-tier ladder, border weights |
| Elevation | `Design/DesignElevation.swift` | Glows, material tiers, accent washes |
| Motion | `Design/DesignMotion.swift` | Curves, durations, Reduce Motion paths |
| Layout | `Design/DesignLayout.swift` | Fixed window and element geometry |

The Swift source is canonical. `.agents/skills/design/` holds the rules that
govern it, and `make check-design-tokens` enforces them.

## Why the numbers are unusual

A YapOps Design System was produced from a read-only copy of this repository. No
Figma file, brand book or token file existed before it; every value in it was
transcribed from the SwiftUI literals this application already rendered.

So the design system is a mirror of the app rather than a new visual language,
and the odd values — 7, 9, 11, 13, 15 and 17pt insets, eleven distinct radii,
white alphas at 3.5%, 5.5% and 11% — are already what YapOps draws. Adopting the
tokens changed no pixels; it gave the values names and one home.

Snapping the spacing scale to a 4- or 8-point grid is the single change that
would make these panels stop reading as native macOS. The gate and
`DesignSpacingTests` both exist to prevent it.

Where the design system and the code disagree, the code wins. Two disagreements
are known and recorded in `.agents/skills/design/references/tokens.md`: the
system's type ladder omits the app's 9pt glyph, and it records weights as
400–700 while the artifact placeholder is deliberately `.light`.

## The profile accent

Six accents — cyan, blue, purple, pink, orange, green, in `WakeProfileAccent`
order. The user picks one per profile, and it propagates through everything that
profile touches: its badge, its menu row checkmark, the menu panel's background
wash, the recording orb's gradient, its conversation panel tint, its provider
mark and its permission card border.

The accent is identity, not decoration. A surface reads it from the environment:

```swift
@Environment(\.profileAccent) private var accent
```

and a surface root establishes it once:

```swift
MenuContentView(model: model)
    .profileAccent(headerAccent)
```

Where no profile is active this resolves to `.secondary`. A profile list is the
exception: it shows six identities at once, so each row uses its own accent
rather than the surface's.

Semantic colour is fixed and never per-profile — red for failures and
destructive actions, orange for partial capture and shortcut recording, green for
ready and saved, indigo only as the app mark's gradient end stop.

No colour is built from components. The six accents and every semantic colour are
macOS system colours requested by name, so they keep tracking appearance,
Increase Contrast and future releases. The hex values in the design system's CSS
are that palette's web rendering and are never transcribed into Swift.

## Copy

The voice is part of the system. Status messages are a two-word title plus a
one-clause detail; `·` joins peer facts; a wake phrase is always rendered with
curly quotes; sentence case everywhere except the 10pt tracked eyebrow; no emoji
and no exclamation marks in UI copy.

`.agents/skills/design/references/content-and-voice.md` is the full contract.

## The elevated target

The design system's brief was "the elevated target", so it described several
surfaces this application did not have. All of them are now built: level
metering and `VoiceBars`, the conversation composer, first run, autosave and
`SaveIndicator`, the Profiles master–detail restructure, `EmptyState`, and
recovery on failures. The full record — including the one panel invariant the
composer required reinterpreting, and the known gap in the composer's own
microphone level — is in
`.agents/skills/design/references/elevated-target.md`.

The archive itself is not vendored. Every asset in it already exists under
`Sources/YapOpsApp/Resources/`, and its React components and Lucide icons have no
use in a native macOS app.

## Related guides

- [UX and interaction](../.agents/skills/ux/SKILL.md) — how to build a surface.
- [Wake profiles](wake-profiles.md) — what an accent is attached to.
- [Development](development.md) — repository layout and the change workflow.
