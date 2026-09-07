<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# ACP Artifact Conversation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve generated ACP images, PDFs, and documents as usable results and make the agent conversation panel a quiet, result-first macOS surface.

**Architecture:** Decode bounded structured artifacts in `YapOpsCore`, carry them through the existing ordered delivery queue, and reduce them into stable presentation state. App-owned thumbnail and file-action adapters handle Quick Look, Image I/O, Finder, `NSWorkspace`, and temporary files; SwiftUI renders a dedicated Results shelf without making the floating panel activating.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, AppKit, QuickLookThumbnailing, ImageIO, UniformTypeIdentifiers, Foundation

**Spec:** `docs/superpowers/specs/2026-09-05-acp-artifact-conversation-design.md`

## Global Constraints

- The panel remains a non-activating floating utility.
- Presentation retains at most 32 artifacts and 4 MiB of decoded embedded payload per conversation.
- The existing 1 MiB ACP frame limit remains authoritative per message.
- Only `file`, `http`, and `https` resources receive an Open action; only existing local files can be revealed.
- Embedded content is materialized only after an explicit Open action in a run-scoped temporary directory.
- Merely receiving an artifact never changes focus.
- Streaming preserves stable identity and the existing 50 ms publication cadence.
- File I/O, base64 decoding, image decoding, and Quick Look work stay off the main actor and Swift cooperative executor.
- Tests never open Finder, Preview, a browser, or the network.
- Preserve the separately active Markdown-rendering work in `/Users/alex/Development/yapops`; do not stage, stash, rewrite, or discard it.

---

### Task 1: Decode ACP artifact content

**Files:**
- Modify: `Sources/YapOpsCore/AgentRunEvent.swift`
- Modify: `Sources/YapOpsCore/ACPEventDecoder.swift`
- Test: `Tests/YapOpsCoreTests/ACPEventDecoderTests.swift`

**Interfaces:**
- Produces: `AgentArtifactPayload`, `AgentArtifact`, and `AgentToolCallContent` public Core values.
- Produces: internal `AgentArtifactLimits` shared by decoding and delivery normalization.
- Produces: defaulted `content: [AgentToolCallContent]` on `AgentToolCall` and `AgentToolCallUpdate`.
- Produces: `AgentRunEvent.artifact(AgentArtifact)` for non-text agent message content.
- Consumes: the existing one-frame `ACPEventDecoder.event(from:) -> AgentRunEvent?` interface.

- [ ] **Step 1: Add failing decoder tests for agent-message artifacts**

Extend `event_WhenStableSessionUpdatesArrive_ReturnsTypedEvents` with an image and a PDF link, then replace the old metadata-only assertion:

```swift
let imageData = Data("png".utf8)
let image = AgentArtifact(
    uri: "file:///tmp/preview.png",
    name: "preview.png",
    title: nil,
    descriptiveText: nil,
    mimeType: "image/png",
    declaredSize: nil,
    payload: .image(data: imageData, mimeType: "image/png"))
#expect(try decoder.event(from: message(update:
    #"{"sessionUpdate":"agent_message_chunk","messageId":"image-1","content":{"type":"image","data":"cG5n","mimeType":"image/png","uri":"file:///tmp/preview.png"}}"#
)) == .artifact(image))

let document = AgentArtifact(
    uri: "file:///tmp/report.pdf",
    name: "report.pdf",
    title: "Security report",
    descriptiveText: "Generated report",
    mimeType: "application/pdf",
    declaredSize: 1_024,
    payload: .linked)
#expect(try decoder.event(from: message(update:
    #"{"sessionUpdate":"agent_message_chunk","content":{"type":"resource_link","uri":"file:///tmp/report.pdf","name":"report.pdf","title":"Security report","description":"Generated report","mimeType":"application/pdf","size":1024}}"#
)) == .artifact(document))
```

- [ ] **Step 2: Add failing decoder tests for tool content and malformed payloads**

Assert both initial and update tool events retain regular text and artifact wrappers, while valid `diff` and `terminal` wrappers are ignored:

```swift
let update = try #require(try decoder.event(from: message(update:
    #"{"sessionUpdate":"tool_call_update","toolCallId":"render","status":"completed","content":[{"type":"content","content":{"type":"text","text":"Rendered"}},{"type":"content","content":{"type":"resource_link","uri":"file:///tmp/report.pdf","name":"report.pdf","mimeType":"application/pdf"}},{"type":"diff","path":"/tmp/a","newText":"x"},{"type":"terminal","terminalId":"term-1"}]}"#
)))
guard case let .toolCallUpdate(toolUpdate) = update else {
    Issue.record("Expected tool update")
    return
}
#expect(toolUpdate.content == [.text("Rendered"), .artifact(document)])
```

Add malformed fixtures for invalid base64, negative `size`, URI over 4 KiB, MIME type over 256 bytes, display metadata over 8 KiB, and decoded embedded payload over 768 KiB.

- [ ] **Step 3: Run the focused test and confirm RED**

Run:

```bash
swift test --filter 'YapOpsCoreTests.ACPEventDecoderTests'
```

Expected: compilation fails because the artifact types, event case, and tool content do not exist.

- [ ] **Step 4: Add the public Core values with DocC**

Add these shapes to `AgentRunEvent.swift`; every declaration, case, member, and initializer receives useful `///` documentation:

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

    public init(
        uri: String?,
        name: String,
        title: String?,
        descriptiveText: String?,
        mimeType: String?,
        declaredSize: UInt64?,
        payload: AgentArtifactPayload)
}

public enum AgentToolCallContent: Equatable, Sendable {
    case text(String)
    case artifact(AgentArtifact)
}

enum AgentArtifactLimits {
    static let maximumURIBytes = 4 * 1_024
    static let maximumMIMETypeBytes = 256
    static let maximumDisplayTextBytes = 8 * 1_024
    static let maximumEmbeddedPayloadBytes = 768 * 1_024
}
```

Add `content: [AgentToolCallContent] = []` to both tool initializers and add `.artifact(AgentArtifact)` to `AgentRunEvent`.

- [ ] **Step 5: Parse supported content blocks and tool wrappers**

Replace the metadata-only `ContentChunk` result with a private decoded enum:

```swift
private enum DecodedContentBlock {
    case text(String)
    case artifact(AgentArtifact)
    case unsupported(String)
}
```

Use `AgentArtifactLimits` in `ACPEventDecoder`: URI 4 KiB, MIME type 256 bytes, name/title/description 8 KiB each, and decoded embedded data 768 KiB. `Data(base64Encoded:)` must succeed. A resource link requires `name` and `uri`; an embedded resource derives its name from the URI's last path component, falling back to `Resource`; an image derives `Image` when its optional URI has no filename. Optional `title`, `description`, `mimeType`, and nonnegative integral `size` are retained.

Decode `tool_call.content` and `tool_call_update.content` through:

```swift
private func toolContent(_ value: ACPJSONValue?) throws -> [AgentToolCallContent] {
    guard let value else { return [] }
    return try array(value, named: "content").compactMap { wrapperValue in
        let wrapper = try object(wrapperValue, named: "tool content")
        switch try string(wrapper["type"], named: "tool content.type") {
        case "content":
            switch try decodedContentBlock(wrapper["content"]) {
            case .text(let text): return .text(text)
            case .artifact(let artifact): return .artifact(artifact)
            case .unsupported: return nil
            }
        case "diff":
            _ = try string(wrapper["path"], named: "tool content.path")
            _ = try string(wrapper["newText"], named: "tool content.newText")
            return nil
        case "terminal":
            _ = try opaqueString(wrapper["terminalId"], named: "tool content.terminalId")
            return nil
        default:
            throw malformed("tool content.type")
        }
    }
}
```

Keep audio as a validated metadata summary. Never retain annotations, `rawInput`, or `rawOutput`.

- [ ] **Step 6: Run the focused tests and confirm GREEN**

Run:

```bash
swift test --filter 'YapOpsCoreTests.ACPEventDecoderTests'
```

Expected: all decoder tests pass with structured image/resource events and tool content.

- [ ] **Step 7: Commit the decoder contract**

```bash
git add Sources/YapOpsCore/AgentRunEvent.swift Sources/YapOpsCore/ACPEventDecoder.swift Tests/YapOpsCoreTests/ACPEventDecoderTests.swift
git commit -m "feat: decode ACP artifact content"
```

---

### Task 2: Carry artifacts through bounded ordered delivery

**Files:**
- Modify: `Sources/YapOpsCore/AgentRunEvent.swift`
- Modify: `Sources/YapOpsCore/AgentRunEventNormalization.swift`
- Modify: `Sources/YapOpsCore/AgentRunEventDeliveryEntry.swift`
- Modify: `Sources/YapOpsCore/AgentRunEventDeliveryQueue.swift`
- Modify: `Sources/YapOpsCore/AgentRunEventDelivery.swift`
- Test: `Tests/YapOpsCoreTests/AgentRunEventDeliveryTests.swift`

**Interfaces:**
- Consumes: `AgentRunEvent.artifact` and artifact-bearing tool events from Task 1.
- Produces: independent artifact byte accounting with a 4 MiB pending limit.
- Produces: `AgentRunEventDeliveryNoticeKind.artifactTruncated`.
- Preserves: tool status before promoted artifact events in the same wire update.

- [ ] **Step 1: Add failing queue tests for ordering and artifact pressure**

Use the file's `DeliveryHandlerGate` and `DeliveryEventRecorder` to hold the consumer. Send a tool update containing one text detail and one artifact, then assert the handler receives the stripped tool update followed by `.artifact`. Add 33 artifacts totaling more than 4 MiB and assert the queue remains bounded and emits one coalesced artifact truncation notice:

```swift
#expect(delivery.snapshotForTesting.pendingArtifactBytes
    <= AgentRunEventDelivery.maximumPendingArtifactBytes)
#expect(delivery.snapshotForTesting.discardedArtifactEntries > 0)
#expect(delivered.contains { event in
    guard case let .deliveryNotice(notice) = event else { return false }
    return notice.kind == .artifactTruncated
})
```

- [ ] **Step 2: Run the delivery suite and confirm RED**

Run:

```bash
swift test --filter 'YapOpsCoreTests.AgentRunEventDeliveryTests'
```

Expected: compilation fails because artifact counters and notice kind are missing.

- [ ] **Step 3: Split tool artifacts during normalization**

Normalize tool events into one required control entry containing only bounded text details, followed by one artifact entry per artifact in original content order:

```swift
let textContent = toolCall.content.compactMap { content -> AgentToolCallContent? in
    guard case let .text(text) = content else { return nil }
    return .text(boundedPrefix(text, maximumBytes: 16 * 1_024).value)
}
var entries = controlEntries(event: .toolCall(AgentToolCall(
    id: toolCall.id,
    title: boundedTitle.value,
    kind: toolCall.kind,
    status: toolCall.status,
    content: textContent)), discardedBytes: discarded, discardedEntries: 0).entries
entries.append(contentsOf: artifactEntries(from: toolCall.content))
return AgentRunEventNormalization(entries: entries)
```

Direct `.artifact` events produce a single artifact entry. Revalidate all public artifact values here with `AgentArtifactLimits` so alternate producers cannot bypass the decoder limits.

- [ ] **Step 4: Add independent artifact accounting**

Add `artifactBytes` to `AgentRunEventDeliveryEntry` and `pendingArtifactBytes`, `discardedArtifactBytes`, and `discardedArtifactEntries` to `AgentRunEventDeliverySnapshot`. Define:

```swift
static let maximumPendingArtifactBytes = 4 * 1_024 * 1_024
```

`AgentRunEventDeliveryQueue.enforceBounds()` discards whole oldest artifact entries until the byte bound is met, inserting or coalescing `.artifactTruncated` notices. Entry-count pressure treats artifact entries as discardable output. Artifact bytes never count as required control bytes and are never prefix-truncated.

- [ ] **Step 5: Run the delivery suite and confirm GREEN**

Run:

```bash
swift test --filter 'YapOpsCoreTests.AgentRunEventDeliveryTests'
```

Expected: ordered splitting, bounded counters, truncation notices, and existing text/control behavior all pass.

- [ ] **Step 6: Commit ordered artifact delivery**

```bash
git add Sources/YapOpsCore/AgentRunEvent.swift Sources/YapOpsCore/AgentRunEventNormalization.swift Sources/YapOpsCore/AgentRunEventDeliveryEntry.swift Sources/YapOpsCore/AgentRunEventDeliveryQueue.swift Sources/YapOpsCore/AgentRunEventDelivery.swift Tests/YapOpsCoreTests/AgentRunEventDeliveryTests.swift
git commit -m "feat: bound ACP artifact delivery"
```

---

### Task 3: Reduce artifacts into result presentation

**Files:**
- Modify: `Sources/YapOpsApp/AgentRunPresentationModels.swift`
- Modify: `Sources/YapOpsApp/AgentRunPresentation.swift`
- Modify: `Sources/YapOpsApp/AgentRunPresentation+Events.swift`
- Modify: `Sources/YapOpsApp/AgentRunPresentation+Publication.swift`
- Modify: `Sources/YapOpsApp/AgentRunPresentationSupport.swift`
- Create: `Tests/YapOpsAppTests/AgentRunPresentationArtifactTests.swift`

**Interfaces:**
- Consumes: ordered artifact events and text-only tool content from Task 2.
- Produces: `AgentArtifactPresentation` with stable UUID identity.
- Produces: defaulted `artifacts` and `omittedArtifactCount` on `AgentRunSnapshot`.
- Preserves: current timeline and 50 ms token publication behavior.

- [ ] **Step 1: Write failing presentation tests**

Create a focused test suite that proves direct and tool artifacts appear, a repeated canonical URI updates in place without changing identity, 33 unique results evict the oldest, embedded payload never exceeds 4 MiB, stale run events do nothing, and copy export includes names/URIs without bytes:

```swift
@MainActor @Test
func receive_WhenArtifactURIRepeats_UpdatesResultWithoutChangingIdentity() throws {
    let presentation = AgentRunPresentation(startsElapsedTimer: false)
    let runID = UUID()
    presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Render")
    presentation.receive(runID: runID, event: .artifact(pdf(title: "Draft")))
    let firstID = try #require(presentation.snapshot?.artifacts.first?.id)

    presentation.receive(runID: runID, event: .artifact(pdf(title: "Final")))

    #expect(presentation.snapshot?.artifacts.count == 1)
    #expect(presentation.snapshot?.artifacts.first?.id == firstID)
    #expect(presentation.snapshot?.artifacts.first?.artifact.title == "Final")
}
```

Add these private helpers to the new suite so it does not depend on another
suite's private fixtures:

```swift
private func makeAgentProfile() throws -> WakeProfile {
    try WakeProfile(
        wakePhrase: "computer",
        action: .agent(AgentHarnessConfiguration(
            preset: .codex,
            displayName: "Codex",
            executablePath: "/usr/bin/env",
            arguments: ["codex-acp"],
            workingDirectory: "/tmp",
            permissionPolicy: .ask)),
        accent: .purple)
}

private func pdf(title: String) -> AgentArtifact {
    AgentArtifact(
        uri: "file:///tmp/report.pdf",
        name: "report.pdf",
        title: title,
        descriptiveText: nil,
        mimeType: "application/pdf",
        declaredSize: 1_024,
        payload: .linked)
}
```

- [ ] **Step 2: Run the focused suite and confirm RED**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentRunPresentationArtifactTests'
```

Expected: compilation fails because snapshot artifact state does not exist.

- [ ] **Step 3: Add stable artifact presentation values**

Add:

```swift
struct AgentArtifactPresentation: Equatable, Identifiable, Sendable {
    let id: UUID
    var artifact: AgentArtifact

    var embeddedByteCount: Int {
        switch artifact.payload {
        case .image(let data, _), .embeddedBlob(let data): data.count
        case .embeddedText(let text): text.utf8.count
        case .linked: 0
        }
    }
}
```

Give `AgentRunSnapshot` defaulted `artifacts: [AgentArtifactPresentation] = []` and `omittedArtifactCount: UInt64 = 0` properties so existing test fixture initializers remain source-compatible. Add matching reducer state and reset it in `start`/`discard`/`shutdown`.

- [ ] **Step 4: Implement deduplication and eviction**

Use a normalized URI key that lowercases only the scheme and host while preserving the path. A repeated key replaces the artifact value at its existing index and keeps its UUID. Artifacts without a URI are never guessed equal. Before insertion, evict oldest entries until both bounds hold:

```swift
while artifacts.count >= Self.maximumArtifacts
    || retainedArtifactBytes + artifactBytes > Self.maximumArtifactBytes
{
    guard !artifacts.isEmpty else { break }
    retainedArtifactBytes -= artifacts.removeFirst().embeddedByteCount
    omittedArtifactCount = saturatingIncrement(omittedArtifactCount)
}
```

Define `maximumArtifacts = 32` and `maximumArtifactBytes = 4 * 1_024 * 1_024`. Add the omission notice once. Handle artifacts found in direct `.artifact`, `.toolCall`, and `.toolCallUpdate` events so unit callers and normalized runtime delivery agree. Retain text tool content inside `AgentToolPresentation` for its collapsed details.

- [ ] **Step 5: Extend copy and diagnostics without leaking content**

Append this section only when artifacts exist:

```swift
let lines = artifacts.map { result in
    result.artifact.uri.map { "- \(result.artifact.name) — \($0)" }
        ?? "- \(result.artifact.name)"
}
sections.append("Results\n" + lines.joined(separator: "\n"))
```

Update event diagnostic switches for `.artifact`; record counts and byte totals only, never URI, filename, description, embedded text, or data.

- [ ] **Step 6: Run the focused presentation tests and confirm GREEN**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentRunPresentationArtifactTests'
swift test --filter 'YapOpsAppTests.AgentRunPresentationTests'
```

Expected: new artifact tests and all existing presentation behavior pass.

- [ ] **Step 7: Commit result presentation**

```bash
git add Sources/YapOpsApp/AgentRunPresentationModels.swift Sources/YapOpsApp/AgentRunPresentation.swift Sources/YapOpsApp/AgentRunPresentation+Events.swift Sources/YapOpsApp/AgentRunPresentation+Publication.swift Sources/YapOpsApp/AgentRunPresentationSupport.swift Tests/YapOpsAppTests/AgentRunPresentationArtifactTests.swift
git commit -m "feat: present generated agent results"
```

---

### Task 4: Generate previews without stale callbacks

**Files:**
- Create: `Sources/YapOpsApp/AgentArtifactPreview.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelModel.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelController.swift`
- Create: `Tests/YapOpsAppTests/AgentArtifactPreviewTests.swift`
- Create: `Tests/YapOpsAppTests/AgentRunPanelModelArtifactTests.swift`

**Interfaces:**
- Consumes: `AgentArtifactPresentation` from Task 3.
- Produces: `AgentArtifactPreviewLoading.loadPreview(for:size:scale:) async -> AgentArtifactPreview?`.
- Produces: observable per-artifact loading, available, and unavailable state on `AgentRunPanelModel`.

- [ ] **Step 1: Write failing preview policy and stale-result tests**

Test that embedded images choose Image I/O, local file links choose Quick Look, remote links and embedded non-images choose no automatic source, and a delayed preview from an old run is rejected after `begin` installs a new run:

```swift
@MainActor @Test
func preview_WhenPreviousRunCompletesLate_DoesNotPopulateCurrentRun() async throws {
    let oldRun = UUID()
    let newRun = UUID()
    let oldArtifact = AgentArtifactPresentation(id: UUID(), artifact: pdf(title: "Old"))
    let preview = AgentArtifactPreview(image: try onePixelImage())
    let loader = ControlledAgentArtifactPreviewLoader()
    let model = AgentRunPanelModel(previewLoader: loader)
    model.begin(snapshot(runID: oldRun, artifacts: [oldArtifact]))
    await loader.waitUntilRequested(oldArtifact.id)

    model.begin(snapshot(runID: newRun, artifacts: []))
    loader.complete(oldArtifact.id, with: preview)
    await Task.yield()

    #expect(model.previewStatus(for: oldArtifact.id) == nil)
}
```

Define the helpers in the same file so the suite is self-contained:

```swift
private func snapshot(
    runID: UUID,
    artifacts: [AgentArtifactPresentation]
) -> AgentRunSnapshot {
    AgentRunSnapshot(
        runID: runID,
        profileID: UUID(),
        accent: .blue,
        prompt: "Render",
        providerName: "Codex",
        phase: .running,
        voiceInput: "",
        output: "",
        timeline: [],
        diagnostics: "",
        plan: [],
        tools: [],
        permissions: [],
        notices: [],
        elapsedSeconds: 0,
        evictedToolCount: 0,
        ignoredToolUpdateCount: 0,
        artifacts: artifacts,
        omittedArtifactCount: 0)
}

private func onePixelImage() throws -> CGImage {
    let bytes = Data([0, 0, 0, 255])
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    return try #require(CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent))
}
```

- [ ] **Step 2: Run the focused suites and confirm RED**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentArtifactPreviewTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelModelArtifactTests'
```

Expected: compilation fails because the preview policy and injected loader do not exist.

- [ ] **Step 3: Add the preview policy and loader**

Define:

```swift
struct AgentArtifactPreview: @unchecked Sendable {
    let image: CGImage
}

enum AgentArtifactPreviewStatus: Equatable {
    case loading
    case available
    case unavailable
}

enum AgentArtifactPreviewState {
    case loading
    case available(AgentArtifactPreview)
    case unavailable

    var status: AgentArtifactPreviewStatus {
        switch self {
        case .loading: .loading
        case .available: .available
        case .unavailable: .unavailable
        }
    }
}

protocol AgentArtifactPreviewLoading: Sendable {
    func loadPreview(
        for artifact: AgentArtifactPresentation,
        size: CGSize,
        scale: CGFloat) async -> AgentArtifactPreview?
}
```

`SystemAgentArtifactPreviewLoader` uses a dedicated `DispatchQueue` for
`CGImageSourceCreateThumbnailAtIndex` and never decodes image data on the main
actor. For existing local file URLs it creates:

```swift
let request = QLThumbnailGenerator.Request(
    fileAt: url,
    size: size,
    scale: scale,
    representationTypes: [.thumbnail, .icon])
request.iconMode = false
```

Bridge `generateBestRepresentation(for:completion:)` with one checked continuation
and cancel the request in a cancellation handler. Return `representation.cgImage`.
Do not call Quick Look or networking for `http`, `https`, unknown schemes, or
embedded non-image content.

- [ ] **Step 4: Make the panel model own preview tasks**

Inject the loader into `AgentRunPanelModel`, defaulting to the system loader in
`AgentRunPanelController`. Track `[UUID: AgentArtifactPreviewState]` and
`[UUID: Task<Void, Never>]`. On begin/update, cancel removed requests, start one
request per new artifact, and publish only when both `runID` and artifact ID still
match the current snapshot. Cancel every task when a new run begins.

- [ ] **Step 5: Run focused preview tests and confirm GREEN**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentArtifactPreviewTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelModelArtifactTests'
```

Expected: source policy, cancellation, stable previews, and stale-run rejection pass.

- [ ] **Step 6: Commit preview generation**

```bash
git add Sources/YapOpsApp/AgentArtifactPreview.swift Sources/YapOpsApp/AgentRunPanelModel.swift Sources/YapOpsApp/AgentRunPanelController.swift Tests/YapOpsAppTests/AgentArtifactPreviewTests.swift Tests/YapOpsAppTests/AgentRunPanelModelArtifactTests.swift
git commit -m "feat: generate native artifact previews"
```

---

### Task 5: Open, reveal, materialize, and clean artifact files

**Files:**
- Create: `Sources/YapOpsApp/AgentArtifactActions.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelPresenter.swift`
- Modify: `Sources/YapOpsApp/AppModel+Lifecycle.swift`
- Test: `Tests/YapOpsAppTests/AgentRunPanelPresenterTests.swift`
- Create: `Tests/YapOpsAppTests/AgentArtifactActionsTests.swift`

**Interfaces:**
- Consumes: artifact IDs from Task 3 and UI actions from Task 6.
- Produces: `openArtifact` and `revealArtifact` panel actions.
- Produces: run-scoped temporary materialization and cleanup.
- Preserves: close retains a result; delete, replacement, and shutdown clean it.

- [ ] **Step 1: Add failing presenter action tests**

Inject an action spy, begin a snapshot with one result, and prove current actions
are forwarded while stale run IDs, unknown artifact IDs, forbidden schemes, and
non-file reveal attempts are ignored. Prove repeated explicit Open clicks remain
allowed, because they are separate user actions.

- [ ] **Step 2: Add failing materialization tests**

Use a UUID temporary root and an injected workspace spy. Assert embedded bytes are
written only after Open, the basename cannot escape the run directory, permissions
are `0600`, replacement/delete/shutdown remove the run directory, close does not,
and a controlled late materialization for a retired run never invokes the workspace.

- [ ] **Step 3: Run the focused suites and confirm RED**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentRunPanelPresenterTests'
swift test --filter 'YapOpsAppTests.AgentArtifactActionsTests'
```

Expected: compilation fails because artifact actions and services are missing.

- [ ] **Step 4: Add the AppKit action boundary**

Define a main-actor service used by the presenter:

```swift
@MainActor
protocol AgentArtifactOpening: AnyObject {
    func begin(runID: UUID)
    func open(runID: UUID, artifact: AgentArtifactPresentation)
    func reveal(runID: UUID, artifact: AgentArtifactPresentation)
    func discard(runID: UUID)
    func shutdown()
}
```

`SystemAgentArtifactOpener` opens `file`, `http`, and `https` URLs using
`NSWorkspace.open(_:configuration:completionHandler:)`. Reveal uses
`activateFileViewerSelecting(_:)` only for an existing local file. The service
records scheme, MIME type presence, result, and run ID—never URI, filename, path,
description, text, or bytes.

- [ ] **Step 5: Add the dedicated temporary-file queue**

Create an `@unchecked Sendable` store whose mutable state and all `FileManager`
calls live on one private `DispatchQueue`. Build paths only from
`URL(fileURLWithPath: artifact.name).lastPathComponent`, replace unsafe characters,
fall back to `Artifact`, and create a `0700` run directory. Write embedded data
atomically and set `0600`. Expose async `materialize`, `discard(runID:)`, and
`discardAll` methods through checked continuations.

After `await materialize`, the opener rechecks its active run generation before
calling `NSWorkspace`. Linked artifacts bypass materialization. `.linked` without
a URI and unknown schemes are rejected.

- [ ] **Step 6: Route actions through the run-scoped presenter**

Add:

```swift
case openArtifact(runID: UUID, artifactID: UUID)
case revealArtifact(runID: UUID, artifactID: UUID)
```

`AgentRunPanelPresenter` looks up the exact current artifact before invoking the
service. `begin` discards the previous run before installing the new one; `delete`
discards the current run; `close` only hides it. Add `shutdown()` and call it from
`AppModel.shutdown()`.

- [ ] **Step 7: Run action and lifecycle tests and confirm GREEN**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentRunPanelPresenterTests'
swift test --filter 'YapOpsAppTests.AgentArtifactActionsTests'
swift test --filter 'YapOpsAppTests.AppModelLifecycleTests'
```

Expected: exact run scoping, explicit file effects, permissions, cleanup, and existing app shutdown behavior pass.

- [ ] **Step 8: Commit native artifact actions**

```bash
git add Sources/YapOpsApp/AgentArtifactActions.swift Sources/YapOpsApp/AgentRunPanelPresenter.swift Sources/YapOpsApp/AppModel+Lifecycle.swift Tests/YapOpsAppTests/AgentRunPanelPresenterTests.swift Tests/YapOpsAppTests/AgentArtifactActionsTests.swift
git commit -m "feat: open generated artifacts safely"
```

---

### Task 6: Build the result-first macOS conversation surface

**Files:**
- Create: `Sources/YapOpsApp/AgentRunArtifactView.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelView.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelContent.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelActivity.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelChrome.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelVisuals.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelLayout.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelModel.swift`
- Modify: `Sources/YapOpsApp/AgentRunPanelController.swift`
- Test: `Tests/YapOpsAppTests/AgentRunPanelLayoutTests.swift`
- Test: `Tests/YapOpsAppTests/AgentRunPanelPresenterTests.swift`
- Test: `Tests/YapOpsAppTests/AgentRunPanelAnimationTests.swift`

**Interfaces:**
- Consumes: snapshot artifacts, preview state, and presenter actions from Tasks 3–5.
- Produces: adaptive Results shelf and preferred 680 by 560 point expanded panel.
- Preserves: non-activation, saved placement, minimize/restore, scroll ownership, permissions, cancellation, and Reduce Motion behavior.

- [ ] **Step 1: Add failing layout and presentation tests**

Change layout expectations to 680 by 560 on a normal screen and to the complete
visible-frame size on a 500 by 300 screen. Verify restoring uses the settled
adaptive size. Render a snapshot containing an image and PDF card under normal,
Reduce Transparency, and increased-contrast environments and assert non-`nil`
output. Assert the panel still cannot become key or main and settled thinking
groups collapse.

- [ ] **Step 2: Run the focused UI suites and confirm RED**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentRunPanelLayoutTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelPresenterTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelAnimationTests'
```

Expected: adaptive geometry and artifact rendering assertions fail.

- [ ] **Step 3: Make expanded geometry adaptive**

Replace the fixed expanded constant with:

```swift
static let preferredExpandedSize = NSSize(width: 680, height: 560)

static func expandedSize(in visibleFrame: NSRect) -> NSSize {
    NSSize(
        width: min(preferredExpandedSize.width, visibleFrame.width),
        height: min(preferredExpandedSize.height, visibleFrame.height))
}
```

Use that size for begin and restore. Store the settled expanded size on
`AgentRunPanelModel` so SwiftUI's frame matches the AppKit panel. Preserve the 372
by 84 compact form and existing multi-display placement identity.

- [ ] **Step 4: Add the Results shelf**

Build `AgentRunArtifactShelf` with an adaptive grid:

```swift
LazyVGrid(
    columns: [GridItem(.adaptive(minimum: 250), spacing: 12)],
    alignment: .leading,
    spacing: 12)
{
    ForEach(snapshot.artifacts) { result in
        AgentRunArtifactCard(
            result: result,
            preview: model.previewState(for: result.id),
            onOpen: { model.onAction?(.openArtifact(
                runID: snapshot.runID, artifactID: result.id)) },
            onReveal: { model.onAction?(.revealArtifact(
                runID: snapshot.runID, artifactID: result.id)) })
    }
}
```

Use aspect-fit previews, a system file icon fallback, filename/title, kind, and
formatted size. Show Open for allowed schemes or embedded content; put Reveal in
a context menu for file URLs. Add labels, values, help, and logical grouping for
VoiceOver. Never show a raw URI as an error and never fetch a remote preview.

- [ ] **Step 5: Reorder and simplify the conversation hierarchy**

Render, in order: quiet header, compact request, Results shelf, timeline, plan,
notices, failure, permissions, stable footer. Keep bottom-follow hooks for artifacts
and existing state, but do not animate token or preview changes.

Remove the large phase orb and mini agent avatar. Replace the multi-gradient
backdrop with one material and an opaque `windowBackgroundColor` fallback under
Reduce Transparency. Remove glow shadows, uppercase tracking, rounded display
fonts, and borders around each response paragraph. Use semantic `.headline`,
`.body`, `.callout`, `.caption`, SF Symbols, `Divider`, `.buttonStyle(.bordered)`,
and one accent tint for active state. Keep permissions and failures prominent.

Do not replace the Markdown renderer in this task. At final integration, retain
`main`'s pending `MarkdownUI` implementation and adapt its call sites to the
simplified response/detail styles.

- [ ] **Step 6: Scope motion and accessibility behavior**

Use opacity-only structural transitions under Reduce Motion and no repeating
status animation after work settles. Under Reduce Transparency use an opaque
semantic background; under increased contrast retain separators and result-card
edges. Decorative previews, separators, and phase marks are accessibility-hidden
when their labels already expose the same information.

- [ ] **Step 7: Run focused UI tests and confirm GREEN**

Run:

```bash
swift test --filter 'YapOpsAppTests.AgentRunPanelLayoutTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelPresenterTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelAnimationTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelModelArtifactTests'
```

Expected: adaptive sizing, renderability, action wiring, panel focus policy, scroll behavior, and motion substitutions pass.

- [ ] **Step 8: Commit the conversation redesign**

```bash
git add Sources/YapOpsApp/AgentRunArtifactView.swift Sources/YapOpsApp/AgentRunPanelView.swift Sources/YapOpsApp/AgentRunPanelContent.swift Sources/YapOpsApp/AgentRunPanelActivity.swift Sources/YapOpsApp/AgentRunPanelChrome.swift Sources/YapOpsApp/AgentRunPanelVisuals.swift Sources/YapOpsApp/AgentRunPanelLayout.swift Sources/YapOpsApp/AgentRunPanelModel.swift Sources/YapOpsApp/AgentRunPanelController.swift Tests/YapOpsAppTests/AgentRunPanelLayoutTests.swift Tests/YapOpsAppTests/AgentRunPanelPresenterTests.swift Tests/YapOpsAppTests/AgentRunPanelAnimationTests.swift
git commit -m "feat: focus agent conversations on results"
```

---

### Task 7: Document, verify, integrate, and remove the worktree

**Files:**
- Modify: `README.md`
- Modify: `docs/agent-harness.md`
- Modify: `docs/architecture.md`
- Modify after merging current `main`: `docs/agent-conversations.md`

**Interfaces:**
- Consumes: all completed implementation tasks.
- Produces: documented user workflow, architecture, privacy, and verified `main` integration.
- Produces: removal of `/Users/alex/.codex/worktrees/8a87/yapops` after merged verification.

- [ ] **Step 1: Update owning documentation**

Document structured ACP agent-message and tool-result artifacts, the Results shelf,
preview policy, explicit Open/Reveal behavior, remote no-fetch rule, temporary-file
cleanup, byte/count bounds, and non-activating focus behavior. Preserve `main`'s
new Markdown-rendering documentation when resolving the final merge.

- [ ] **Step 2: Run focused and complete verification in the worktree**

Run:

```bash
swift test --filter 'YapOpsCoreTests.ACPEventDecoderTests'
swift test --filter 'YapOpsCoreTests.AgentRunEventDeliveryTests'
swift test --filter 'YapOpsAppTests.AgentRunPresentationArtifactTests'
swift test --filter 'YapOpsAppTests.AgentArtifactPreviewTests'
swift test --filter 'YapOpsAppTests.AgentArtifactActionsTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelModelArtifactTests'
swift test --filter 'YapOpsAppTests.AgentRunPanelLayoutTests'
swift test
swift test --sanitize=thread
CONFIGURATION=debug make app
make check
git diff --check
```

Expected: every command exits 0 with no unexpected warnings.

- [ ] **Step 3: Exercise the real bundled app**

Open the debug bundle and inspect local PNG/JPEG, PDF, and document links; an
embedded image; a broken local link; and an explicit HTTPS link. Check short and
long responses, rapid streaming, follow-up, permission, cancel, completed, compact,
and restored states. Repeat the relevant views in light/dark appearance, Reduce
Motion, Reduce Transparency, Increase Contrast, and VoiceOver while another app
remains active. Record any environment-bound row that cannot be exercised; do not
call it passed.

- [ ] **Step 4: Commit docs and any verification fixes**

```bash
git add README.md docs/agent-harness.md docs/architecture.md
git commit -m "docs: explain generated agent results"
```

Re-run the focused test for every fix made during verification, then repeat the
complete commands in Step 2.

- [ ] **Step 5: Recheck the main checkout before touching it**

Run:

```bash
git -C /Users/alex/Development/yapops status --short
git -C /Users/alex/Development/yapops log -1 --oneline --decorate
```

Expected before integration: clean status. If it is still dirty, stop at this
single merge gate and ask the user to finish or move that unrelated work; never
stash, commit, reset, or overwrite it.

- [ ] **Step 6: Merge the latest clean `main` into this worktree**

From this worktree, run:

```bash
git merge --no-ff main -m "Merge main into ACP artifact conversation"
```

Resolve overlaps by preserving both sides: keep `main`'s `MarkdownUI` dependency,
`AgentMarkdownRendering`, docs split, and tests; keep this worktree's typed artifacts,
Results shelf, preview/action lifecycle, simplified panel, and adaptive layout. Run
the full Step 2 verification again and commit only real conflict-resolution edits.

- [ ] **Step 7: Fast-forward `main` and verify the merged checkout**

Capture the verified worktree commit, then run from the main checkout:

```bash
task_verified_commit=$(git rev-parse HEAD)
git cat-file -e "$task_verified_commit^{commit}"
git -C /Users/alex/Development/yapops merge --ff-only "$task_verified_commit"
cd /Users/alex/Development/yapops
swift test
CONFIGURATION=debug make app
make check
git diff --check
```

Expected: the validated variable names the literal current commit, `main` points
at that verified integration commit, the checkout is clean, and every command
exits 0.

- [ ] **Step 8: Remove the merged worktree**

Only after Step 7 passes, run from `/Users/alex/Development/yapops`:

```bash
git worktree remove /Users/alex/.codex/worktrees/8a87/yapops
git worktree list --porcelain
```

Expected: the removed path is absent and `main` remains at the verified integration
commit. Do not use `--force`; a non-clean worktree is evidence that required work
remains.
