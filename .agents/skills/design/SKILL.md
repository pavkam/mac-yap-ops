---
name: design
description: Use when adding, changing, or reviewing a design token, a colour, radius, spacing, type, motion or layout value, an accent treatment, user-visible copy wording, or when deciding whether to adopt part of the YapOps Design System.
---

<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Design

`Sources/YapOpsApp/Design/` owns every colour, radius, spacing, type, motion and
layout value in the application. A view states which token it wants; it does not
restate the number.

This skill owns **what the values are and where they came from**. The `ux` skill
owns **how to build a surface** — layering, materials, controls, accessibility.
Read `.agents/skills/ux/SKILL.md` for the latter; neither skill restates the
other.

## Load only what the task touches

| When the task touches | Read |
| --- | --- |
| A token's value, the accent, the ladders, or what may not be rounded | `references/tokens.md` |
| Status strings, labels, help text, or any user-visible wording | `references/content-and-voice.md` |
| Adding a token, changing one, or an exemption from the gate | `references/adoption.md` |
| Whether to build something the design system describes but the app lacks | `references/elevated-target.md` |

## Three rules that outrank the rest

1. **The profile accent is identity.** Six accents; the user picks one per
   profile and it propagates through that profile's badge, menu row, panel wash,
   orb gradient and permission border. Read it from
   `@Environment(\.profileAccent)`, set it once per surface root with
   `.profileAccent(_:)`, and never hard-code one.
2. **Do not round the numbers.** 7, 9, 11, 13, 15 and 17pt insets and the eleven
   radii are transcribed from SwiftUI literals. Snapping them to a 4- or 8-point
   grid destroys the native read. This is why the gate exists.
3. **Result-first.** Answers before process; artifacts above the timeline;
   thinking collapsed by default.

## Shape the change

1. Find the token that already covers the value. `rg 'Design\.' Sources` before
   adding anything — the layer is small enough to read end to end.
2. If nothing fits, read `references/adoption.md`. A new token needs a role name,
   a doc comment saying where it is used, and a value test.
3. Put the value in `Design/`, the semantic mapping in a presentation type, and
   the rendering in SwiftUI. A view that computes a colour is doing too much.
4. Run `make check-design-tokens` and `swift test --filter Design`.

## Quality gate

A design change is ready only when:

- no styling literal returned to a view, or each one carries a
  `// design-token-exempt:` comment with a real reason;
- the accent reaches every accent-derived value through the environment rather
  than a threaded parameter;
- a new token has a value test pinning it to the literal it replaced;
- the radius ladder still has eleven entries in ascending order;
- copy follows `references/content-and-voice.md` — sentence case, no emoji, no
  exclamation marks, `·` between peer facts, curly quotes around a wake phrase;
- Reduce Motion, Reduce Transparency and Increase Contrast paths still resolve
  through `Design.Motion` and the material fallbacks; and
- appearance is unchanged, or the change is the point and is stated as such.

Do not transcribe a hex value from the design system's CSS into Swift, add a
twelfth radius to avoid picking a tier, or name a token after the one view that
uses it. The layer is small because the application is disciplined; keep it that
way.
