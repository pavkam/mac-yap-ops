<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Voice-First Response Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for task-by-task execution in this session, or `superpowers:executing-plans` in a separate session. Load the project `development`, `acp-integration`, `ux`, `voice-reading`, and `testing-and-debugging` skills before changing code.

**Goal:** Let an ACP agent author a short response specifically for speech and a separate rich response for the panel, while preserving ordinary ACP agents' current display-and-narrate behavior exactly.

**Architecture:** Decode an optional namespaced ACP `_meta` response-channel extension into typed Core events. For today's pinned adapters, ask the agent to use a tiny, deterministic text-marker contract carried by standard `agent_message_chunk` events and route that stream in Core. If neither contract is present, retain the existing legacy event. App presentation displays every agent-authored response, while narration speaks only typed spoken content or the unchanged legacy fallback.

**Tech stack:** Swift 6.2, Swift Testing, ACP v1 over JSON-RPC, SwiftUI/AppKit, `AVSpeechSynthesizer`, and the existing ElevenLabs adapter.

**Spec:** This document is the approved feature contract and implementation plan. No separate speculative design is required.

## Product boundary

Voice Activation is a thin native voice/runtime bridge. It may transport and render/speak typed agent-authored content, arbitrate audio/cancellation, and retain opaque identities. The ACP agent owns wording, semantics, planning, tool use, confirmation decisions, result interpretation, memory, and task execution. Do not make the app infer which tool is dangerous, summarize results, rewrite prose, or implement a second dialogue policy.

This feature therefore routes text the agent explicitly authored. It does not derive a spoken summary from Markdown, tool output, plans, diagnostics, or stop reasons. The existing Markdown-to-speech rendering remains only as the compatibility path for untyped legacy agent messages.

## Feature contract

### Observable scenarios

1. The user says, “Move my screenshots into an Archive folder.” The agent completes the work and emits spoken text, “Done — I moved 18 screenshots into Archive,” plus a display response containing the exact file list. Voice Activation speaks only the spoken text and shows both agent-authored sections in the panel.
2. The user asks, “What changed?” during the same conversation. The ACP agent authors another spoken response and a rich Markdown diff summary. The app does not reconstruct either response from earlier tool calls.
3. A standard ACP agent emits only ordinary `agent_message_chunk` text. The panel and narration behave exactly as today: the message is displayed and passed through the legacy Markdown narration formatter.
4. An agent begins the marker contract but sends the marker across multiple JSON-RPC chunks. The router recognizes it without exposing or speaking the marker.
5. An agent emits malformed or unknown extension metadata, or starts text that only resembles a marker. The entire original message is delivered as a legacy agent message; no text disappears.
6. The user barges in or says “stop.” The current narration generation is invalidated before owned synthesis/playback is cancelled. Late chunks, synthesis callbacks, and player completions from the retired run cannot resume speech.
7. A restored or background session replays historical updates. Historical spoken events remain visible, but are not automatically narrated merely because they were replayed; only newly admitted `.live` events for the retained run/session may enter the speech queue.

### Channel semantics

| Event | Panel | Speech | Interpretation |
| --- | --- | --- | --- |
| Typed `spoken` | Visible in a labelled, accessible Spoken response row | Speak as agent-authored plain text | None |
| Typed `display` | Render as rich Markdown | Never speak | None |
| Legacy agent message | Existing response timeline/output | Existing Markdown narration path | None |
| Thought, tool, plan, diagnostic | Existing presentation | Never synthesize into a response | None |

The agent may emit only spoken content, only display content, both, or multiple message identities. Audio is never the sole carrier: spoken content must remain visible and copyable.

## Protocol proof and compatibility contract

### What ACP v1 can and cannot express

The [ACP v1 schema](https://agentclientprotocol.com/protocol/v1/schema) defines `agent_message_chunk` as a `ContentBlock` plus optional `messageId`. `TextContent` has `text`, optional annotations, and `_meta`; the standard annotations describe audience, priority, and modification time, not a spoken-versus-display channel. ACP v1 therefore **cannot portably express a distinct spoken response**.

The [ACP extensibility contract](https://agentclientprotocol.com/protocol/v1/extensibility) permits custom data only under `_meta`, including nested content blocks and capability objects. Unknown metadata remains compatible, while custom root fields are forbidden. That gives a valid provider enhancement, not a standard ACP semantic.

The pinned adapters are Codex ACP 1.8.0 and Claude Agent ACP 0.73.0 (`docs/agent-harness.md`). Inspection of [Codex `ContentChunks.ts` at v1.8.0](https://github.com/agentclientprotocol/codex-acp/blob/v1.8.0/src/ContentChunks.ts) and the [Claude adapter at v0.73.0](https://github.com/agentclientprotocol/claude-agent-acp/tree/v0.73.0/src) finds ordinary text chunks but no Voice Activation response-channel metadata. The extension path is consequently implementable and backward-compatible, but not sufficient for current providers by itself.

### Provider extension: typed content metadata

Advertise support under `clientCapabilities._meta`:

```json
{
  "clientCapabilities": {
    "_meta": {
      "ciobanu.org.voiceActivation": {
        "responseChannels": { "version": 1, "channels": ["spoken", "display"] }
      }
    }
  }
}
```

A supporting ACP agent attaches this metadata to each text content block:

```json
{
  "sessionUpdate": "agent_message_chunk",
  "messageId": "answer-7",
  "content": {
    "type": "text",
    "text": "Done — I moved 18 screenshots into Archive.",
    "_meta": {
      "ciobanu.org.voiceActivation": {
        "responseChannel": { "version": 1, "channel": "spoken" }
      }
    }
  }
}
```

Only integer version `1` and exact string channels `spoken` and `display` are accepted. Unknown versions, values, shapes, or placement fall back to legacy text. A valid typed block bypasses marker parsing; its text is literal. Providers must not combine typed metadata and text markers.

Durable Continuity creates `ACPClientCapabilities` as the single owner of the complete initialize capability object. Features contribute namespaced fragments and the builder deep-merges object paths while rejecting collisions; no plan writes a fresh `_meta` dictionary over another feature. This slice adds `voiceResponseChannelsV1`, contributing `ciobanu.org.voiceActivation.responseChannels`. Background Task Continuity later contributes `jetbrains.air` through the same builder. A combined fixture must prove both keys survive in one initialize request.

### Current-adapter contract: in-band markers

`ACPAgentInstruction.responseStyle` tells agents whose adapter does not emit the extension to start a response with this exact ASCII marker:

```text
[[voice-activation:spoken:v1]]
Agent-authored plain text for speech.
[[voice-activation:display:v1]]
Agent-authored Markdown for the panel.
```

The display marker and display section are optional. The spoken marker must be the first bytes of a message. Once that exact marker is accepted, the text is typed spoken content; a missing display marker means “spoken only,” not corruption. The router buffers at most one marker's UTF-8 length to recognize markers split across chunks. Any first-byte mismatch, partial start marker at a semantic boundary, or unknown marker flushes the original bytes as legacy text. Once in display mode, marker-looking text is literal.

This is an app-level instruction contract transported by standard ACP, not a new ACP feature. Model compliance is not guaranteed; the untouched legacy route is the exact fallback. Current pinned adapters can carry the contract because they already forward agent text in standard message chunks. A future adapter can instead emit typed `_meta` blocks without changing the app event model.

## Current-state evidence

- `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` sends `clientCapabilities: {}`. `ACPClientConnection` adds `ACPAgentInstruction.responseStyle` to the normal ACP prompt; `ACPProcessTransport` also writes Codex developer instructions only for the Codex/profile configuration path, not as a general prompt owner.
- `Sources/VoiceActivationCore/ACPEventDecoder.swift`, `ACPEventDecoder.ContentChunk`, decodes text from `agent_message_chunk` into `.agentMessageDelta(messageID:text:)` and drops content annotations and `_meta`.
- `Sources/VoiceActivationCore/AgentRunEvent.swift`, `AgentRunEvent`, has one response-text case; there is no response channel.
- `Sources/VoiceActivationCore/AgentRunEventNormalization.swift`, `AgentRunEventDeliveryEntry.swift`, and `AgentRunEventDelivery.swift` enforce event normalization, coalescing, 512 KiB output/control limits, 256 queued entries, and bounded opaque identities.
- `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift` admits one decoded event at a time, so routing belongs between decoding and delivery rather than in App UI code.
- `Sources/VoiceActivationApp/AgentConversationAudio.swift`, `AgentConversationAudioPresenter.process`, narrates every `.agentMessageDelta`. It marks other semantic events as boundaries and delegates generation-safe speech to `AgentNarrationSegmenter`.
- `Sources/VoiceActivationApp/AgentNarrationSegmenter.swift` bounds narration at 20,000 characters and 350 ms; `AgentSpeechQueue.swift` bounds 64 pending segments and two cloud synthesis tasks, preserves FIFO order, and rejects retired generations.
- `Sources/VoiceActivationApp/AgentRunPresentation+Events.swift` sends ordinary responses to rich output and timeline models. `AgentRunPresentationModels.swift` currently distinguishes response and thought only.
- `Tests/VoiceActivationAppTests/AgentRunPresentationTests.swift` is already 662 lines. New response-channel tests must be separate files to preserve the 700-line cap.

## Chosen architecture

The Core boundary owns protocol typing and streaming marker state. The App boundary owns visible presentation, accessibility, and audio transport. No SwiftUI, AppKit, speech framework, or provider-specific JSON escapes into Core presentation policy.

### Exact Core API

Add the typed cases while retaining the legacy case:

```swift
public enum AgentSpokenSuppressionReason: Equatable, Sendable {
    case oversized
    case incompleteDelivery
}

public enum AgentRunEvent: Equatable, Sendable {
    case agentMessageDelta(messageID: String?, text: String)
    case agentSpokenMessageDelta(messageID: String?, text: String)
    case agentSpokenNarrationReady(messageID: String?, text: String)
    case agentSpokenNarrationSuppressed(
        messageID: String?, reason: AgentSpokenSuppressionReason)
    case agentDisplayMessageDelta(messageID: String?, text: String)
    // Existing cases remain unchanged.
}
```

Add a framework-independent router owned by the live connection/session, not by one active turn:

```swift
public struct AgentResponseChannelRouter: Sendable {
    public static let spokenMarker = "[[voice-activation:spoken:v1]]\n"
    public static let displayMarker = "\n[[voice-activation:display:v1]]\n"

    public init() {}
    public mutating func route(_ event: AgentRunEvent) -> [AgentRunEvent]
    public mutating func finishMessage() -> [AgentRunEvent]
    public mutating func reset()
}
```

Internally use an enum state—`undecided(buffer,messageID)`, `legacy(messageID)`, `spoken(pendingSuffix,messageID)`, and `display(messageID)`—and retain no more than `max(spokenMarker.utf8.count, displayMarker.utf8.count)` undecided/suffix bytes. A message-ID change, non-message semantic event, prompt completion, cancellation, or connection close calls `finishMessage()` before the next event. The router returns arrays because a boundary can flush buffered text and then deliver the boundary event in order.

Spoken deltas remain visible as they arrive, while the router separately accumulates an exact narration unit up to 20,000 characters. `finishMessage()` emits one atomic `.agentSpokenNarrationReady` only if every fragment was admitted and the unit is within bounds; otherwise it emits a content-free suppression event. `AgentRunEventDelivery` tracks a narration group and suppresses the ready event if any upstream fragment was dropped or truncated. It never applies prefix/suffix truncation to the atomic ready event. This prevents the UI/delivery/queue bounds from turning exact speech into a misleading partial sentence.

Prompt completion finishes only current message state; it does not destroy the connection-owned router. The same router therefore accepts newly emitted live agent messages between turns, including provider background-task results. Each load restoration token owns a separate router that is flushed on restoration completion, reset on abort, and routed to presentation only. Cancellation invalidates the current generation before flushing and does not let retired buffered content escape.

Extend `ACPEventDecoder.ContentChunk` to retain validated response metadata and map it directly:

```swift
private enum ResponseChannel: String, Sendable {
    case spoken
    case display
}

private struct ContentChunk: Sendable {
    let contentType: String?
    let messageID: String?
    let text: String?
    let responseChannel: ResponseChannel?
}
```

The decoder reads only the exact namespaced path. It does not preserve arbitrary metadata, log it, or reject a valid text block because optional metadata is invalid.

### Exact App API

Add an input mode at the segmenter boundary so typed spoken prose is not passed through Markdown rewriting, and distinguish legacy normalization from exact agent-authored admission at the player boundary:

```swift
enum AgentNarrationInputFormat: Sendable {
    case legacyMarkdown
    case agentAuthoredPlainText
}

enum AgentSpeechTextPolicy: Sendable {
    case legacyNormalized
    case verbatim
}

var onSegment: ((String, AgentSpeechTextPolicy) -> Void)? { get set }

func append(
    messageID: String?,
    text: String,
    format: AgentNarrationInputFormat
)

func speak(
    _ text: String,
    localeID: String,
    policy: AgentSpeechTextPolicy
)
```

`AgentConversationAudioPresenter.process` treats `.agentSpokenMessageDelta` as visible-only input and speaks only the matching atomic `.agentSpokenNarrationReady` with `.agentAuthoredPlainText`/`.verbatim`. It ignores `.agentDisplayMessageDelta` for speech and retains `.legacyMarkdown`/`.legacyNormalized` for `.agentMessageDelta`. `AgentSpeechRequest` carries the policy into `AgentSpeechQueue.enqueue`; the verbatim branch rejects oversize/full-queue input as a whole and never trims, prefixes, suffixes, or coalesces. Speech segmentation may create playback-sized utterances only after the complete unit is admitted and may not substitute, summarize, truncate, or drop words. This shared bridge change is implemented once if the spoken-confirmations plan lands first.

Add `spokenResponse` to `AgentMessagePresentationKind` and bounded `spokenOutput` to `AgentRunPresentationSnapshot`. `AgentRunPresentation+Events.swift` appends typed spoken text to a visible Spoken timeline row and `spokenOutput`, typed display text to the existing rich response output, and legacy text exactly as today. Bound `spokenOutput` at 64 KiB and reuse the existing 256-item timeline cap. Copy output labels separate agent-authored sections in UI chrome; it does not rewrite their content.

### File map

Create:

- `Sources/VoiceActivationCore/AgentResponseChannelRouter.swift`
- `Tests/VoiceActivationCoreTests/ACPEventDecoderResponseChannelTests.swift`
- `Tests/VoiceActivationCoreTests/AgentResponseChannelRouterTests.swift`
- `Tests/VoiceActivationCoreTests/ACPClientConnectionResponseChannelTests.swift`
- `Tests/VoiceActivationCoreTests/AgentRunEventDeliveryResponseChannelTests.swift`
- `Tests/VoiceActivationAppTests/AgentConversationAudioResponseChannelTests.swift`
- `Tests/VoiceActivationAppTests/AgentSpeechQueueVerbatimTests.swift`
- `Tests/VoiceActivationAppTests/AgentRunPresentationResponseChannelTests.swift`

Modify:

- Core: `ACPAgentInstruction.swift`, `ACPClientConnection.swift`, `ACPClientConnection+Requests.swift`, `ACPClientConnection+Receive.swift`, `ACPEventDecoder.swift`, `AgentRunEvent.swift`, `AgentRunEventNormalization.swift`, `AgentRunEventDeliveryEntry.swift`, `ACPAgentRunnerSupport.swift`, `ACPClientConnectionSupport.swift`, and `VoiceActivationCoordinator.swift`.
- App: `AgentConversationAudio.swift`, `AgentNarrationSegmenter.swift`, `AgentSpeechQueue.swift`, `AgentRunPresentation.swift`, `AgentRunPresentationModels.swift`, `AgentRunPresentation+Events.swift`, `AgentRunPresentationSupport.swift`, `AgentRunPanelContent.swift`, and the exhaustive lifecycle switch in `AppModel.swift`.
- Documentation: `README.md`, `docs/architecture.md`, `docs/agent-harness.md`, and `docs/troubleshooting.md`.

Before editing, run `rg -n 'agentMessageDelta|AgentMessagePresentationKind|switch event' Sources Tests` and update every exhaustive switch it reports. Split a production file before it reaches 700 physical lines.

## ACP wire and data flow

```text
agent-owned text
  -> agent_message_chunk ContentBlock
  -> ACPEventDecoder
       valid responseChannel _meta -> typed spoken/display AgentRunEvent
       otherwise                   -> legacy AgentRunEvent
  -> AgentResponseChannelRouter
       typed event                 -> pass through literally
       exact marker stream         -> typed spoken/display events
       absent/malformed marker     -> original legacy events
  -> bounded AgentRunEventDelivery
  -> coordinator run/session/source identity gate
  -> App presentation + audio presenter
       spoken -> visible transcript + plain-text narration
       display -> rich visible response
       legacy -> current visible response + Markdown narration
```

The connection flushes current message state before delivering prompt completion or a non-message control event, but retains the session-owned router between turns. It resets the entire router when the connection closes. Turn cancellation first retires the current generation and drops that generation's partial unit; a later live background message starts clean state under the retained session identity. Restoration uses its own token-qualified router. Late events remain rejected by run/session/source gates.

## Privacy, bounds, identity, and cancellation

- Do not log response text, markers' surrounding content, `_meta` payloads, prompts, or speech bytes. Diagnostics may count `legacy`, `spoken`, `display`, `invalid-extension`, and `marker-fallback` events without content.
- Accept only the exact nested extension keys and primitive values. Ignore all other metadata; do not retain it in snapshots or diagnostics.
- Preserve `messageId` as an opaque value under the existing 4 KiB identity bound. A channel switch never invents or changes it.
- Marker lookahead is bounded by the longest marker. Exact spoken-unit accumulation is separately capped at 20,000 characters; after overflow the router keeps forwarding visible deltas but permanently suppresses narration for that message. Delivery remains bounded by current byte and entry budgets, spoken presentation has an explicit 64 KiB display bound, and the queue remains capped at 64 pending requests.
- Cancellation invalidates run/turn and narration generation first, then cancels transport, synthesis, and playback. `finishMessage()` must not emit buffered content after invalidation.
- Typed spoken content goes to configured system or ElevenLabs TTS only when “Reads replies aloud” is enabled. Existing Keychain, network, fallback, and no-secret logging rules remain unchanged. Apple synthesis uses the existing [`AVSpeechSynthesizer`](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer) delegate lifecycle; ElevenLabs retains its existing bounded [streaming TTS](https://elevenlabs.io/docs/api-reference/text-to-speech/stream) path.
- Speech playback must not activate the app. Visible typed speech gets the same VoiceOver access and keyboard copy support as other timeline messages.

## Rejected alternatives

- **Summarize the rich response in the app:** rejected because it duplicates agent semantics, introduces another model/policy, and can contradict the actual result.
- **Speak the first paragraph or text before a heading:** rejected because the app would infer authorial intent from formatting.
- **Synthesize tool status or raw output:** rejected because tool payloads can be sensitive and are not an agent-authored result.
- **Request a second “make this speakable” model turn:** rejected because it adds cost, latency, cancellation complexity, and a second dialogue policy.
- **Use standard `annotations`:** rejected because ACP v1 defines no speech-routing annotation.
- **Require `_meta` only:** rejected for the first release because neither pinned adapter emits this extension.
- **Treat marker compliance as guaranteed:** rejected because markers are an instruction-level compatibility contract. Exact legacy fallback is mandatory.
- **Hide spoken text from the panel:** rejected because audio cannot be the only accessible or recoverable representation.

## Phased TDD implementation

### Task 1: Type ACP extension events without breaking legacy decoding

**Files:** `AgentRunEvent.swift`, `ACPEventDecoder.swift`, `ACPEventDecoderResponseChannelTests.swift`

- [ ] Add `ACPEventDecoderResponseChannelTests.agentMessageChunk_WithSpokenMetadata_DecodesSpokenDelta` and `...WithDisplayMetadata_DecodesDisplayDelta`. Assert the exact `messageID` and text.
- [ ] Add `ACPEventDecoderResponseChannelTests.agentMessageChunk_WithUnknownOrMalformedMetadata_FallsBackToLegacyDelta` with wrong version, wrong channel, and wrong shape cases.
- [ ] Run `swift test --filter ACPEventDecoderResponseChannelTests`. RED evidence: the typed `AgentRunEvent` cases do not compile or metadata still produces `.agentMessageDelta`.
- [ ] Add the two public, DocC-documented event cases and exact nested `_meta` decoding shown above. Never decode arbitrary metadata into an unbounded dictionary.
- [ ] Update event text/byte accounting and all exhaustiveness helpers found by `rg -n 'agentMessageDelta' Sources/VoiceActivationCore`.
- [ ] Re-run the focused suite. GREEN evidence: valid v1 metadata produces typed events; invalid metadata preserves the exact legacy text.

### Task 2: Route the current adapters' marker stream deterministically

**Files:** `AgentResponseChannelRouter.swift`, `AgentResponseChannelRouterTests.swift`

- [ ] Add `AgentResponseChannelRouterTests.markerSplitAcrossChunks_RoutesSpokenAndDisplayWithoutMarkers`, including a split inside each marker and Unicode split across input strings.
- [ ] Add `...unmarkedMessage_PreservesEveryLegacyByte`, `...partialMarkerAtBoundary_FlushesLegacy`, `...messageIDChange_FinishesPreviousMessageBeforeNext`, `...spokenMessage_FinishesAsOneExactNarrationUnit`, `...oversizeSpokenMessage_RemainsVisibleButSuppressesNarration`, and `...cancelReset_DropsOnlyUnadmittedBufferedPrefix`.
- [ ] Run `swift test --filter AgentResponseChannelRouterTests`. RED evidence: `AgentResponseChannelRouter` is missing.
- [ ] Implement the state machine and exact APIs above. Keep only the undecided marker prefix or possible display-marker suffix for parsing, plus the separately bounded 20,000-character spoken accumulator used to produce one atomic narration-ready event.
- [ ] Add a property-style table test that concatenates every emitted text fragment for unmarked inputs and proves equality with the original text for every chunk split position.
- [ ] Re-run the suite. GREEN evidence: all split positions route identically, markers never leak on a valid contract, and malformed input is byte-for-byte legacy.

### Task 3: Integrate routing, client advertisement, delivery bounds, and lifecycle

**Files:** modify Durable Continuity's `ACPClientCapabilities.swift`, plus `ACPAgentInstruction.swift`, `AgentPrompt.swift`, `MacContextPromptEncoder.swift`, `ACPClientConnection*.swift`, delivery/normalization files, coordinator support, and three Core test files

- [ ] Add `ACPClientConnectionResponseChannelTests.initialize_AdvertisesResponseChannelV1UnderClientCapabilitiesMeta` and assert the complete JSON path without loosening existing initialize assertions.
- [ ] Add `...initialize_WhenAIRContributionAlsoExists_PreservesBothCapabilityNamespaces`, `...prompt_IncludesExactMarkerContractBeforeContinuityContextResourcesAndUntouchedRequest`, `...steeredPrompt_PreservesCapturedContextButDoesNotRepeatResponseInstruction`, `...promptCompletion_FlushesPartialMarkerBeforeTurnEnd`, `...backgroundMessageBetweenTurns_UsesRetainedSessionRouter`, and `...cancel_DoesNotDeliverBufferedMarkerAfterTurnRetirement`.
- [ ] Add `AgentRunEventDeliveryResponseChannelTests.sameChannelAndMessageID_CoalescesWithinBudget`, `...differentChannelOrMessageID_PreservesBoundaryAndOrder`, `...narrationReady_IsAdmittedAtomicallyWithoutSuffixTruncation`, and `...droppedSpokenFragment_SuppressesWholeNarrationUnit`.
- [ ] Run `swift test --filter 'ACPClientConnectionResponseChannelTests|AgentRunEventDeliveryResponseChannelTests'`. RED evidence: initialize metadata is absent, routed events are missing, and delivery cannot classify new cases.
- [ ] Add the deep-merging `ACPClientCapabilities` owner and use it for every initialize request. Store one live router on the connection/session plus one router per restoration token. Route decoder output before source-qualified delivery; finish message state before control events/prompt completion; retain the live router between turns; reset only the retired generation or connection as specified. Add the exact system instruction and capability JSON from this plan.
- [ ] Extend the canonical typed `AgentPrompt` pipeline instead of flattening text. The response instruction is the instruction block; continuity, captured context, resource links, and untouched request retain their order and roles. Steering reuses the admitted `AgentPrompt` and omits only the already-active response instruction.
- [ ] Give spoken/display separate delivery coalescing discriminators and track spoken narration-group admission while retaining current byte, identity, queue, and control-event budgets. An atomic narration-ready event is either admitted whole or replaced by a content-free suppression event. Update coordinator diagnostic switches with content-free event names only.
- [ ] Re-run the two suites plus `swift test --filter ACPClientConnectionTests`. GREEN evidence: wire order, completion flush, cancellation, and delivery coalescing all pass without regressing standard messages.

### Task 4: Present every channel and narrate only the right one

**Files:** App audio/presentation files and the two new App test files

- [ ] Add `AgentConversationAudioResponseChannelTests.spokenDelta_IsVisibleButDoesNotSpeakBeforeReady`, `...spokenReady_NarratesOneVerbatimUnit`, `...displayDelta_DoesNotNarrate`, `...legacyDelta_RetainsMarkdownNarration`, `...oversizeOrDroppedSpokenUnit_IsRejectedWhole`, `...restoredSpokenUnit_RemainsSilent`, `...backgroundLiveSpokenUnit_NarratesOnceWithoutStartingWorkingPulse`, and `...cancelledRun_RejectsLateSpokenDelta` using the existing audio spy—never real sound or network.
- [ ] Add `AgentSpeechQueueVerbatimTests.verbatim_PreservesWhitespace`, `...verbatim_WhenFull_RejectsWithoutCoalescing`, `...verbatim_WhenOversized_RejectsWithoutPrefixing`, and a legacy regression proving current normalization/coalescing remains intact.
- [ ] Add `AgentRunPresentationResponseChannelTests.spokenAndDisplayDeltas_RemainSeparatelyVisibleAndCopyable`, `...spokenOutput_TruncatesAtBound`, and `...staleRun_CannotAppendEitherChannel`.
- [ ] Run `swift test --filter 'AgentConversationAudioResponseChannelTests|AgentRunPresentationResponseChannelTests'`. RED evidence: the new cases are not handled and no spoken presentation kind exists.
- [ ] Add narration input format and speech admission policy on `AgentSpeechRequest`, branch inside `AgentSpeechQueue.enqueue`, update audio spies/call sites, process typed/legacy cases as specified, and preserve generation-first cancellation. Typed speech is one plain agent-text unit admitted without silent truncation; only the legacy route uses `AgentMarkdownFormatter`.
- [ ] Add the Spoken timeline treatment and bounded snapshot field. Give the row a VoiceOver label such as “Spoken response”; keep the agent's text unchanged.
- [ ] Re-run both suites and `swift test --filter AgentConversationAudioPresenterTests`. GREEN evidence: the spy receives only typed spoken and legacy fallback text, visible snapshots retain both typed channels, and stale events do nothing.

### Task 5: Document, validate the bundled app, and prove fallback behavior

**Files:** the documentation set named in the file map

- [ ] Document the three behavior levels: standard ACP legacy fallback, current-adapter marker contract, and optional namespaced provider extension. State plainly that ACP v1 has no standard spoken channel.
- [ ] Document settings/privacy: typed spoken content follows “Reads replies aloud,” may reach the selected TTS provider, remains visible, and is never produced from raw tool payloads.
- [ ] Add troubleshooting for an agent that ignores the marker contract: the response safely appears and is narrated through legacy behavior; capture content-free event counts, not the response.
- [ ] Run `swift test`, then `swift test --sanitize=thread`. Expected evidence: all suites pass and ThreadSanitizer reports no race in routing, cancellation, or speech callbacks.
- [ ] Run `CONFIGURATION=debug make app`, `codesign --verify --deep --strict .build/VoiceActivation.app`, `make check`, and `git diff --check`. Expected evidence: the bundle builds, signature verifies, repository checks pass, and no whitespace errors appear.
- [ ] Manually exercise bundled-app scenarios with a deterministic fake ACP process: typed metadata, split markers, unmarked legacy, malformed metadata, light/dark mode, VoiceOver, “Reads replies aloud” off, another app focused, and barge-in. Verify no real provider, paid prompt, TCC reset, Keychain value, or live sound is required for automated coverage.

## Documentation acceptance criteria

- `docs/agent-harness.md` owns the exact wire shapes, namespace/version rules, fallback behavior, and raw-payload privacy boundary.
- `docs/architecture.md` shows the decoder → router → bounded delivery → presentation/audio path and states which agent-authored text can reach cloud TTS.
- `README.md` explains user-visible spoken/display/legacy behavior and accessibility without claiming every ACP agent supports typed channels.
- `docs/troubleshooting.md` describes content-free channel counters and legacy fallback.

## Dependencies on the companion plans

- `2026-09-05-spoken-confirmations-and-results.md`: implement this response channel first so post-permission results have an explicit agent-authored spoken route. Confirmations still have a standard-event fallback if sequencing changes.
- `2026-09-05-mac-context-snapshot.md`: context may change what the agent says, but it must enter the ACP prompt as typed context and never alter channel routing.
- `2026-09-05-conversational-control-semantics.md`: that plan owns the meaning of “stop,” “continue,” and corrections. This feature only obeys admitted typed events and cancellation identities.
- `2026-09-05-durable-continuity.md`: land its generic `ACPClientCapabilities` composer first. The app persists no transcript or channel content. Restored routing is typed-if-present, then marker-if-present, then silent legacy-visible fallback. Each restoration token owns isolated router state, and replay never autoplays.
- `2026-09-05-background-task-continuity.md`: a newly admitted `.live` background result for the retained session may enqueue one spoken unit even between turns. Restored/task-metadata/stale callbacks cannot speak, and this audio path never starts or prolongs the prompt working pulse.

None of the other plans may bypass ACP by making the app author a response.

## Explicit non-goals

- Generating, shortening, translating, correcting, or ranking agent prose in the app.
- Guessing a spoken section from Markdown, tool kind, plan status, result payload, or sentence position.
- Adding another model, app server, account, shell, MCP server, or paid synthesis call to obtain a summary.
- Making the extension a prerequisite for ACP compatibility or claiming it is standard ACP v1.
- Speaking agent thoughts, raw tool input/output, diagnostics, restored history, or display-only content.
- Changing provider authentication, voice catalog behavior, TTS credentials, or existing cloud-to-system fallback.
- Replacing the permission protocol; that belongs to the companion spoken-confirmations plan.

## Definition of done

The feature is complete only when standard unmarked ACP messages still behave exactly as before, valid typed metadata and split marker streams produce separate visible/spoken channels, every fallback preserves the original text, cancellation rejects retired work, speech never depends on raw tool data, the full verification matrix passes, and the documentation accurately separates ACP-standard behavior from Voice Activation/provider extensions.
