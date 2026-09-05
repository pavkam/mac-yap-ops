<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Spoken Confirmations and Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for task-by-task execution in this session, or `superpowers:executing-plans` in a separate session. Load the project `development`, `acp-integration`, `ux`, `voice-reading`, and `testing-and-debugging` skills before changing code.

**Goal:** Speak the ACP provider/adapter's exact confirmation presentation and offered choices, preserve the request and selected-option identities end to end, then speak only the agent-authored result that follows the decision.

**Architecture:** Extend the existing permission event with bounded, typed presentation text decoded from the permission `_meta` already emitted by the pinned Codex and Claude adapters. Standard ACP falls back to its human-readable tool title and exact option labels. App audio keeps a bounded identity-keyed queue of pending prompts, while the existing ACP connection remains the sole owner of permission selection and cancellation. Results arrive through ordinary agent messages or the companion voice-first response channel; the app never synthesizes them from tool state.

**Tech stack:** Swift 6.2, Swift Testing, ACP v1 `session/request_permission`, SwiftUI/AppKit, `AVSpeechSynthesizer`, and the existing ElevenLabs adapter.

**Spec:** This document is the approved feature contract and implementation plan. No separate speculative design is required.

## Product boundary

Voice Activation is a thin native voice/runtime bridge. It may transport and render/speak typed provider presentation text and agent-authored content, arbitrate audio/cancellation, and retain opaque identities. The ACP agent owns semantics, planning, tool use, confirmation decisions, result interpretation, memory, and task execution. The provider/adapter may supply permission UI wording. Do not make the app infer which tool is dangerous, summarize results, rewrite prose, or implement a second dialogue policy.

Accordingly, the app can announce a permission request by speaking fields the provider/adapter explicitly supplied. It cannot claim those fields were authored by the model, invent “This is dangerous,” turn raw command arguments into prose, claim an action succeeded, or infer a result from tool status.

## Feature contract

### Observable scenarios

1. The user says, “Delete the old downloads.” The provider presents the ACP permission with title “Move 43 old downloads to Trash?” and options “Allow once” and “Deny.” Voice Activation speaks those three exact strings as separate utterances and shows the same prompt. Saying “Allow once” returns the exact associated `optionId` on the exact JSON-RPC request.
2. The agent provides no permission presentation extension. Voice Activation speaks the standard ACP tool-call title, if present, followed by the exact standard option labels in wire order. It adds no explanatory words.
3. Two permission requests are pending. Audio and cards preserve arrival order. Resolving the older request stops any queued speech for that exact request and requeues only the still-pending prompts; a reused JSON-RPC ID from another turn cannot cross the turn-token boundary.
4. The user answers with an unrecognized or ambiguous phrase. The app sends no option and leaves the permission unresolved for the existing conversation-control path; this feature does not guess.
5. The agent resumes after permission and reports “Done — 43 items are in Trash.” That exact agent message is narrated through the legacy response path or, once `2026-09-05-voice-first-response-channel.md` is implemented, through its typed spoken channel. The app never says “Done” based on a completed tool update.
6. The user cancels while a permission prompt is speaking. Voice Activation invalidates the turn, clears identity-keyed prompt state, cancels synthesis/playback, returns ACP `cancelled` for every pending request, and does not speak the current app-authored “Stopped.” phrase.
7. “Reads replies aloud” is off. Permission cards and exact choices remain usable by mouse, keyboard, VoiceOver, and voice input, but no confirmation or result prose is sent to TTS.

### Exact spoken sequence

For each admitted request, enqueue these nonempty strings as separate, unmodified utterances:

1. provider-extension `title`, otherwise standard `toolCall.title`;
2. provider-extension `description`, when present;
3. every standard ACP `PermissionOption.name`, in wire order.

There is no app-authored prefix, conjunction, numbering, warning, or suffix. A pause between utterances supplies separation without changing text. If the total is empty or exceeds the 20,000-character narration admission limit, speak none of that request; retain the complete visible card and record only a content-free suppression reason. Partial speech or truncation would change the agent's offer and is forbidden.

## Protocol proof and fallback

### Standard ACP behavior

The [ACP v1 schema](https://agentclientprotocol.com/protocol/v1/schema) defines `session/request_permission` with `sessionId`, `toolCall`, and `options`. Each option has human-readable `name`, semantic `kind`, and opaque `optionId`. The selected response carries the exact `optionId`; cancelling a prompt turn requires a `cancelled` response for every pending permission request.

ACP v1 does **not** define a distinct confirmation sentence or spoken-confirmation field. The standard portable source is therefore the human-readable tool title plus exact option labels. `toolCall.rawInput`, `rawOutput`, `content`, and `locations` exist for other client presentation needs, but are not confirmation wording and must never enter this feature's model.

### Pinned-provider enhancement

Both pinned adapters already emit the same typed request-level extension:

```json
{
  "_meta": {
    "permission": {
      "version": 1,
      "title": "Run command?",
    "description": "Provider presentation detail, when supplied."
    }
  }
}
```

[Codex ACP 1.8.0 `metadata.ts`](https://github.com/agentclientprotocol/codex-acp/blob/v1.8.0/src/permissions/metadata.ts) defines `{ permission: { version: 1, title, description? } }` and separate option-description metadata. [Claude Agent ACP 0.73.0 `presentation.ts`](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/permissions/presentation.ts) emits the same request shape. This is a provider extension carried legally under ACP's [`_meta` extensibility mechanism](https://agentclientprotocol.com/protocol/v1/extensibility), not portable ACP v1.

Decode only request-level `_meta.permission.version == 1`, `title`, and optional `description`. Do not decode option descriptions in this release: the exact standard option `name` remains the choice users both hear and select. Unknown or invalid extension data is ignored without rejecting a valid standard permission request.

### Result fallback

ACP has no separate “result to speak” field. The portable result is the next agent-authored `agent_message_chunk`, which current behavior already displays and narrates. The companion voice-first response plan adds explicit spoken/display routing through a client-advertised extension plus an instruction-level marker contract. Until then, results retain legacy narration. In neither path may the app convert tool completion, raw output, a plan, or a stop reason into result prose.

## Current-state evidence

- `Sources/VoiceActivationCore/AgentRunEvent.swift` defines `AgentPermissionOption(id:label:kind:)`, `AgentPermissionRequest(turnToken:requestID:toolCall:options:)`, and `.permissionRequested`.
- `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift`, `decodePermissionRequest(params:)`, retains only session ID, tool-call ID/title/kind/status, and option ID/name/kind. It already discards `rawInput`, `rawOutput`, content, and locations—keep that privacy boundary.
- `Sources/VoiceActivationCore/ACPClientConnection.swift` keys pending requests by `PendingPermissionKey(turnToken:requestID)`, caps them at 32, checks the selected ID against the retained offered options, and settles all pending requests as cancelled on turn cancellation.
- `Sources/VoiceActivationCore/AgentRunEventDelivery.swift` caps permission options at 64, queued entries at 256, pending control data at 512 KiB, and opaque identities at 4 KiB.
- `Sources/VoiceActivationApp/AgentRunPresentationModels.swift` has `AgentPermissionKey(turnToken:requestID)` and `AgentPermissionPresentation`, but no typed provider/adapter presentation detail.
- `Sources/VoiceActivationApp/AgentRunPresentation+Events.swift` presents `toolCall.title` and falls back visually to the app-authored label “Agent action.” That UI fallback must not be spoken.
- `Sources/VoiceActivationApp/AgentPermissionVoiceCommand.swift` returns the exact retained option ID after matching an exact label or the existing fixed allow/deny vocabulary. This plan adds no new decision vocabulary.
- `Sources/VoiceActivationApp/AppModel+AgentConversation.swift` resolves the oldest visible request using its exact turn token and request ID, but calls `AgentConversationAudioPresenter.resumeAfterPermission(runID:)` without a permission identity.
- `Sources/VoiceActivationApp/AgentConversationAudio.swift`, `AgentConversationAudioPresenter.handle`, currently marks a permission as a narration boundary and stops the working sound but says nothing. On a cancelled completed run it speaks the app-authored string “Stopped.”
- `Sources/VoiceActivationApp/AgentNarrationSegmenter.swift` and `AgentSpeechQueue.swift` own bounded, generation-safe narration and playback. The queue currently trims, prefixes, and coalesces strings, so the verbatim path needs reject-without-rewrite admission at the real queue owner.
- `Tests/VoiceActivationCoreTests/ACPClientConnectionPermissionTests.swift` already exercises wire identities and policy outcomes. `Tests/VoiceActivationAppTests/AgentConversationAudioActivityTests.swift` currently asserts “Stopped.” and must change.

## Chosen architecture

### Exact Core types

Add a small typed extension payload and carry it on the existing permission event:

```swift
/// Provider/adapter-supplied presentation text for one blocking permission request.
public struct AgentPermissionPresentationText: Equatable, Sendable {
    public let title: String
    public let description: String?

    public init(title: String, description: String?) {
        self.title = title
        self.description = description
    }
}

public struct AgentPermissionRequest: Equatable, Sendable {
    public let turnToken: AgentTurnToken
    public let requestID: ACPRequestID
    public let toolCall: AgentToolCallUpdate
    public let options: [AgentPermissionOption]
    public let presentationText: AgentPermissionPresentationText?
}
```

Define and reuse these bounds in Core:

```swift
public static let maximumPermissionPromptTitleBytes = 4 * 1024
public static let maximumPermissionPromptDescriptionBytes = 8 * 1024
```

Validate UTF-8 byte counts, non-whitespace title, and absence of NUL. Preserve accepted strings exactly—validation may inspect a trimmed view but must not store it. If any extension field is wrong or oversized, set `prompt` to `nil` and continue decoding the standard request. Include accepted prompt bytes in `permissionRetainedByteCount` and the existing delivery/control admission.

### Exact App identities and APIs

Add an App-only audio key because run identity does not belong on the ACP wire:

```swift
private struct AgentPermissionAudioKey: Hashable, Sendable {
    let runID: UUID
    let turnToken: AgentTurnToken
    let requestID: ACPRequestID
}

private struct PendingPermissionNarration: Equatable, Sendable {
    let key: AgentPermissionAudioKey
    let utterances: [String]
}
```

Replace the unkeyed method:

```swift
func permissionResolutionBegan(
    runID: UUID,
    turnToken: AgentTurnToken,
    requestID: ACPRequestID
)
```

`AgentConversationAudioPresenter` retains at most 32 pending narrations in arrival order. A request builds exact utterances from `prompt`, standard title fallback, and standard labels. Duplicate event identities are ignored. Exact resolution removes only that key, resets narration generation, calls `stopSpeaking()`, and re-enqueues the still-pending requests in arrival order so no already-resolved prompt remains queued. It keeps the working pulse off while any permission remains; otherwise it resumes the current behavior while the ACP agent continues.

To support exact speech shared with the voice-first response plan, change the App audio bridge to distinguish compatibility normalization from exact admission:

```swift
enum AgentSpeechTextPolicy: Sendable {
    case legacyNormalized
    case verbatim
}

func speak(
    _ text: String,
    localeID: String,
    policy: AgentSpeechTextPolicy
)
```

Carry this policy on `AgentSpeechRequest` all the way into `AgentSpeechQueue.enqueue`. `.legacyNormalized` preserves current prefix/trim/coalescing behavior. `.verbatim` accepts a nonempty string only when it is within 20,000 characters and queue capacity is available, then enqueues it unchanged. It never trims, prefixes, suffixes, or coalesces. Oversize or full-queue input is rejected as a whole with a content-free reason. Test spies record the policy. Permission utterances and completed typed spoken-response units use `.verbatim`.

### Presentation behavior

Extend `AgentPermissionPresentation` with `promptTitle` and `promptDescription`. Prefer `request.presentationText.title`; otherwise show the standard `toolCall.title`; only the visible UI may use its neutral “Agent action” chrome when both are absent. Show the provider description above the buttons. Options remain the exact standard labels and preserve wire order.

VoiceOver reads title, description, and each control's exact label. Buttons and recognized phrases still resolve via the retained `AgentPermissionKey` and `option.id`; display strings are never used as JSON-RPC identities.

### File map

Create:

- `Tests/VoiceActivationCoreTests/ACPClientConnectionPermissionPromptTests.swift`
- `Tests/VoiceActivationAppTests/AgentConversationAudioPermissionTests.swift`
- `Tests/VoiceActivationAppTests/AgentSpeechQueueVerbatimTests.swift`
- `Tests/VoiceActivationAppTests/AgentRunPresentationPermissionPromptTests.swift`
- `Tests/VoiceActivationAppTests/AgentPermissionResultFlowTests.swift`

Modify:

- Core: `AgentRunEvent.swift`, `ACPClientConnection+Receive.swift`, `ACPClientConnectionSupport.swift`, `AgentRunEventNormalization.swift`, and `AgentRunEventDeliveryEntry.swift`.
- App: `AgentConversationAudio.swift`, `AgentNarrationSegmenter.swift`, `AgentSpeechQueue.swift`, `AgentRunPresentationModels.swift`, `AgentRunPresentation+Events.swift`, `AgentRunPanelActivity.swift`, `AgentPermissionVoiceCommand.swift`, and `AppModel+AgentConversation.swift`.
- Existing tests/support: `ACPClientConnectionPermissionTests.swift`, `ACPClientConnectionTestSupport.swift`, `AgentConversationAudioActivityTests.swift`, `AppModelConversationTests.swift`, and audio/presentation spies whose protocol signature changes.
- Documentation: `README.md`, `docs/agent-harness.md`, `docs/architecture.md`, and `docs/troubleshooting.md`.

Before editing, run `rg -n 'AgentPermissionRequest\(|AgentPermissionPresentation\(|resumeAfterPermission|func speak\(' Sources Tests` and update each compile-time call site. Add new test files instead of growing a test file toward the 700-line limit.

## ACP wire and data flow

```text
ACP agent decides confirmation is required
  -> session/request_permission(request JSON-RPC id,
       toolCall human title + unretained raw payload,
       exact ordered optionId/name/kind,
       optional _meta.permission v1 title/description)
  -> ACPClientConnection validates and bounds retained fields
  -> pendingPermissions[(turnToken, requestID)] retains exact offered IDs
  -> AgentPermissionRequest carries typed wording, no raw payload
  -> bounded delivery + coordinator run/turn gate
  -> panel shows exact prompt/labels
  -> audio queue speaks exact prompt/labels under (runID, turnToken, requestID)
  -> user selects by button or recognized phrase
  -> AppModel sends exact key + option ID to coordinator
  -> ACPClientConnection validates option ID against that exact pending request
  -> RequestPermissionResponse selected(optionId) or cancelled
  -> ACP agent executes/declines and authors a result agent message
  -> response channel or legacy narration speaks that agent-authored result
```

No layer reconstructs a permission prompt from raw arguments. No layer derives success or failure prose from a tool event.

## Privacy, bounds, identity, and cancellation

- Never log prompt title, description, option labels/IDs, request IDs, tool titles, transcripts, tool payloads, or spoken text. Diagnostics may record bounded counts and reasons such as `extension_invalid`, `speech_disabled`, `speech_oversized`, and `stale_identity`.
- Continue discarding `rawInput`, `rawOutput`, tool content, and locations in `decodePermissionRequest`. Do not add them to `AgentPermissionRequest`, presentation snapshots, or audio state.
- Keep request ID paired with `AgentTurnToken`; audio adds `runID`. JSON-RPC string, integer, and null IDs remain opaque and are returned in their original form by the existing connection.
- Keep the existing maximum 32 pending requests and 64 options per request. Prompt metadata adds at most 12 KiB before existing 512 KiB control admission. Narration rejects an entire request above 20,000 characters rather than truncating any wording.
- On cancellation: invalidate turn admission first; clear pending audio identities and reset narration generation; stop speech; settle each connection-level pending permission once with ACP `cancelled`; then await the original prompt's cancelled stop reason. Late callbacks cannot recreate audio state.
- `permissionResolutionBegan` must be a no-op for a stale run, turn, or request and must not stop current speech for another active identity.
- The “Reads replies aloud” setting governs both confirmation and result prose. System speech stays local; configured ElevenLabs speech follows the existing Keychain and network privacy contract. No automated test uses live sound, a secret, or a paid request.
- The panel remains non-activating and preserves foreground-app focus. Keyboard and VoiceOver controls remain complete when speech is disabled or unavailable.

## Rejected alternatives

- **Read raw command input or a diff aloud:** rejected because payloads may contain secrets and are not provider presentation wording.
- **Infer danger from ACP tool kind:** rejected because the ACP agent owns whether and how to request confirmation.
- **Invent “Do you want to allow this?” around standard fields:** rejected because the app would become a second dialogue author.
- **Treat `_meta.permission` as standard ACP:** rejected; it is a compatible provider extension even though both pinned adapters emit it.
- **Require the extension:** rejected because any conforming ACP agent must still work via standard title and option labels.
- **Select by array position or display title:** rejected because only the exact offered `optionId` is a valid wire decision.
- **Keep an unkeyed audio resume:** rejected because request IDs can be reused across turns and multiple permissions can be pending.
- **Speak a local success sentence on tool completion:** rejected because only the ACP agent can interpret and report the result.
- **Speak “Stopped.” after cancellation:** rejected because it is app-authored response prose and can race with newer speech.

## Phased TDD implementation

### Task 1: Decode bounded provider/adapter permission presentation

**Files:** Core permission types/decoder/support and `ACPClientConnectionPermissionPromptTests.swift`

- [ ] Add `ACPClientConnectionPermissionPromptTests.requestPermission_WithV1Metadata_PublishesExactPromptAndOptions` using string and integer request IDs. Assert exact title, description, turn token, request ID, option order, labels, and IDs.
- [ ] Add `...WithMissingUnknownOrMalformedMetadata_FallsBackToStandardFields` and `...WithOversizedMetadata_DoesNotRejectValidStandardPermission`. Include wrong version, non-string fields, blank title, NUL, and byte-limit cases.
- [ ] Add `...WithRawToolPayload_DoesNotRetainOrPublishPayload` containing a recognizable secret sentinel and assert it occurs nowhere in the event description or retained model.
- [ ] Run `swift test --filter ACPClientConnectionPermissionPromptTests`. RED evidence: `AgentPermissionRequest.prompt` does not compile and the current decoder drops `_meta.permission`.
- [ ] Implement the DocC types and strict optional-extension decoder. Preserve valid strings and exact identities; update retained-byte accounting without retaining the original metadata object.
- [ ] Re-run the suite plus `swift test --filter ACPClientConnectionPermissionTests`. GREEN evidence: valid extension text survives exactly, invalid metadata uses standard fallback, raw payload remains absent, and existing selection/cancellation tests pass.

### Task 2: Render exact prompts while identities remain opaque

**Files:** presentation model/event/panel files and `AgentRunPresentationPermissionPromptTests.swift`

- [ ] Add `AgentRunPresentationPermissionPromptTests.extendedPrompt_ShowsExactTitleDescriptionAndOrderedOptions` and `...standardFallback_ShowsToolTitleWithoutCreatingSpokenCopy`.
- [ ] Add `...sameRequestIDAcrossTurns_RemainsDistinct`, `...duplicateDeliveryIdentity_DoesNotDuplicateCard`, and `...staleRun_CannotRestoreResolvedPrompt`.
- [ ] Run `swift test --filter AgentRunPresentationPermissionPromptTests`. RED evidence: presentation has no prompt description and cannot assert the typed source.
- [ ] Extend the model and event reducer, retaining `AgentPermissionKey` exactly. Add accessible title/detail and controls without activating the app or changing option labels.
- [ ] Keep “Agent action” strictly as visual chrome when no agent title exists; do not place it in the audio model.
- [ ] Re-run the focused suite. GREEN evidence: exact provider/standard wording is visible, option order and IDs survive, and stale/duplicate events are inert.

### Task 3: Speak exact, identity-keyed permission queues

**Files:** App audio bridge/presenter/segmenter/queue, audio spies, `AgentConversationAudioPermissionTests.swift`, and `AgentSpeechQueueVerbatimTests.swift`

- [ ] Add `AgentConversationAudioPermissionTests.extendedPrompt_SpeaksExactFieldsAndStandardLabelsInOrder` and `...standardFallback_SpeaksToolTitleAndLabelsWithoutInventedWords`.
- [ ] Add `...oversizedPrompt_SpeaksNothingRatherThanTruncating`, `...readsRepliesDisabled_SpeaksNothing`, and `...rawPayloadSentinel_NeverReachesAudioSpy`.
- [ ] Add `...resolvingExactRequest_RemovesOnlyThatQueueEntry`, `...reusedRequestIDFromAnotherTurn_IsNotRemoved`, `...cancellation_ClearsAllPendingSpeechBeforeLateCallback`, and `...completedCancellation_DoesNotSpeakStopped`.
- [ ] Add queue-owner tests `verbatim_LeadingAndTrailingWhitespace_IsPreserved`, `verbatim_WhenOverLimit_RejectsWholeRequest`, `verbatim_WhenQueueIsFull_RejectsWithoutCoalescing`, and `legacyNormalized_RetainsExistingTrimPrefixAndCoalescing`.
- [ ] Run `swift test --filter AgentConversationAudioPermissionTests`. RED evidence: permissions emit no speech, resolution accepts only a run ID, and cancellation still emits “Stopped.”
- [ ] Implement the verbatim speech policy on `AgentSpeechRequest` and branch inside `AgentSpeechQueue.enqueue`, plus pending narration types, admission builder, and keyed resolution API. Remove the app-authored cancellation sentence. Clear identities on start/follow-up/cancel/fail/complete/shutdown.
- [ ] Re-run the suite plus `swift test --filter AgentConversationAudioPresenterTests`. GREEN evidence: spy calls are exact and ordered, oversize is all-or-nothing, stale identities do nothing, and cancellation emits no prose.

### Task 4: Preserve exact selection across mouse and voice paths

**Files:** `AppModel+AgentConversation.swift`, `AgentPermissionVoiceCommand.swift`, and their focused tests

- [ ] Add `AppModelTests.agentConversation_WhenPermissionResolves_ForwardsExactTurnRequestAndOptionIdentityToAudioAndCoordinator` in `AppModelConversationTests.swift` for button and voice resolution.
- [ ] Add `AgentPermissionVoiceCommandTests.duplicateNormalizedLabels_ReturnsNoDecision` and `...unrecognizedPhrase_ReturnsNoDecision`; ambiguity must not select the first display match.
- [ ] Run `swift test --filter 'AppModelTests|AgentPermissionVoiceCommandTests'`. RED evidence: audio receives no exact permission identity and duplicate labels currently select the first option.
- [ ] Pass the full key to `permissionResolutionBegan` before sending the exact retained option ID. Change exact-label matching to require one unique match; leave the existing fixed semantic vocabulary otherwise unchanged.
- [ ] Keep the oldest-visible-permission rule and existing ACP option-kind mapping. Any broader conversational repair belongs to `2026-09-05-conversational-control-semantics.md`.
- [ ] Re-run both suites. GREEN evidence: every successful response identifies one run, turn, request, and offered option; ambiguity produces no wire response.

### Task 5: Prove agent-authored results and document the boundary

**Files:** response-channel integration tests and the documentation set in the file map

- [ ] Add an end-to-end fake-transport test `AgentPermissionResultFlowTests.selectedPermission_ResultComesOnlyFromFollowingAgentMessage` that emits permission → exact selection → tool completion → agent message. Assert no result speech at tool completion and one speech call only for the agent message.
- [ ] Add `...cancelledPermission_SettlesRequestAndEmitsNoResultProse`. Assert one cancelled JSON-RPC response and zero app-authored speech.
- [ ] Run `swift test --filter AgentPermissionResultFlowTests`. RED evidence: the current cancellation sentence appears or result-channel integration is absent.
- [ ] Document standard ACP fallback versus `_meta.permission`, exact identity handling, reads-aloud behavior, raw-payload exclusion, result ownership, multiple pending requests, and cancellation.
- [ ] Run `swift test`, then `swift test --sanitize=thread`. Expected evidence: all suites pass and ThreadSanitizer reports no race in request resolution, pending audio state, or cancellation callbacks.
- [ ] Run `CONFIGURATION=debug make app`, `codesign --verify --deep --strict .build/VoiceActivation.app`, `make check`, and `git diff --check`. Expected evidence: bundle/signature/repository checks pass with no whitespace or line-limit failures.
- [ ] Manually exercise the bundled app with a deterministic fake ACP process: extended and standard prompts, two simultaneous requests, voice/mouse/keyboard selection, duplicate labels, Reads replies off, light/dark mode, VoiceOver, another app focused, barge-in, and cancellation. Automated verification must not authenticate, start a model session, play real sound, access secrets, or make paid calls.

## Documentation acceptance criteria

- `docs/agent-harness.md` owns the exact standard request/response fields, `_meta.permission` provider extension, fallback, bounds, and cancellation settlement.
- `docs/architecture.md` shows that raw tool payload is discarded before permission presentation/audio and that identity flows independently of labels.
- `README.md` explains that the app can speak agent-requested confirmation and agent-authored results without claiming spoken wording is standard ACP.
- `docs/troubleshooting.md` covers missing provider metadata, disabled speech, oversize all-or-nothing suppression, ambiguous voice choices, and content-free diagnostic evidence.

## Dependencies on the companion plans

- `2026-09-05-voice-first-response-channel.md`: preferred first dependency for an explicit agent-authored spoken result. Without it, ordinary agent-message narration remains the complete fallback.
- `2026-09-05-mac-context-snapshot.md`: snapshot context may help the agent decide and word a request, but this feature never inspects the snapshot to decide whether permission is required.
- `2026-09-05-conversational-control-semantics.md`: owns repair of ambiguous answers and the semantics of cancel/continue. This feature retains exact identities and performs only deterministic option matching.
- `2026-09-05-durable-continuity.md`: may preserve provider session correlation, but the app persists no permission request identity, confirmation prose, option labels, transcript, or queued audio. Historical permission requests are rejected during load; only a newly emitted live `session/request_permission` can be shown or spoken.
- `2026-09-05-background-task-continuity.md`: a permission emitted while its originating prompt is deliberately held open follows the normal turn-token path and remains actionable. A permission emitted after prompt settlement has no live permission owner, so it is cancelled silently and is never retained, replayed, or narrated.

None of these plans may bypass the ACP permission owner or manufacture a result in the app.

## Explicit non-goals

- Deciding which operations need permission or whether a tool is dangerous.
- Reading, retaining, logging, or converting raw tool input/output, locations, diffs, commands, or diagnostics into speech.
- Inventing confirmation questions, warnings, explanations, option aliases, success claims, failure summaries, or cancellation prose.
- Changing ACP policy presets, provider authentication, agent execution, or tool handling.
- Sending a selection that was not one of the exact options retained for the exact pending request.
- Treating provider `_meta.permission` as mandatory or standard ACP.
- Persisting prompt/result content or replaying speech after restore.
- Adding another model call, app server, account, shell, or MCP server.

## Definition of done

The feature is complete only when both pinned provider/adapter presentations and standard ACP fallbacks are spoken from exact retained human text, raw payloads cannot reach audio, option/request/turn/run identities survive every route, ambiguous input cannot select arbitrarily, cancellation settles once without app-authored prose, results are spoken only from agent messages, and the full automated, bundled-app, accessibility, privacy, and documentation checks pass.
