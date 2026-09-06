<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Agent Markdown Rendering Design

## Problem

Agent output is currently split by a hand-written line parser and rendered as a
stack of custom SwiftUI blocks. It handles a narrow happy path, but it does not
implement CommonMark or GitHub-flavored Markdown. Multiline and nested blocks,
task lists, tables, escaped syntax, and streaming-incomplete markup therefore
render incorrectly or as plain text.

The panel already receives bounded, coalesced Markdown snapshots and owns
scroll-follow behavior. The renderer should improve document fidelity without
moving presentation policy into Core or disturbing panel identity, focus, and
scroll ownership.

## Decision

Replace the visual block parser with the native SwiftUI renderer `MarkdownUI`,
pinned to version `2.4.1`.

The package is a better fit than the alternatives considered:

- It uses the reference `cmark-gfm` parser and supports the response vocabulary
  requested by Voice Activation: headings, nested lists, task lists, tables,
  block quotes, links, inline code, fenced code, and thematic breaks.
- Version 2.4.1 is a mature MIT release with macOS 12+ support and an established
  SwiftUI theming surface.
- Custom block and inline image providers can make provider output
  non-networking while keeping the rest of the document native.
- It avoids a `WKWebView` inside the panel's existing SwiftUI scroll view.

`SwiftStreamingMarkdown` was the first choice, but its version 0.7.0 dependency
graph does not build under this repository's SwiftPM toolchain because its
pinned highlighter relies on unavailable SwiftUI macro plugins. Textual is
MarkdownUI's active successor, but version 0.5.0 has unresolved content-update
issues on the path this streaming panel needs. HTML in WebKit would require
sanitization, a content-security policy, navigation delegation, intrinsic-height
bridging, and selection/scroll preservation on every update.

## Rendering Boundary

`AgentMarkdownView` remains the app-owned rendering boundary. It passes the raw,
bounded Markdown snapshot to `Markdown`, supplies an app-specific theme and
non-networking image providers, and installs a safe link-opening policy. The
rest of the panel continues to know only about `AgentMarkdownView`.

`AgentMarkdownRenderStyle` defines the two typography contexts:

- `response`: 13-point body copy and the existing 18/16/15-point heading
  hierarchy.
- `detail`: 11-point secondary copy for expanded reasoning details.

Both use semantic colors, compact block spacing, monospaced code, disabled
remote images, and native SwiftUI text selection. The panel continues to own
its non-activating window behavior.

## Links and Untrusted Content

Agent Markdown is untrusted. Image loading stays disabled. Link activation is
explicitly limited to `http` and `https`; unsupported or missing schemes are
discarded. A supported link still opens only after the user clicks it through
the system URL action.

Raw HTML is not executed because rendering remains native. No Markdown source,
link destination, or rendered content is added to diagnostics.

## Streaming and Layout

The existing presentation layer continues to publish bounded snapshots at its
coalesced cadence. `Markdown` reparses when the snapshot changes and updates its
native block tree. The outer panel remains the sole vertical scroll owner. Code
blocks and tables may scroll horizontally.

No per-token animation is added, preserving Reduce Motion behavior. Existing
bottom-follow logic remains conditional on the user's scroll position.

## Verification

Automated coverage protects the app-owned policy and integration boundary:
unsafe URL schemes are rejected; images fail closed; representative GFM and
incomplete streaming snapshots rasterize; long code stays horizontally bounded;
and response/detail styles keep the intended typography scale.

The focused tests must fail before the policy exists, then pass after the
implementation. The completion gate is the focused suite, full `swift test`,
the debug app bundle, `make check`, and `git diff --check`. Manual inspection
should cover a representative Markdown fixture, light/dark appearance,
selection, links, long code, tables, streaming growth, and user-owned scroll.
