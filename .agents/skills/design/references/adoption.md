<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Adoption

How to add a token, change one, and get past the gate honestly.

## Before adding anything

The layer is small enough to read end to end. Search it first:

```bash
rg 'Design\.' Sources/YapOpsApp --type swift | rg -v '/Design/'
rg 'static let' Sources/YapOpsApp/Design
```

Most "new" values already exist under a role name. A second constant with the
same number and a near-identical role is the failure this layer exists to
prevent.

## Adding a token

1. **Name it for its role, not its call site.** `cardTight`, not
   `thinkingBlockPadding`. A token named after one view becomes dead weight the
   moment that view changes, and it invites a second token for the next view.
2. **Document where it is used.** Every constant carries a `///` comment naming
   the surfaces it appears on. That comment is how the next person decides
   whether to reuse it.
3. **Pin it with a test.** Add an expectation to the matching
   `Tests/YapOpsAppTests/Design*Tests.swift` suite asserting the value. The risk
   this layer carries is a token silently drifting from the literal it replaced
   while every build stays green; the value tests are the only thing that
   catches it.
4. **Check the invariants still hold.** The radius ladder must keep eleven
   ascending entries; the spacing scale must keep its off-grid steps. Both are
   asserted, so a violation fails rather than merely looking wrong.

## Changing a token

Changing a value changes appearance on every surface that uses it. That is the
point of the layer, and it is also the risk.

Before changing one, list its users:

```bash
rg 'Design\.Radius\.row' Sources/YapOpsApp --type swift
```

If the change is right for some users and wrong for others, the token is doing
two jobs and should be split — do not special-case one call site with a literal.

Update the value test in the same commit. A test that gets edited to match a
changed constant with no other change is a signal worth pausing on: either the
appearance change is deliberate and should be stated, or the token drifted.

## The gate

`make check-design-tokens` runs `scripts/check-design-tokens.sh`, which is part
of `make check`. It scans `Sources/YapOpsApp` outside `Design/` for three things:

| Rule | Why |
| --- | --- |
| `cornerRadius: <number>` | Radii encode scale; a literal opts out of the ladder |
| `.system(size: <number>` | Sizes belong to the ramp |
| `Color(red:` / `Color(white:` / `Color(hue:` | Colours are named macOS system colours, never components |

Opacity is deliberately **not** checked. The views use `.opacity(_:)` for
animated state as well as for fills, so a rule covering it would produce false
positives — and a gate that cries wolf gets switched off rather than obeyed.
Widening the rule set is fine once a category is genuinely clean; adding a noisy
rule is not.

## Exemptions

A real exception is suppressed with a comment on the preceding line:

```swift
// design-token-exempt: sized to the host NSImage, not to the type ramp
.font(.system(size: measuredHeight))
```

The reason is mandatory and the gate fails on an empty one, so the escape hatch
stays auditable. Grep for them during review:

```bash
rg 'design-token-exempt' Sources/YapOpsApp
```

A growing list of exemptions in one area means the layer is missing a token, not
that the gate is wrong.

## Verifying a migration is a no-op

Snapshot tests are not available here: a UI test that touches process-global
AppKit state passes alone and crashes in the suite, and serialising within one
suite does not isolate it from others. So the evidence is:

1. `swift test --filter Design` — every token still equals its literal.
2. `make check-design-tokens` — no literal returned to a view.
3. The diff itself, read one file at a time against its origin.
4. `make app && open .build/YapOps.app` for anything touching a dense surface.
   `swift run` does not validate bundle resources, `Info.plist`, signing or
   privacy grants, so it cannot stand in for the built bundle.
