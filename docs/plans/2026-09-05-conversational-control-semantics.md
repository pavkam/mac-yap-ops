<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Conversational Control Semantics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user keep talking while an ACP turn is running without Voice Activation guessing what the words mean or cancelling useful work.

**Architecture:** Voice Activation treats every non-reserved utterance as opaque agent input. It offers that input to a capability-gated, lifecycle-safe ACP steering extension when the exact initialized provider contract proves the idle race remains host-owned; otherwise it keeps the input in a bounded FIFO and submits it as the next ordinary `session/prompt`. The ACP agent decides whether “also add”, “actually replace”, “pause”, or “what are you doing?” changes the work.

**Tech Stack:** Swift 6.2, Swift Testing, ACP v1 JSON-RPC over stdio, `VoiceActivationCore`, SwiftUI/AppKit presentation, Apple Speech.

**Spec:** This document contains the approved feature contract. There is no separate speculative design document.

## Global constraints

- Voice Activation is a thin native voice/runtime bridge. It may capture bounded native context, transport typed ACP content/events, speak agent-authored output, and retain opaque provider/session/task identifiers.
- The ACP agent owns semantic interpretation, planning, tool use, memory content/logic, and task execution.
- Do not create local natural-language intent parsing, local task planning, or a second agent inside the app.
- App-level semantics are explicit transport controls only; ordinary language remains agent input.
- Keep framework-independent queue, capability, identity, and cancellation policy in `VoiceActivationCore`; keep presentation mapping in `VoiceActivationApp`.
- Keep every queue and retained string bounded, preserve FIFO order, and reject callbacks from retired run, turn, session, request, and routing identities.
- Never log prompt text, transcripts, provider output, raw ACP payloads, or credentials.
- Preserve direct process execution, macOS 15, Swift tools 6.2, four-space Swift indentation, public Core DocC, and the 700-line Swift file limit.

---

## Feature contract

The app reserves only explicit local transport controls already visible in the product: exact capture cancellation, exact conversation end (`stop`, `cancel`, or `dismiss`), the panel's **Stop turn**, permission-option selection, and **End conversation**. Everything else goes to the ACP agent unchanged.

Concrete voice scenarios:

1. While Claude Agent ACP 0.73.0 is actively working, Alex says “also add a regression test.” The app stops reply playback if necessary, sends `_session/steering`, receives `injected`, and marks the utterance **Added to current turn**. It does not cancel `session/prompt` and does not start another prompt.
2. In the same state Alex says “actually, use the parser fixture instead.” The wire path is identical. The app does not classify this as replacement; Claude interprets it.
3. While Cursor or the pinned Codex ACP 1.8.0 is working, Alex says either sentence. The app displays **Queued for next turn**, allows the current prompt to finish, then sends one ordinary `session/prompt` per utterance in original order.
4. A Claude steering request reaches the adapter just after the turn becomes idle. The request includes `_meta.steering.idleBehavior = "promptRequired"`; `promptRequired` leaves the content unconsumed, so the app submits it once through `session/prompt`.
5. Steering fails after its request was written or returns `startedNewTurn`. The app does not replay the utterance because provider-side acceptance is ambiguous. It cancels/closes that cached connection, marks the input **Delivery failed — say it again**, and preserves later FIFO entries for a fresh normal turn.
6. Alex asks “what are you doing?”, “pause after this file”, or “repeat that more briefly.” These are ordinary agent inputs. No Swift switch, regex, locale table, or keyword list assigns their meaning.
7. Alex says exactly `stop`, `cancel`, or `dismiss`. The existing explicit transport control ends the conversation. This reserved behavior stays documented and visually discoverable.
8. Alex speaks over narration. Barge-in stops only queued/playing speech first; the resulting utterance then follows the steering-or-FIFO rules above. Agent work is not cancelled merely because audio was interrupted.
9. Seventeen inputs arrive while sixteen are pending. The seventeenth is rejected before retention with the existing queue-full notice; it is not partly sent or silently dropped.

Acceptance is observable in the timeline: each submitted utterance has one stable ID and one transport state: **Routing**, **Added to current turn**, **Queued for next turn**, **Started as next turn**, or **Delivery failed**. These labels describe transport, not inferred intent.

## Current-state evidence

- `Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift` → `submitAgentFollowUp(_:)` appends the prompt, then cancels `executionTask` and calls `beginAgentCancellation(runID:)` whenever a turn is active. Any mid-turn utterance therefore discards the current turn before the agent can interpret whether it was additive or corrective.
- The same file → `startNextAgentPrompt()` already owns a bounded FIFO of at most `VoiceActivationCoordinator.maximumPendingAgentPrompts == 16`; that is the correct portable fallback, but it is currently reached only after cancellation.
- `Sources/VoiceActivationCore/VoiceActivationCoordinator+Speech.swift` → `finishConversationUtterance()` reserves exact cancellation phrases and otherwise calls `submitAgentFollowUp(_:)`. It does not otherwise classify ordinary language. Preserve that boundary.
- `Sources/VoiceActivationCore/AgentHarnessRunning.swift` exposes `run`, permission resolution, cancellation, reset, and shutdown, but no side-band input operation.
- `Sources/VoiceActivationCore/ACPClientConnection.swift` → `prompt(_:onEvent:)` allows one active prompt, while `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` → `sendRequest(method:params:)` already supports multiple correlated JSON-RPC requests over the same actor-owned connection.
- `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` → `applyInitializeResult(_:)` currently keeps agent display name and authentication methods but discards `agentInfo.version` and top-level `_meta`. It cannot prove an extension contract yet.
- `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` sends `clientCapabilities: {}`. Steering itself needs no client advertisement in the two inspected adapters, but the response capability still must be parsed and gated.
- `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift` → `agentConversation_WhenFollowUpInterruptsTurn_CancelsBeforeStartingIt` locks in the behavior this feature deliberately replaces.
- `Sources/VoiceActivationApp/AgentRunPresentation.swift` → `submitFollowUp(runID:prompt:)` adds a user row immediately but has no delivery state, so the UI cannot tell whether the input steered or waited.
- `Sources/VoiceActivationApp/AgentConversationAudio.swift` and `Sources/VoiceActivationCore/VoiceActivationCoordinator+Speech.swift` already separate barge-in from recognized utterance submission. Reuse that lifecycle.

## Protocol and provider evidence

Stable ACP v1 defines one `session/prompt` request whose terminal response carries `stopReason`, plus `session/cancel`; it does not define queueing or steering. See the protocol-owner [Prompt Turn](https://agentclientprotocol.com/protocol/v1/prompt-turn) documentation and the protocol discussion explicitly describing v1's missing injection surface in [agent-client-protocol discussion #1220](https://github.com/orgs/agentclientprotocol/discussions/1220).

The exact project pins were inspected from their cached npm tarballs and official tagged sources on 2026-09-05:

- [Claude Agent ACP v0.73.0 `acp-agent.ts`](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/acp-agent.ts) advertises top-level `_meta.steering.supported: true`, accepts `_session/steering`, and supports the host-owned idle option `_meta.steering.idleBehavior: "promptRequired"`. Its response is `injected`, `promptRequired`, or the legacy `startedNewTurn`. The host-owned option is decisive: `promptRequired` promises that the adapter did not consume the content.
- [Codex ACP v1.8.0 `CodexAcpServer.ts`](https://github.com/agentclientprotocol/codex-acp/blob/v1.8.0/src/CodexAcpServer.ts) also advertises steering, but its pinned request parser ignores the host-owned idle option and starts a detached turn when no live turn remains. The response `startedNewTurn` has no standard prompt request that Voice Activation can await for terminal ownership. Therefore this pin must use the ordinary FIFO fallback despite advertising steering.
- [Cursor's ACP documentation](https://cursor.com/docs/cli/acp) documents the standard prompt/cancel path but no compatible host-owned steering extension. Cursor uses the FIFO fallback.

This is a compatibility allowlist, not provider favoritism: enable safe steering only when the initialize response reports name `@agentclientprotocol/claude-agent-acp`, version `0.73.0`, `_meta.steering.supported == true`, and the profile preset is `.claude`. A future pin stays on FIFO until its tagged source, deterministic fixtures, and initialize-only probe prove the same host-owned idle contract.

## Chosen design

### Transport types

Add these public Core values to `AgentHarnessRunning.swift`:

```swift
/// The safe transport result of offering user input during an active agent turn.
public enum AgentMidTurnInputResult: Equatable, Sendable {
    /// The provider accepted the text into the currently running turn.
    case injected
    /// The text remains locally owned and must be sent by a normal prompt.
    case promptRequired
}

/// The user-visible transport state of one conversation input.
public enum AgentConversationInputDisposition: Equatable, Sendable {
    /// Capability negotiation or a steering request is still in progress.
    case routing
    /// The provider accepted the input into the current turn.
    case injected
    /// The app retained the input for the next ordinary prompt.
    case queued
    /// The retained input began its own ordinary prompt.
    case prompted
    /// Delivery became ambiguous; the app will not replay the text automatically.
    case failed
}
```

Extend `AgentHarnessRunning` with:

```swift
/// Offers opaque user input to the active provider turn without interpreting it.
func offerMidTurnInput(
    profileID: UUID,
    prompt: AgentPrompt
) async throws -> AgentMidTurnInputResult
```

`ControlledAgentRunner` records offers and returns a controlled result. `ACPAgentRunner.offerMidTurnInput` returns `.promptRequired` without writing when there is no matching active turn/connection, then delegates to `ACPClientConnection.offerMidTurnInput(_:)` for the exact active connection.

### Capability proof

Add `Sources/VoiceActivationCore/ACPAgentCapabilities.swift`:

```swift
struct ACPAgentCapabilities: Equatable, Sendable {
    let agentName: String
    let agentVersion: String
    let supportsHostOwnedIdleSteering: Bool

    static func decode(
        initializeResult: ACPJSONValue,
        preset: AgentHarnessPreset
    ) throws -> ACPAgentCapabilities
}
```

`decode` validates bounded `agentInfo.name` and `agentInfo.version`, validates top-level `_meta` only when present, and computes `supportsHostOwnedIdleSteering` from the exact four-part proof above. Unknown keys remain ignored. Malformed fields that claim steering fail initialization rather than quietly enabling it.

### Wire operation

Add to `ACPClientConnection`:

```swift
var capabilities: ACPAgentCapabilities?

func offerMidTurnInput(_ prompt: AgentPrompt) async throws -> AgentMidTurnInputResult
```

The method checks the 8,192-byte `prompt.request` bound and the Mac-context plan's separate context bounds, an active non-cancelling prompt, the exact session identity, and `supportsHostOwnedIdleSteering`. Unsupported or already-idle cases return `.promptRequired` without a write. Steering serializes any typed continuity status, the already-captured context JSON/resource links, and the untouched request, preserving each `AgentPromptBlockRole` `_meta` value; it omits only the response-style instruction because that already governs the active session. The no-context wire request is:

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "_session/steering",
  "params": {
    "sessionId": "opaque-session-id",
    "prompt": [{
      "type": "text",
      "text": "also add a regression test",
      "_meta": {
        "ciobanu.org.voiceActivation": {"promptBlockRole": "request"}
      }
    }],
    "_meta": {"steering": {"idleBehavior": "promptRequired"}}
  }
}
```

Parse only an object whose `outcome` is `injected` or `promptRequired` as success; ignore additional bounded keys on `promptRequired`. Treat `startedNewTurn`, `failed`, an unknown outcome, or an invalid object as an unsafe extension result: send `session/cancel` when possible, close the connection, throw `ACPClientError.ambiguousMidTurnInput`, and do not replay that utterance.

### Coordinator FIFO

Add a focused file `Sources/VoiceActivationCore/VoiceActivationCoordinator+AgentInput.swift` and replace `[String]` with stable entries:

```swift
struct PendingAgentInput: Sendable {
    let id: UUID
    let text: String
    let contextCapture: Task<MacContextSnapshot?, Never>?
}

var pendingAgentInputs: [PendingAgentInput] = []
var agentInputRoutingTask: Task<Void, Never>?
var steeringBlockedGeneration: Int?
```

`submitAgentFollowUp(_:)` creates one ID, starts the Mac-context plan's bounded capture immediately, publishes `followUpSubmitted` with disposition `.routing`, and appends before any suspension. `routeNextAgentInput()` owns exactly one head offer. It awaits that already-started capture once, builds one immutable `AgentPrompt`, and reuses it for either steering or the later FIFO prompt; it never recaptures. Its main-run-loop completion verifies run ID, execution generation, input ID, and routing task token:

- `injected`: remove the exact head, publish `followUpDispositionChanged` with `.injected`, and route the next head;
- `promptRequired`: leave the head in place, set `steeringBlockedGeneration`, publish `.queued`, and wait for the current prompt response;
- error: remove only that head, publish `.failed` plus a bounded local notice, block more steering for that generation, and keep later entries FIFO.

When no turn is active, `startNextAgentPrompt()` removes the head, publishes `.prompted`, and starts one normal prompt. It never starts while `agentInputRoutingTask` is unresolved. `cancelAgentRun`, conversation end, profile reset, and `stop()` invalidate the routing token before cancelling the task.

### Presentation

Change lifecycle cases to carry stable input identity:

```swift
case followUpSubmitted(
    runID: UUID,
    inputID: UUID,
    prompt: String,
    disposition: AgentConversationInputDisposition)
case followUpDispositionChanged(
    runID: UUID,
    inputID: UUID,
    disposition: AgentConversationInputDisposition)
```

Change `AgentUserMessagePresentation` to store `disposition`. `AgentRunPresentation` inserts by `inputID` and updates only that row. `AgentRunPanelContent.swift` renders a quiet transport caption and an accessibility value; it never labels an utterance additive, corrective, paused, or replaced.

## Rejected alternatives

- **Classify “also”, “actually”, “pause”, “status”, and “repeat” in Swift:** rejected. It creates a fragile English intent router, loses provider context, and violates the product boundary.
- **Cancel the current prompt for every utterance:** rejected. That is the current defect; it destroys useful in-flight context and can interrupt side effects.
- **Always call `_session/steering` when `_meta.steering.supported` is true:** rejected. Codex ACP 1.8.0's idle race starts a detached turn that the standard client cannot own to completion.
- **Replay steering text after any JSON-RPC error:** rejected. Once the request write is observable, replay can duplicate an action. Only `promptRequired` is a proven non-consumption result.
- **Put multiple spoken inputs into one concatenated prompt:** rejected. It changes message boundaries, weakens FIFO evidence, and asks the app to manufacture semantics.
- **Wait for ACP v2:** rejected. The safe exact-pin Claude path and portable FIFO path work on ACP v1 now; future standardized injection can replace the compatibility adapter later.

## File map

| File | Responsibility |
| --- | --- |
| `Sources/VoiceActivationCore/AgentHarnessRunning.swift` | Public mid-turn result/disposition types and runner protocol method. |
| `Sources/VoiceActivationCore/ACPAgentCapabilities.swift` | Bounded initialize parsing and exact safe-steering compatibility proof. |
| `Sources/VoiceActivationCore/ACPClientConnection.swift` | Stored capability state, public offer method, and typed client error. |
| `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` | Initialize capability capture and `_session/steering` request/result parsing. |
| `Sources/VoiceActivationCore/ACPAgentRunner.swift` | Active-profile offer routing and ambiguous-result connection eviction. |
| `Sources/VoiceActivationCore/VoiceActivationCoordinator.swift` | Stable pending-input/routing identities and lifecycle cases. |
| `Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift` | Turn completion invokes the FIFO only; ordinary follow-up no longer cancels. |
| `Sources/VoiceActivationCore/VoiceActivationCoordinator+AgentInput.swift` | Single-owner steering/FIFO state machine. Keep the execution extension below 700 lines. |
| `Sources/VoiceActivationApp/AgentRunPresentationModels.swift` | Input disposition in timeline snapshots. |
| `Sources/VoiceActivationApp/AgentRunPresentation.swift` | Insert/update identified input rows. |
| `Sources/VoiceActivationApp/AgentRunPanelContent.swift` | Visible and accessibility transport state. |
| `Sources/VoiceActivationApp/AppModel+AgentConversation.swift` | Route the two new lifecycle cases. |
| `Tests/VoiceActivationCoreTests/ACPAgentCapabilitiesTests.swift` | Capability allowlist and malformed/oversized metadata. |
| `Tests/VoiceActivationCoreTests/ACPClientConnectionSteeringTests.swift` | Exact frames, results, races, ambiguity, and bounds. |
| `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift` | No-cancel behavior, FIFO, routing identity, and queue bounds. |
| `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorTests.swift` | Controlled runner offer seam. |
| `Tests/VoiceActivationAppTests/AgentRunPresentationInputDispositionTests.swift` | New focused stable row/disposition suite; avoids growing the existing 662-line presentation test file. |
| `Tests/VoiceActivationAppTests/MenuContentViewTests.swift` | Accessible user-visible transport labels where rendered. |
| `docs/agent-harness.md` | Provider matrix, safe steering proof, fallback, and failure policy. |
| `README.md` | Replace the “follow-up cancels” description with steering/FIFO behavior. |
| `.agents/skills/acp-integration/references/protocol-v1.md` | Record the verified extension boundary and exact-pin allowlist. |
| `.agents/skills/acp-integration/references/claude.md` | Document safe host-owned idle steering in 0.73.0. |
| `.agents/skills/acp-integration/references/codex.md` | Document why 1.8.0 remains on FIFO despite advertising steering. |

## Privacy, bounds, identity, and cancellation

- The existing 8,192-byte UTF-8 request limit applies before retaining or sending an input. Mac context is bounded separately by its plan. The pending FIFO remains capped at 16 entries, each with at most one owned capture task.
- Diagnostics record input ID, run ID, generation, byte count, result kind, queue depth, and duration. They never record the input text or raw result object.
- `ACPRequestID` owns each steering response. `PendingAgentInput.id` owns the UI row and coordinator queue entry. `AgentTurnToken` continues to own permissions. Do not substitute array indices.
- A routing completion must match routing token, run ID, generation, profile ID, and head input ID before mutation.
- Exact conversation end invalidates the routing token, clears the FIFO, then cancels ACP work. **Stop turn** invalidates the routing operation before `session/cancel`; queued inputs remain only when the explicit action means “stop this turn”, not when it means “end conversation”.
- Barge-in cancels narration generation/playback, not the ACP turn. A stale speech callback cannot submit or reroute text.
- `startedNewTurn` is unsafe even if received successfully. Close the connection because otherwise an unowned provider turn could continue mutating the workspace.
- The provider capability allowlist is tied to the initialize response, not merely the Settings preset label or executable path.

## Implementation tasks

### Task 1: Decode a provable steering capability

**Files:**
- Create: `Sources/VoiceActivationCore/ACPAgentCapabilities.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPAgentCapabilitiesTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPClientConnectionTestSupport.swift`

**Interfaces:**
- Produces: `ACPAgentCapabilities.decode(initializeResult:preset:)` and `ACPClientConnection.capabilities`.
- Consumes: existing `ACPJSONValue`, `requiredObject`, `optionalString`, and `boundedText` helpers.

- [ ] **Step 1: Write capability RED tests**

```swift
@Test func decode_WhenPinnedClaudeAdvertisesSteering_EnablesHostOwnedIdleSteering() throws {
    let value = initializeResult(
        name: "@agentclientprotocol/claude-agent-acp",
        version: "0.73.0",
        steering: true)

    let result = try ACPAgentCapabilities.decode(
        initializeResult: value,
        preset: .claude)

    #expect(result.supportsHostOwnedIdleSteering)
}

@Test(arguments: [AgentHarnessPreset.cursor, .codex, .custom])
func decode_WhenPresetIsNotValidatedClaude_RejectsSteering(preset: AgentHarnessPreset) throws {
    let result = try ACPAgentCapabilities.decode(
        initializeResult: initializeResult(
            name: "@agentclientprotocol/claude-agent-acp",
            version: "0.73.0",
            steering: true),
        preset: preset)

    #expect(!result.supportsHostOwnedIdleSteering)
}

@Test func decode_WhenClaudeVersionDrifts_RejectsSteering() throws {
    let result = try ACPAgentCapabilities.decode(
        initializeResult: initializeResult(
            name: "@agentclientprotocol/claude-agent-acp",
            version: "0.74.0",
            steering: true),
        preset: .claude)

    #expect(!result.supportsHostOwnedIdleSteering)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `swift test --filter ACPAgentCapabilitiesTests`

Expected RED: compilation fails because `ACPAgentCapabilities` does not exist.

- [ ] **Step 3: Implement exact bounded decoding**

Implement the type/signature above. Require nonempty `agentInfo.name` and `version`, cap each at `ACPEventDecoder.maximumOpaqueIdentifierBytes`, and treat absent `_meta.steering` as unsupported. Keep future versions disabled until the compatibility baseline changes.

- [ ] **Step 4: Capture it during initialize and confirm GREEN**

Set `capabilities` inside `applyInitializeResult(_:)` before session creation and keep `agentName` display selection unchanged.

Run: `swift test --filter ACPAgentCapabilitiesTests`

Expected GREEN: the exact Claude fixture enables steering; Codex, Cursor, custom, missing metadata, malformed metadata, oversized identity, and version drift fixtures remain disabled or fail closed as asserted.

- [ ] **Step 5: Commit the capability boundary**

```bash
git add Sources/VoiceActivationCore/ACPAgentCapabilities.swift \
  Sources/VoiceActivationCore/ACPClientConnection.swift \
  Sources/VoiceActivationCore/ACPClientConnection+Requests.swift \
  Tests/VoiceActivationCoreTests/ACPAgentCapabilitiesTests.swift \
  Tests/VoiceActivationCoreTests/ACPClientConnectionTestSupport.swift
git commit -m "feat: negotiate safe ACP steering"
```

### Task 2: Implement lifecycle-safe `_session/steering`

**Files:**
- Modify: `Sources/VoiceActivationCore/AgentHarnessRunning.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPClientConnectionSteeringTests.swift`

**Interfaces:**
- Consumes: `ACPAgentCapabilities.supportsHostOwnedIdleSteering` from Task 1.
- Consumes: `AgentPrompt` and its bounded content encoder from the Mac Context Snapshot plan.
- Produces: `ACPClientConnection.offerMidTurnInput(_:) async throws -> AgentMidTurnInputResult`.

- [ ] **Step 1: Write exact frame and result RED tests**

```swift
@Test func offerMidTurnInput_WhenValidatedClaudeTurnIsActive_SendsHostOwnedSteering()
    async throws
{
    let transport = FakeACPTransport()
    let connection = try await establishClaudeSteeringConnection(transport: transport)
    let promptTask = prompt(connection, text: "Inspect", recorder: AgentEventRecorder())
    _ = await transport.nextSentMessage()

    let offer = Task {
        try await connection.offerMidTurnInput(
            AgentPrompt(request: "also add tests", context: nil))
    }
    #expect(await transport.nextSentMessage() == .request(
        id: .integer(4),
        method: "_session/steering",
        params: .object([
            "sessionId": .string("session-1"),
            "prompt": .array([.object([
                "type": .string("text"),
                "text": .string("also add tests"),
            ])]),
            "_meta": .object([
                "steering": .object(["idleBehavior": .string("promptRequired")]),
            ]),
        ])))
    try await transport.feed(.response(
        id: .integer(4),
        result: .object(["outcome": .string("injected")])))
    #expect(try await offer.value == .injected)

    try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
    _ = try await promptTask.value
}
```

Add sibling tests named:

- `offerMidTurnInput_WhenExtensionIsUnsupported_ReturnsPromptRequiredWithoutWrite`
- `offerMidTurnInput_WhenTurnSettled_ReturnsPromptRequiredWithoutWrite`
- `offerMidTurnInput_WhenProviderReturnsPromptRequired_DoesNotConsumeLocallyOwnedText`
- `offerMidTurnInput_WhenProviderReturnsStartedNewTurn_ClosesConnectionWithoutReplay`
- `offerMidTurnInput_WhenPromptExceedsLimit_RejectsBeforeWrite`
- `cancel_WhenSteeringRequestIsPending_SettlesRequestAndPromptExactlyOnce`

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter ACPClientConnectionSteeringTests`

Expected RED: compilation fails because `AgentMidTurnInputResult` and `offerMidTurnInput` do not exist.

- [ ] **Step 3: Implement the typed request**

Add the enum and method signatures from the design. Use existing `sendRequest(method:params:)` so request IDs and writes remain actor-serialized. Encode the already-resolved context and request without the response-style system block: steering is the next opaque user message inside a configured session, not a new configured turn.

For an unsafe returned outcome, execute this order inside the connection actor:

```swift
isPromptCancelling = true
await sendCancelIfPromptWasPublished()
let error = ACPClientError.ambiguousMidTurnInput
await close()
throw error
```

- [ ] **Step 4: Run and confirm GREEN**

Run: `swift test --filter ACPClientConnectionSteeringTests`

Expected GREEN: the test observes exactly one extension request, no `session/cancel` for `injected`/`promptRequired`, and a cancel-plus-close path for unsafe outcomes without a second prompt frame.

- [ ] **Step 5: Commit the wire operation**

```bash
git add Sources/VoiceActivationCore/AgentHarnessRunning.swift \
  Sources/VoiceActivationCore/ACPClientConnection.swift \
  Sources/VoiceActivationCore/ACPClientConnection+Requests.swift \
  Tests/VoiceActivationCoreTests/ACPClientConnectionSteeringTests.swift
git commit -m "feat: offer input to active ACP turns"
```

### Task 3: Route offers through the cached runner

**Files:**
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+Delivery.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerLifecycleTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerTestSupport.swift`

**Interfaces:**
- Consumes: `ACPClientConnection.offerMidTurnInput(_:)` from Task 2.
- Produces: the `AgentHarnessRunning.offerMidTurnInput(profileID:prompt:)` implementation.

- [ ] **Step 1: Write runner identity RED tests**

```swift
@Test func offerMidTurnInput_WhenProfileOwnsActiveTurn_ForwardsToItsConnection()
    async throws
{
    let fixture = try RunnerFixture(validatedClaudeSteering: true)
    let run = fixture.startRun(profileID: fixture.profileID, prompt: "Inspect")
    try await fixture.establishAndStartPrompt()

    let offer = Task {
        try await fixture.runner.offerMidTurnInput(
            profileID: fixture.profileID,
            prompt: AgentPrompt(request: "also add tests", context: nil))
    }
    #expect(await fixture.transport.nextSentMessage().method == "_session/steering")
    try await fixture.transport.feed(steeringResponse(id: 4, outcome: "injected"))
    #expect(try await offer.value == .injected)

    try await fixture.finishPrompt()
    _ = try await run.value
}
```

Add `offerMidTurnInput_WhenProfileDoesNotOwnActiveTurn_ReturnsPromptRequiredWithoutWrite` and `offerMidTurnInput_WhenUnsafeOutcomeClosesRecord_DiscardsOnlyMatchingCachedSession`.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter ACPAgentRunnerLifecycleTests`

Expected RED: `ACPAgentRunner` does not conform to the extended protocol.

- [ ] **Step 3: Implement active-record routing**

Guard `activeTurn.profileID == profileID`, `!activeTurn.isCancelling`, and a current connection. On ambiguous input failure, remove and dispose only the matching `recordID`; do not reset unrelated profile sessions.

- [ ] **Step 4: Run and confirm GREEN**

Run: `swift test --filter ACPAgentRunnerLifecycleTests`

Expected GREEN: the matching connection receives one offer; idle/mismatched cases perform no write; ambiguous delivery evicts only one record.

- [ ] **Step 5: Commit runner routing**

```bash
git add Sources/VoiceActivationCore/ACPAgentRunner.swift \
  Sources/VoiceActivationCore/ACPAgentRunner+Delivery.swift \
  Tests/VoiceActivationCoreTests/ACPAgentRunnerLifecycleTests.swift \
  Tests/VoiceActivationCoreTests/ACPAgentRunnerTestSupport.swift
git commit -m "feat: route mid-turn input through ACP runner"
```

### Task 4: Replace cancel-on-speech with steering-or-FIFO

**Files:**
- Modify: `Sources/VoiceActivationCore/VoiceActivationCoordinator.swift`
- Modify: `Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift`
- Create: `Sources/VoiceActivationCore/VoiceActivationCoordinator+AgentInput.swift`
- Modify: `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift`

**Interfaces:**
- Consumes: `AgentHarnessRunning.offerMidTurnInput(profileID:prompt:)` and the shared `PendingAgentInput` capture ownership from the Mac Context Snapshot plan.
- Produces: stable input lifecycle events and the single-owner routing state machine.

- [ ] **Step 1: Replace the obsolete behavior test with RED scenarios**

```swift
@MainActor
@Test func agentConversation_WhenActiveTurnAcceptsInput_SteersWithoutCancellation()
    async throws
{
    let runner = ControlledAgentRunner(midTurnResults: [.injected])
    let fixture = try Fixture(
        profiles: [try makeAgentProfile()],
        agentRunner: runner)
    fixture.coordinator.setPassiveEnabled(true)
    fixture.speech.emit("agent inspect this", isFinal: true)
    await waitUntil { await runner.recordedInvocations().count == 1 }

    fixture.speech.emit("also add tests", isFinal: true)
    await waitUntil { await runner.recordedMidTurnOffers().count == 1 }

    #expect(await runner.cancelCount == 0)
    #expect(await runner.recordedInvocations().count == 1)
    #expect(await runner.recordedMidTurnOffers().map(\.prompt.request) == ["also add tests"])
}
```

Add exact tests:

- `agentConversation_WhenSteeringRequiresPrompt_QueuesWithoutCancellingThenStartsAfterCompletion`
- `agentConversation_WhenThreeOffersArrive_RoutesAndPromptsInFIFOOrder`
- `agentConversation_WhenSteeringFails_DoesNotReplayAmbiguousInput`
- `agentConversation_WhenConversationEnds_IgnoresLateRoutingCompletion`
- `agentConversation_WhenStopTurnIsClicked_PreservesQueuedInputsForNextTurn`
- `agentConversation_WhenSeventeenthInputArrives_RejectsItBeforeRetention`
- `agentConversation_WhenUserBargesIn_StopsNarrationButDoesNotCancelAgentTurn`

- [ ] **Step 2: Run the coordinator suite and confirm RED**

Run: `swift test --filter VoiceActivationCoordinatorConversationTests`

Expected RED: the first test observes `cancelCount == 1`, proving the current unconditional cancellation path.

- [ ] **Step 3: Implement the queue state machine**

Move follow-up routing into `VoiceActivationCoordinator+AgentInput.swift`. Append before suspension, route one head, use `MainRunLoopScheduler.perform`, and check all identities before applying the result. `finishAgentExecution` clears `steeringBlockedGeneration` before starting the next normal prompt.

- [ ] **Step 4: Run and confirm GREEN**

Run: `swift test --filter VoiceActivationCoordinatorConversationTests`

Expected GREEN: ordinary mid-turn input never increments `cancelCount`; safe offers inject; unsupported/raced offers become normal prompts in FIFO order; stale and ambiguous results do not replay.

- [ ] **Step 5: Run cancellation regressions**

Run: `swift test --filter VoiceActivationCoordinatorCancellationTests`

Expected GREEN: explicit stop, full conversation end, launch cancellation, pending permission cancellation, and stale-generation tests retain their existing terminal states.

- [ ] **Step 6: Commit coordinator semantics**

```bash
git add Sources/VoiceActivationCore/VoiceActivationCoordinator.swift \
  Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift \
  Sources/VoiceActivationCore/VoiceActivationCoordinator+AgentInput.swift \
  Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorTests.swift \
  Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift
git commit -m "feat: preserve agent work during voice follow-ups"
```

### Task 5: Show transport truth without inventing intent

**Files:**
- Modify: `Sources/VoiceActivationApp/AgentRunPresentationModels.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPresentation.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPanelContent.swift`
- Modify: `Sources/VoiceActivationApp/AppModel+AgentConversation.swift`
- Create: `Tests/VoiceActivationAppTests/AgentRunPresentationInputDispositionTests.swift`
- Modify: `Tests/VoiceActivationAppTests/MenuContentViewTests.swift`

**Interfaces:**
- Consumes: identified lifecycle events from Task 4.
- Produces: one timeline row whose caption follows the exact input ID.

- [ ] **Step 1: Write presentation RED tests**

```swift
@MainActor
@Test func followUpDisposition_WhenInputMatches_UpdatesOnlyThatTimelineRow() throws {
    let presentation = AgentRunPresentation(startsElapsedTimer: false)
    let runID = UUID()
    let firstID = UUID()
    let secondID = UUID()
    presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Start")
    presentation.submitFollowUp(
        runID: runID,
        inputID: firstID,
        prompt: "also add tests",
        disposition: .routing)
    presentation.submitFollowUp(
        runID: runID,
        inputID: secondID,
        prompt: "and run them",
        disposition: .routing)

    presentation.updateFollowUp(
        runID: runID,
        inputID: firstID,
        disposition: .injected)

    #expect(presentation.snapshot?.userMessage(id: firstID)?.disposition == .injected)
    #expect(presentation.snapshot?.userMessage(id: secondID)?.disposition == .routing)
}
```

Add `followUpDisposition_WhenRunOrInputIsStale_DoesNotMutateSnapshot` and a view assertion that `.queued` exposes accessibility value `Queued for next turn`.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter AgentRunPresentationInputDispositionTests`

Expected RED: `submitFollowUp` has no input identity/disposition parameters.

- [ ] **Step 3: Implement stable row updates and labels**

Map dispositions exactly:

```swift
extension AgentConversationInputDisposition {
    var presentationLabel: String {
        switch self {
        case .routing: "Routing…"
        case .injected: "Added to current turn"
        case .queued: "Queued for next turn"
        case .prompted: "Started as next turn"
        case .failed: "Delivery failed — say it again"
        }
    }
}
```

Use this for visible caption and accessibility value. Do not add a semantic icon such as “replace” or “append”.

- [ ] **Step 4: Run and confirm GREEN**

Run: `swift test --filter 'AgentRunPresentationInputDispositionTests|MenuContentViewTests'`

Expected GREEN: identified rows update independently, stale IDs are ignored, and every state has visible/accessibility text.

- [ ] **Step 5: Commit presentation truth**

```bash
git add Sources/VoiceActivationApp/AgentRunPresentationModels.swift \
  Sources/VoiceActivationApp/AgentRunPresentation.swift \
  Sources/VoiceActivationApp/AgentRunPanelContent.swift \
  Sources/VoiceActivationApp/AppModel+AgentConversation.swift \
  Tests/VoiceActivationAppTests/AgentRunPresentationInputDispositionTests.swift \
  Tests/VoiceActivationAppTests/MenuContentViewTests.swift
git commit -m "feat: show voice input delivery state"
```

### Task 6: Document and verify the provider boundary

**Files:**
- Modify: `README.md`
- Modify: `docs/agent-harness.md`
- Modify: `.agents/skills/acp-integration/references/protocol-v1.md`
- Modify: `.agents/skills/acp-integration/references/claude.md`
- Modify: `.agents/skills/acp-integration/references/codex.md`

**Interfaces:**
- Consumes: shipped behavior from Tasks 1–5.
- Produces: a dated, reproducible compatibility statement.

- [ ] **Step 1: Update the documented contract**

State that ordinary language remains agent input; exact Claude 0.73.0 steering is enabled only with the initialize proof; Cursor and Codex 1.8.0 use FIFO; `promptRequired` is the only automatic normal-prompt fallback after a steering request; ambiguous outcomes are never replayed.

- [ ] **Step 2: Run focused protocol and conversation suites**

```bash
swift test --filter ACPAgentCapabilitiesTests
swift test --filter ACPClientConnectionSteeringTests
swift test --filter ACPAgentRunnerLifecycleTests
swift test --filter VoiceActivationCoordinatorConversationTests
swift test --filter AgentRunPresentationInputDispositionTests
```

Expected: all selected suites pass; no test starts a real provider, microphone, audio output, network request, or paid prompt.

- [ ] **Step 3: Run proportional repository verification**

```bash
swift test
swift test --sanitize=thread
CONFIGURATION=debug make app
make check
git diff --check
```

Expected: full suite and Thread Sanitizer pass; the app bundle builds; SPDX, guidance, Swift size, and public DocC checks pass; no whitespace errors remain.

- [ ] **Step 4: Run safe compatibility evidence**

Run: `.agents/skills/acp-integration/scripts/probe-local-clients.sh all`

Expected: initialize-only handshakes succeed for the project pins. The probe creates no session and sends no prompt, so it cannot prove model steering. The exact tagged-source fixture tests are the steering evidence.

- [ ] **Step 5: Exercise the bundled manual matrix**

With test prompts containing no sensitive data, verify: Claude injected input; Cursor and Codex queued input; three rapid utterances retain order; barge-in stops speech but not ACP work; exact `stop` ends the conversation; queue-full copy is visible; the foreground app remains active; muted audio, VoiceOver labels, Reduce Motion, and a menu-open/event-tracking interval preserve state.

Record each exercised row and explicitly list any row not run. Do not claim perceived speech quality from automated tests.

- [ ] **Step 6: Commit documentation and verified behavior**

```bash
git add README.md docs/agent-harness.md \
  .agents/skills/acp-integration/references/protocol-v1.md \
  .agents/skills/acp-integration/references/claude.md \
  .agents/skills/acp-integration/references/codex.md
git commit -m "docs: define conversational input routing"
```

## Dependencies on the other feature plans

- **Mac context snapshot** (`2026-09-05-mac-context-snapshot.md`): implement its typed `AgentPrompt` and immediate `PendingAgentInput.contextCapture` ownership first. Steering/FIFO must await and reuse that single snapshot without inspecting, merging, or recapturing its meaning.
- **Spoken confirmations and results** (`2026-09-05-spoken-confirmations-and-results.md`): permission selection remains an explicit typed control before ordinary-input routing; no general phrase classifier moves into this plan.
- **Voice-first response channel** (`2026-09-05-voice-first-response-channel.md`): barge-in cancels spoken projection before the opaque utterance is routed; input disposition captions are not narration content.
- **Durable continuity** (`2026-09-05-durable-continuity.md`): persisted opaque session identity may allow later normal prompts to continue provider context, but pending or ambiguous local input is never persisted/replayed automatically.
- **Background task continuity** (`2026-09-05-background-task-continuity.md`): session-scoped background events may arrive while a steering decision is pending. They use session identity and must not settle, reorder, or semantically classify the input FIFO.

## Explicit non-goals

- No local distinction between additive, corrective, status, pause, resume, repeat, or replacement language.
- No local LLM, embeddings, grammar engine, locale-specific intent catalog, or command router for ordinary conversation.
- No ACP adapter upgrade and no reliance on npm `latest`.
- No support for Codex 1.8.0's detached `startedNewTurn` steering path.
- No automatic retry after ambiguous request failure, provider disconnect, `startedNewTurn`, or unknown extension outcome.
- No persistence of utterance text or pending input across app restart.
- No change to direct-command profiles.
- No claim that Cursor or every custom ACP agent can steer; their proven path is bounded FIFO `session/prompt`.

## Completion evidence

The feature is complete only when a failing regression first proves ordinary speech cancels the active turn, the same test passes with zero cancellation, exact Claude fixtures prove `injected` and `promptRequired`, unsupported providers prove no extension write, unsafe outcomes prove no replay, FIFO/stale-ID/queue-bound tests pass, the full and sanitizer suites pass, the bundle is exercised, and the docs name the exact provider pins and limits. Anything less is a demo with very good posture.
