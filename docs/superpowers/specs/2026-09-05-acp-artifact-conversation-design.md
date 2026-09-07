<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# ACP artifact conversation design

## Outcome

The agent conversation becomes a result surface rather than a transcript wrapped
in decorative chrome. ACP images, generated documents, PDFs, and other resources
remain structured from the wire through presentation. The panel gives those
results visual priority, keeps execution detail available without making it the
main event, and uses ordinary macOS preview and file actions.

The panel remains a non-activating floating utility. Streaming, permissions,
follow-ups, cancellation, minimization, and retained terminal conversations keep
their current lifecycle and identity guarantees.

## Current failure

`ACPEventDecoder` validates non-text `ContentBlock` values, then replaces them
with metadata such as `Agent sent resource_link content`. It also discards the
`content` array on `tool_call` and `tool_call_update`. The presentation layer can
therefore render only Markdown, reasoning, tools, plans, permissions, and notices.
A valid generated PDF or image reaches the app and then disappears.

ACP v1 explicitly allows images, embedded resources, and resource links in agent
messages. Tool call content wraps the same content blocks. The implementation must
follow that contract instead of inferring files from Markdown:

- [ACP v1 content](https://agentclientprotocol.com/protocol/v1/content)
- [ACP v1 tool calls](https://agentclientprotocol.com/protocol/v1/tool-calls)

## Chosen approach

Decode supported ACP content into bounded Core value types, reduce artifacts into
stable presentation state, and render a dedicated Results shelf above the ordinary
conversation feed. App-owned services generate previews and perform explicit file
actions. Core never imports AppKit, SwiftUI, Quick Look, or Uniform Type Identifiers.

Rejected alternatives:

- Detect paths and Markdown links in agent prose. This misses structured tool
  output, invents trust from untrusted text, and breaks as soon as wording changes.
- Embed full PDF, office-document, and browser viewers in the floating panel. This
  adds focus, process, security, and lifecycle machinery while making the panel
  noisier than the result it is meant to show.
- Open every generated result automatically. Agents control their output; they do
  not get to move the user into Preview, Finder, or a browser without an explicit
  action.

## Core artifact model

`YapOpsCore` gains public, documented content values for the retained
parts of ACP blocks:

```swift
public enum AgentArtifactPayload: Equatable, Sendable {
    case image(data: Data, mimeType: String)
    case embeddedText(String)
    case embeddedBlob(Data)
    case linked
}

public struct AgentArtifact: Equatable, Sendable {
    public let uri: String?
    public let name: String
    public let title: String?
    public let descriptiveText: String?
    public let mimeType: String?
    public let declaredSize: UInt64?
    public let payload: AgentArtifactPayload
}
```

The initializer remains public because tests, alternate transports, and future ACP
adapters are legitimate producers. Presentation assigns a UUID when an artifact is
first retained. A canonical URI is used only for presentation deduplication, never
as wire identity.

`AgentRunEvent` gains an artifact event for non-text agent message chunks.
`AgentToolCall` and `AgentToolCallUpdate` retain supported regular content from
their `content` arrays. Text tool content remains collapsed execution detail;
artifacts are promoted to Results. Diff and terminal content stay explicitly
unsupported until the corresponding client capabilities exist.

All strings and decoded payloads are validated before retention. Missing required
fields, invalid base64, negative sizes, or content beyond the declared bounds fail
as malformed ACP input. Any bounded URI remains displayable, but only `file`,
`http`, and `https` resources receive an Open action; only existing local files can
be revealed. Raw tool input/output and annotations remain discarded.

## Presentation state

`AgentRunPresentation` owns a bounded `[AgentArtifactPresentation]` alongside the
timeline. It appends artifacts in delivery order, merges repeated updates for the
same canonical local resource, and preserves the first stable display identity.
The immutable array is included in `AgentRunSnapshot`.

Artifacts do not become ordinary message bubbles. This keeps repeated tool status
updates out of the main reading path and allows one generated result to remain
prominent even when the agent later explains it. The plain-text copy export adds a
`Results` section containing retained names and URIs; it never includes embedded
binary data.

Presentation retains at most 32 artifacts and 4 MiB of decoded embedded payload
per conversation. The existing 1 MiB ACP frame limit remains authoritative per
message. Eviction removes the oldest payload first, leaves one omission notice,
and never removes response text merely to preserve binary data.

## Native artifact services

The App target owns two narrow boundaries:

- `AgentArtifactPreviewLoading` loads thumbnails away from the main actor. Local
  files use `QLThumbnailGenerator`; embedded images decode from memory. Remote URLs
  and unsupported embedded document formats receive a semantic file icon rather
  than an automatic network request.
- `AgentArtifactOpening` validates the currently presented run and artifact, then
  opens a link through `NSWorkspace` or reveals a local file in Finder. Embedded
  content is materialized only after an explicit Open action in a run-scoped
  temporary directory and removed when the run is deleted, replaced, or the app
  terminates.

Preview results carry the run and artifact identity across suspension. A thumbnail
or temporary-file callback for a retired run cannot update or open the current
conversation. File I/O, base64 decoding, image decoding, and Quick Look work stay
off the main actor and Swift cooperative executor.

## Conversation experience

The expanded panel grows from 620 by 420 points to a result-friendly preferred size
of 680 by 560 points while retaining screen clamping, saved placement,
minimization, and the recording-overlay handoff. The layout policy reduces that
preferred size to the visible screen frame when necessary, with the scroll view
absorbing the lost height and no internal horizontal scrolling.

The visual hierarchy is:

1. a quiet header with provider, truthful phase, elapsed work time, and minimize;
2. a compact request summary;
3. a Results shelf when artifacts exist;
4. the agent response as the main readable content;
5. collapsed reasoning, tools, plans, notices, failures, and permissions; and
6. phase-specific actions in a stable footer.

The Results shelf uses an adaptive two-column grid. Images use an aspect-fit
preview. PDFs and documents use their system thumbnail, filename, kind, and size.
Each card has an explicit Open action; local linked files also offer Reveal in
Finder through a compact context menu. A failed or unavailable preview leaves the
card actionable and explains the state without exposing a raw path as an error.

The redesign removes the large provider orb, layered radial gradients, glow
shadows, uppercase micro-labels, rounded display fonts, and card borders around
every paragraph. One material, semantic text styles, SF Symbols, standard button
roles, restrained separators, and the profile accent for active state are enough.
Thinking and tool activity stays collapsed after settlement. Permissions and
failures remain visually prominent because they require action or explain why work
stopped.

Streaming preserves stable identity and the existing 50 ms publication cadence.
Structural insertions may fade or settle once; individual tokens and thumbnail
updates do not animate the scroll position. Automatic bottom-follow continues only
while the user remains near the bottom.

## Accessibility and focus

The agent panel remains unable to become key or main. Explicit Open and Reveal
actions may activate the system destination because the user requested that
transition; merely receiving an artifact never changes focus.

Every artifact exposes its title, kind, preview state, and available actions to
VoiceOver. Decorative previews and separators are hidden when their information is
already named. Reduce Motion replaces spatial insertion with opacity. Reduce
Transparency uses an opaque semantic background. Increase Contrast and
Differentiate Without Color retain borders, symbols, copy, and status meaning.

## Testing and verification

Core tests cover image, resource-link, and embedded-resource decoding from agent
messages and tool content; malformed values; deterministic identity; byte/count
bounds; and delivery ordering. Presentation tests cover deduplication, eviction,
copy export, stale events, and snapshots. App tests cover preview policy, local and
remote action routing, on-demand materialization cleanup, stale preview rejection,
result layout, panel sizing, scroll ownership, accessibility labels, and terminal
action guards. Framework effects use fakes; tests never open Finder, Preview, a
browser, or the network.

Completion requires the focused RED/GREEN cycles, the full Swift suite, Thread
Sanitizer for the asynchronous preview and cleanup boundaries, debug app packaging,
`make check`, and `git diff --check`. The real bundle is inspected in light and dark
appearance, Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver, long
and short output, local images, PDFs, documents, broken links, rapid streaming, and
another foreground app.

After verification, the detached worktree commit is merged into the separately
advanced `main` checkout without discarding either history. Verification runs again
on the merged tree, then this worktree is removed through Git's worktree machinery.
The work is complete only when structured ACP artifacts remain usable, the focused
macOS conversation experience is verified, `main` contains the merge, and the
temporary worktree no longer exists.
