<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Agent Markdown Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the agent panel's partial Markdown renderer with a native, streaming-aware GFM renderer while preserving privacy, focus, selection, and scroll ownership.

**Architecture:** Keep `AgentMarkdownView` as the single app-owned boundary and delegate parsing/rendering to `MarkdownUI`. Build semantic app typography, non-networking image providers, and untrusted-link policy locally; leave presentation bounds and vertical scrolling unchanged.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, SwiftPM, Swift Testing, `MarkdownUI` 2.4.1, and its `cmark-gfm` parser.

**Spec:** `docs/superpowers/specs/2026-09-05-agent-markdown-rendering-design.md`

## Global Constraints

- Support macOS 15 and preserve the non-activating `NSPanel` contract.
- Keep agent content bounded and out of diagnostics.
- Do not enable remote Markdown images or execute raw HTML.
- Allow only user-clicked `http` and `https` links.
- Keep the outer panel as the only vertical scroll owner.
- Do not add per-token animation or a second vertical scroll owner.
- Preserve four-space indentation and MIT SPDX headers.

---

### Task 1: Pin the renderer and protect app-owned policy

**Files:**
- Modify: `Package.swift`
- Create: `Tests/VoiceActivationAppTests/AgentMarkdownRenderingTests.swift`
- Create: `Sources/VoiceActivationApp/AgentMarkdownRendering.swift`

**Interfaces:**
- Produces: `AgentMarkdownLinkPolicy.allows(_:)`, non-networking image
  providers, and `AgentMarkdownRendering.theme(accent:style:)`.
- Consumes: `MarkdownUI.Theme` and semantic SwiftUI colors.

- [ ] **Step 1: Add the pinned SwiftPM dependency**

Add `MarkdownUI` at exact version `2.4.1` and link its product only to
`VoiceActivationApp`.

- [ ] **Step 2: Write failing policy tests**

Add tests that require:

```swift
let webURL = try #require(URL(string: "https://example.com"))
let imageURL = try #require(URL(string: "https://example.com/private.png"))
#expect(AgentMarkdownLinkPolicy.allows(webURL))
#expect(AgentMarkdownRenderStyle.response.bodyFontSize == 13)
await #expect(throws: AgentMarkdownImageError.disabled) {
    try await AgentMarkdownInlineImageProvider().image(with: imageURL, label: "private")
}
```

- [ ] **Step 3: Verify RED**

Run `swift test --filter AgentMarkdownRenderingTests` and confirm compilation
fails because the app-owned rendering policy does not exist.

- [ ] **Step 4: Implement the minimal policy**

Create the style enum, semantic `Theme`, rejecting image providers, and the
`http`/`https` URL allowlist.

- [ ] **Step 5: Verify GREEN**

Run `swift test --filter AgentMarkdownRenderingTests` and require zero failures.

### Task 2: Replace the visual parser at the existing view boundary

**Files:**
- Modify: `Sources/VoiceActivationApp/AgentMarkdownView.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPanelContent.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPanelActivity.swift`
- Read: `Sources/VoiceActivationApp/AgentMarkdownFormatter.swift`
- Read: `Tests/VoiceActivationAppTests/AgentMarkdownFormatterTests.swift`

**Interfaces:**
- Consumes: `AgentMarkdownRendering.theme(accent:style:)` and
  `AgentMarkdownLinkPolicy.allows(_:)`.
- Produces: the unchanged `AgentMarkdownView` panel boundary backed by
  `MarkdownUI.Markdown`.

- [ ] **Step 1: Replace the renderer**

Make `AgentMarkdownView` accept `accent` and `style`, render `Markdown`, and
install both non-networking image providers plus an `OpenURLAction` that returns
`.systemAction(url)` only for allowed links and `.discarded` otherwise.

- [ ] **Step 2: Route the two visual roles**

Pass `.response` for visible agent replies and `.detail` for thought/reasoning
content. Remove outer font/foreground modifiers that cannot override attributed
AppKit runs.

- [ ] **Step 3: Keep narration parsing scoped**

Confirm `AgentMarkdownFormatter` remains narration-only after the view switches
to MarkdownUI. Retain its block reduction and focused speech tests until
narration is deliberately migrated.

- [ ] **Step 4: Verify the focused suite**

Run `swift test --filter 'AgentMarkdownRenderingTests|AgentMarkdownFormatterTests'`
and require zero failures.

### Task 3: Document and verify the shipped boundary

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/agent-conversations.md`
- Modify: `docs/development.md`
- Modify: `Package.resolved`

**Interfaces:**
- Consumes: the verified renderer behavior and dependency graph.
- Produces: current user and architecture documentation plus a reproducible
  SwiftPM resolution.

- [ ] **Step 1: Update the owning guides**

Describe native GFM rendering, task lists/tables/code blocks, disabled remote
images, safe links, the app-owned renderer boundary, and its focused tests.

- [ ] **Step 2: Run proportional verification**

Run, in order:

```bash
swift test --filter 'AgentMarkdownRenderingTests|AgentMarkdownFormatterTests'
swift test
CONFIGURATION=debug make app
make check
git diff --check
```

- [ ] **Step 3: Inspect the final diff**

Confirm `Package.resolved` changed only for the selected renderer and its
transitive dependencies, no file exceeds repository limits, and no unrelated
work was modified.
