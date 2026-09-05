<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Background Task Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep provider-owned work observable and controllable after a foreground prompt ends or the conversation panel is minimized, without pretending that a killed ACP process can resume an in-flight turn.

**Architecture:** Voice Activation keeps the ACP process and session event stream alive while the app process is alive. Standard ACP prompts remain the portable baseline. For the exact Claude Agent ACP 0.73.0 pin, the app negotiates the typed AIR `asyncTasks` extension, projects its task lifecycle into a bounded session-presentation registry, and exposes an explicit typed stop action. Background-task state is orthogonal to the conversation/prompt phase, so a completed turn returns to listening while its session remains observable. On app relaunch, durable continuity restores provider context only; work that was active at process exit is shown as interrupted until a new live event proves otherwise.

**Tech Stack:** Swift 6.2, Swift Testing, ACP v1 JSON-RPC over stdio, Claude Agent ACP 0.73.0 AIR extension, `VoiceActivationCore`, SwiftUI/AppKit, Apple Speech.

**Spec:** This document is the approved feature contract and implementation path. There is no inferred provider behavior outside the pinned, cited source.

## Global constraints

- Voice Activation is a thin native voice/runtime bridge. It may capture bounded native context, transport typed ACP content/events, speak agent-authored output, and retain opaque provider/session/task identifiers.
- The ACP agent owns semantic interpretation, planning, tool use, memory content/logic, and task execution.
- Do not create local natural-language intent parsing, local task planning, or a second agent inside the app.
- App-level semantics are explicit transport controls only; ordinary language remains agent input.
- Put framework-independent capability, identity, event, bound, and cancellation policy in `VoiceActivationCore`; keep SwiftUI/AppKit projection in `VoiceActivationApp`.
- A retired app run, ACP process, session, prompt, or provider task cannot mutate current state. Invalidate identity before cancellation and settle resources once.
- Never log transcripts, prompts, agent content, task descriptions/summaries, raw ACP payloads, output paths, credentials, or authorization data.
- Keep all strings, task collections, event queues, and diagnostics bounded. Preserve provider event order and backpressure.
- Preserve direct `Foundation.Process` execution, macOS 15, Swift tools 6.2, public Core DocC, and the 700-line Swift file limit.

---

## Feature contract

### Concrete voice scenarios

1. Alex asks, “watch the build and tell me when it finishes.” The agent decides whether to spawn background work. If Claude Agent ACP 0.73.0 emits `async_task_spawned`, the panel moves to **Working in background**, keeps the adapter process alive, and shows the provider-authored name and progress. The app does not infer “watch” as a task command.
2. Alex minimizes the non-activating agent panel and works in another Mac app. The Voice Activation process, cached ACP connection, and session event consumer remain alive. A later `async_task_progress`, `async_task_state_update`, or agent message reaches the same session presentation without stealing focus.
3. While a Claude task runs between prompt turns, Alex invokes Voice Activation and asks, “how is it going?” The sentence is ordinary agent input routed by the conversational-control plan. The agent interprets it using its session/task context; the app does not synthesize a status answer from native task fields.
4. Alex presses **Stop background task** for a task whose event says `canStop == true`. The app sends `_session/async_task/stop` with the exact opaque session and task IDs. A `stopped: true` response acknowledges transport; the visible terminal state still comes from the provider's ordered `async_task_state_update`.
5. Alex says, “stop the watcher.” The utterance is sent to the agent as ordinary language. It is not matched to the native stop action. Only the visible button is an explicit app-level transport control.
6. A standard ACP provider, Cursor, Codex ACP 1.8.0, a custom agent, or an incompatible Claude version runs a long normal prompt. The prompt continues while the app remains running and its panel is minimized. No async-task UI or custom method is claimed. The next ordinary prompt starts only after the terminal prompt response.
7. Voice Activation quits, crashes, or is updated while a standard prompt or Claude task is live. Startup reconciliation changes its persisted `AgentInterruptedWorkMarker` from `.active` to `.interruptedByProcessExit`. A resumable ACP session may restore provider context, but the app does not say the prior prompt/task resumed and never replays it automatically.
8. After relaunch, the provider emits a fresh typed event with the same session/task ID during a newly established live connection. Only that live event may create a new current task lifecycle. The historical marker remains an honest record of the process boundary.
9. An unknown extension update or a thirty-third concurrent task arrives. The decoder bounds it, records only a content-free diagnostic category, and safely ignores or evicts presentation history by the defined rule. It never crashes, grows without limit, or appears as agent-authored speech.
10. A permission request arrives after a normal prompt has already completed. Because there is no live prompt-scoped permission token, the app responds with cancellation when the wire contract permits and does not surface a stale approval panel.

### Observable promises

- **Live app continuity:** proven for a live normal `session/prompt`, and for negotiated Claude async-task events before the Voice Activation/adapter process exits.
- **Panel continuity:** hiding/minimizing the panel does not cancel work. **Stop turn** cancels only the live prompt. **End conversation** ends capture/current prompt UI but retains sessions with active provider tasks in the registry. Profile reset and app termination close the connection; explicit task stop targets exactly one provider task.
- **Restart recovery:** restores opaque session context through capability-gated `session/load` or `session/resume`; it does not restore a standard in-flight prompt or assert that Claude async work survived adapter death.
- **Voice output:** only agent-authored message content is eligible for narration. Task names, descriptions, progress summaries, paths, and native status labels are never automatically spoken.

## Current-state evidence

- `Sources/VoiceActivationCore/ACPClientConnection.swift` owns a connection process, request table, one `activePromptRequestID`, and one `activeEventDelivery`. It has no session-scoped delivery after the prompt response.
- `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift` → `completePendingRequest(id:with:)` marks `promptResponseWasReceived` and stops prompt delivery. A provider notification arriving between turns therefore has no durable event sink.
- The same file sends `clientCapabilities: {}` in `initialize`. Claude's AIR extension will not activate until the client advertises the exact capability.
- `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` → `applyInitializeResult(_:)` retains display/authentication data but not top-level `_meta`, agent version, or session capability details. The app cannot currently prove that an extension or `session/resume` was negotiated.
- `Sources/VoiceActivationCore/ACPEventDecoder.swift` maps standard `session/update` values into `AgentRunEvent` and converts unknown updates into bounded `.unknown` events. There are no typed async-task cases.
- `Sources/VoiceActivationCore/ACPAgentRunner.swift` and `ACPAgentRunner+Connection.swift` cache at most four provider sessions/processes by profile. This already supplies the correct live-process ownership boundary; it does not persist across app exit.
- `Sources/VoiceActivationCore/ACPAgentRunner.swift` owns one global `activeTurn`; `ACPAgentRunner+Delivery.swift` → `forward(event:turnToken:profileID:recordID:)` rejects every event without that active turn. There is no persistent per-session observer after a prompt completes.
- `Sources/VoiceActivationCore/AgentHarnessRunning.swift` exposes prompt, permission, turn cancellation, reset, and shutdown operations, but no session event stream or provider-task stop operation.
- `Sources/VoiceActivationApp/AgentRunPresentation.swift` accepts events only for its current nonterminal run. It contains no provider-task collection or session registry and cannot retain live session state after the prompt completes.
- `Sources/VoiceActivationApp/AppModel+AgentConversation.swift` binds coordinator callbacks to one in-memory presentation. `AppModel+Lifecycle.swift` → `shutdown()` stops the coordinator/audio and clears presentation, correctly proving that quitting kills the current transport.
- `Sources/VoiceActivationApp/AgentRunPanelView.swift`, `AgentRunPanelContent.swift`, and `AgentRunPanelPresenter.swift` allow a live panel to minimize; close/delete semantics are presentation-oriented and no background-task action exists.
- `Tests/VoiceActivationCoreTests/ACPClientConnectionPromptTests.swift`, `ACPAgentRunnerLifecycleTests.swift`, `ACPEventDecoderTests.swift`, `Tests/VoiceActivationAppTests/AgentRunPresentationTests.swift`, and `AppModelConversationTests.swift` are the focused owners to extend.

## Protocol and exact-provider evidence

Stable ACP v1's [Prompt Turn](https://agentclientprotocol.com/protocol/v1/prompt-turn) contract keeps a `session/prompt` request open through streamed `session/update` notifications and ends it with one response; `session/cancel` is the standard cancellation surface. Stable v1 has no detachable prompt handle or cross-process in-flight prompt recovery.

ACP [Session Setup](https://agentclientprotocol.com/protocol/v1/session-setup) defines `session/load` and `session/resume` behind advertised capabilities. Load replays session history; resume restores provider context without replay. Neither operation states that an unfinished prompt or external provider task is revived. The restart contract in this plan is deliberately narrower.

The exact provider pins were inspected from cached npm tarballs and official tagged source on 2026-09-05, without authenticating, starting a model session, reading secrets, or making a paid call:

- [Claude Agent ACP v0.73.0 `acp-agent.ts`](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/acp-agent.ts) advertises top-level `_meta.jetbrains.air` support and `_meta.steering.supported`, registers `_session/async_task/stop`, and keeps its session update consumer alive between turns.
- [Claude Agent ACP v0.73.0 `air-extension.ts`](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/air-extension.ts) requires the client to advertise `clientCapabilities._meta.jetbrains.air = {"version":1,"capabilities":["asyncTasks"]}` before async-task behavior is negotiated.
- [Claude Agent ACP v0.73.0 `async-tasks.ts`](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/async-tasks.ts) defines `async_task_spawned`, `async_task_progress`, and `async_task_state_update`, including task ID, display fields, progress usage, terminal states, optional output path/tool-call ID, and whether the task can stop.
- [Codex ACP v1.8.0 `CodexAcpServer.ts`](https://github.com/agentclientprotocol/codex-acp/blob/v1.8.0/src/CodexAcpServer.ts) does not expose this AIR async-task contract. [Cursor's ACP documentation](https://cursor.com/docs/cli/acp) documents the stable surface, not the AIR extension. Both use the portable normal-prompt path.

An initialize-only probe against the project pins—Cursor 2026.01.23, Codex ACP 1.8.0, and Claude Agent ACP 0.73.0—confirmed all three advertise `loadSession`; Codex and Claude also advertise session capabilities, while Cursor's summary exposed load/prompt capabilities. This proves negotiation shape only. It does not prove model-task survival and must not be described as such.

## Chosen architecture

### 1. Negotiate an exact capability, never infer one

Extend the capability aggregate introduced by the conversational-control plan; do not declare a second type with the same name. Session restoration stays in the durable-continuity plan's separate `ACPSessionRestorationCapabilities`:

```swift
/// Capabilities accepted after intersecting client support, provider metadata,
/// exact adapter identity, and the configured preset pin.
struct ACPAgentCapabilities: Equatable, Sendable {
    let agentName: String
    let agentVersion: String
    let supportsHostOwnedIdleSteering: Bool
    let supportsAIRAsyncTasks: Bool
}
```

`supportsAIRAsyncTasks` is true only when all conditions hold:

1. the profile preset is Claude;
2. initialized `agentInfo.name == "@agentclientprotocol/claude-agent-acp"`;
3. initialized `agentInfo.version == "0.73.0"`;
4. the client advertised AIR version 1 and `asyncTasks`;
5. the initialize response advertises AIR version 1 and `asyncTasks`.

An unknown provider, version, capability, missing field, wrong type, or future extension version produces `false`. Never switch on an executable path or display name alone.

Use the Voice-First Response plan's shared `ACPClientCapabilities` builder. Add the AIR fragment by deep merge; never construct or overwrite the whole `_meta` object in this feature. Keep the existing `Self.clientName`, `Self.clientTitle`, and `Self.clientVersion` values:

```swift
"clientCapabilities": try ACPClientCapabilities.compose([
    .voiceResponseChannelsV1,
    .jetBrainsAIRAsyncTasksV1,
]),
"clientInfo": .object([
    "name": .string(Self.clientName),
    "title": .string(Self.clientTitle),
    "version": .string(Self.clientVersion),
]),
```

The resulting `_meta` contains both `ciobanu.org.voiceActivation.responseChannels` and `jetbrains.air`. A collision at an already-populated non-object key is a local programming error covered by tests, not last-writer-wins behavior.

### 2. Decode provider events into bounded Core values

Add `Sources/VoiceActivationCore/AgentBackgroundTask.swift`:

```swift
/// An opaque provider-owned task identifier scoped to one ACP session.
public struct AgentBackgroundTaskID: Hashable, Sendable {
    public let rawValue: String
}

public enum AgentBackgroundTaskState: String, Equatable, Sendable {
    case running
    case paused
    case completed
    case failed
    case stopped
}

public struct AgentBackgroundTaskUsage: Equatable, Sendable {
    public let totalTokens: Int?
    public let toolUses: Int?
    public let durationMilliseconds: Int?
}

public enum AgentBackgroundTaskUpdate: Equatable, Sendable {
    case spawned(
        id: AgentBackgroundTaskID,
        name: String,
        taskType: String,
        description: String,
        showInTranscript: Bool,
        canStop: Bool,
        outputFilePath: String?,
        toolCallID: String?
    )
    case progress(
        id: AgentBackgroundTaskID,
        description: String?,
        summary: String?,
        lastToolName: String?,
        usage: AgentBackgroundTaskUsage?,
        outputFilePath: String?,
        toolCallID: String?
    )
    case stateChanged(
        id: AgentBackgroundTaskID,
        state: AgentBackgroundTaskState,
        summary: String?,
        outputFilePath: String?,
        toolCallID: String?
    )
}
```

Add `case backgroundTask(AgentBackgroundTaskUpdate)` to `AgentRunEvent`. Exact decode limits are: session IDs use the existing 4 KiB ACP opaque-identity bound; task/tool-call IDs are 256 UTF-8 bytes each; name, task type, and last tool are 256 bytes; description and summary are 4 KiB; output path is 4 KiB; nonnegative usage values clamp to `Int.max`; at most 32 task presentations are retained per session. Invalid required IDs/state or oversized required values produce `.unknown(discriminator: "async_task_update", summary: "Invalid ACP async task update.")`; optional oversized values become `nil`. Diagnostics may name only the update category and rejection reason.

Do not validate, normalize, open, or execute `outputFilePath`; it is untrusted provider-authored display content. A later explicit open-file feature needs its own authorization and containment contract.

### 3. Give every cached session a persistent event sink

Add to `AgentHarnessRunning.swift`:

```swift
/// A provider event correlated to its owning profile and ACP session.
public struct AgentSessionEventEnvelope: Equatable, Sendable {
    public let profileID: UUID
    public let sessionID: String
    public let streamEvent: AgentRunStreamEvent
}

public protocol AgentHarnessRunning: Sendable {
    func setSessionEventHandler(
        _ handler: (@Sendable (AgentSessionEventEnvelope) async -> Void)?
    ) async

    func stopBackgroundTask(
        profileID: UUID,
        sessionID: String,
        taskID: AgentBackgroundTaskID
    ) async throws -> Bool
}
```

Keep existing protocol requirements unchanged. Add deterministic no-op/default test behavior only to named fakes, not as a production protocol extension that hides missing conformance.

`AgentRunStreamEvent` comes from Durable Continuity and makes origin non-optional. Persistent between-turn delivery emits only `.live`; restoration emits token-qualified `.restored` through its isolated delivery path. `ACPClientConnection` gains one persistent bounded `AgentRunEventDelivery` for session-scoped updates. The routing invariant is:

- while `activePromptRequestID` owns a prompt, decoded updates go to that prompt delivery;
- the prompt response transition retires prompt delivery and selects the already-installed session delivery in the same actor-isolated operation;
- between turns, only negotiated `backgroundTask` and agent message updates go to session delivery as `.live`;
- a permission emitted while the originating prompt remains open retains the normal live turn-token path; after prompt settlement, a permission has no owner, is answered with cancellation, and is never forwarded, retained, or narrated;
- on shutdown/reset, invalidate process generation, finish both deliveries once, then terminate transport.

The same wire notification is delivered once. There is no temporal gap and no fan-out to both sinks. Keep the existing ordered/bounded `AgentRunEventDelivery` behavior; do not introduce an unbounded `AsyncStream`.

### 4. Correlate session events without reopening stale runs

`ACPAgentRunner` owns one handler and emits `AgentSessionEventEnvelope` only after verifying connection generation, profile ID, session ID, and source token/generation. App code installs the handler once during startup and routes it through the existing mode-aware main-run-loop scheduler.

Add `AgentSessionPresentationRegistry` in App, keyed by `(profileID, sessionID)` and capped at the runner's four cached sessions. It retains one `AgentRunPresentation` plus its run/process generation for every session that has a live prompt or active background task. Selecting a new conversation changes only the visible key; it does not replace another session's retained presentation. An envelope is accepted only when key, run generation, process generation, and source are current. Profile reset, retired process generation, or deletion after all tasks are terminal rejects later callbacks.

Add an app-facing presentation type in `Sources/VoiceActivationApp/AgentBackgroundTaskPresentation.swift`:

```swift
struct AgentBackgroundTaskPresentation: Identifiable, Equatable {
    let id: AgentBackgroundTaskID
    var name: String
    var taskType: String
    var description: String
    var summary: String?
    var state: AgentBackgroundTaskState
    var canStop: Bool
    var usage: AgentBackgroundTaskUsage?
}
```

The per-session collection is ordered by first spawn. Duplicate spawn for the same session/task ID updates the existing row. Progress before spawn creates a bounded generic **Background task** row. On the thirty-third ID, evict the oldest terminal row; if all 32 are active, ignore the new row and record a content-free overflow diagnostic.

Do not add `AgentRunPhase.background`. Prompt/conversation phase and task lifecycle are orthogonal: after a prompt completes, the conversation returns to `.listening` while `hasActiveBackgroundTasks` remains true and `acceptsSessionEvents` follows the retained session identity. A background update never reactivates a prompt timer, capture, working pulse, or permission UI. The menu/panel can show **Working in background** from task state without lying about conversation phase.

The runner marks cached connections with active AIR task IDs as non-evictable. If all four cache entries are pinned, starting a fifth session fails before process launch with a bounded local availability notice; it never evicts running work. Terminal task updates unpin the connection. The menu lists every retained session with active work; choosing one shows its presentation without activating another Mac app.

Minimize/hide never cancels. **Stop turn** cancels only a current prompt. **End conversation** ends capture/current prompt UI but keeps registry entries with active tasks. Close/delete is disabled while any task is active: the user may stop each stoppable task, while a non-stoppable task remains observable until a provider terminal event, reset, or app exit. Once all tasks are terminal, close/delete removes that registry entry and a new run may replace it. This explicit lifecycle prevents work from becoming invisible or unstoppable.

Add a session-audio entry point separate from prompt lifecycle handling. `handleSessionEvent(_:)` accepts only `.live` agent-message/spoken-ready events for a current registry key, narrates them once through the Voice-First router policy, and never calls `setWorking(true)`. It explicitly no-ops for restoration lifecycle, restored content, async-task metadata, permission/control events, and native notices. Session terminal/task updates therefore cannot leave the prompt activity sound running indefinitely.

### 5. Stop is a typed transport action

For a negotiated task with `canStop == true`, send:

```json
{
  "jsonrpc": "2.0",
  "id": 41,
  "method": "_session/async_task/stop",
  "params": {"sessionId": "opaque-session", "asyncTaskId": "opaque-task"}
}
```

Parse only `{ "stopped": true }` or `{ "stopped": false }`. A `true` response changes the button to **Stop requested** but does not fabricate `.stopped`; wait for the typed state update. A false response restores the button and shows **Couldn’t stop task**. Request failure, connection replacement, stale session/task identity, or unknown response clears the pending action without retry.

The panel button calls `AppModel.stopBackgroundTask(runID:taskID:)`. Spoken language never calls it directly. The agent may choose to invoke its own tools after receiving an ordinary voice prompt; that remains agent-owned behavior.

### 6. Make restart recovery explicitly interrupted

Integrate the durable-continuity plan's exact shared values:

```swift
public struct AgentSessionBookmark: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let sessionID: String
    public let providerFingerprint: String
    public let lastAccessOrdinal: UInt64
}

public struct AgentInterruptedWorkMarker: Codable, Equatable, Sendable {
    public let key: AgentInterruptedWorkKey
    public let turnID: String?
    public let providerTaskID: String?
    public let state: AgentInterruptedWorkState
}
```

Allocate a fresh local `occurrenceID` for every prompt and accepted task spawn, write its `.active` marker before the prompt becomes externally writable or task lifecycle is presented, and clear only its exact `AgentInterruptedWorkKey` on the matching terminal prompt/state event. Provider task IDs are not assumed unique over time. Startup reconciliation atomically changes every remaining `.active` marker to `.interruptedByProcessExit` before starting providers.

Only these opaque IDs, fingerprint, ordinal, and enum state persist. Claude task names, descriptions, summaries, usage, paths, prompt text, and transcript do not. Plain ACP turns never resume after process death. Claude async work is not durable after adapter death. If `session/resume` succeeds, the session may receive new prompts with restored provider context; a new live event can create a new current task lifecycle but does not rewrite the historical interruption claim.

## ACP wire and data flow

```text
voice utterance
  -> ordinary session/prompt or capability-gated steering
  -> ACP agent chooses whether background work exists
  -> Claude 0.73.0 emits typed async_task_* session/update
  -> ACPClientConnection validates + decodes + orders
  -> active prompt delivery OR persistent session delivery (never both)
  -> ACPAgentRunner verifies process/profile/session identity
  -> AppModel hops through mode-aware main-run-loop bridge
  -> AgentRunPresentation bounds rows and rejects stale identity
  -> panel shows provider-authored state; only agent messages reach narration
```

Portable providers follow the same path only through the terminal `session/prompt` response. The app remains alive and can keep waiting; it does not manufacture a task handle.

## Rejected alternatives

- **Parse “watch,” “keep going,” “status,” or “stop” locally.** Rejected: language meaning belongs to the ACP agent and locale/phrase matching becomes a second brittle agent.
- **Treat panel close/minimize as process ownership.** Rejected: presentation visibility must not silently cancel provider work. Explicit controls own cancellation.
- **Keep the existing prompt-only event callback.** Rejected: it drops legitimate between-turn extension events and agent results.
- **Broadcast every update to prompt and session observers.** Rejected: duplicates state and narration, and violates exactly-once ordering.
- **Enable AIR for any provider that mentions `asyncTasks`.** Rejected: underscore methods are nonstandard. Exact name, version, pin, preset, and bidirectional capability intersection are required.
- **Use Codex steering's detached turn as a background task.** Rejected: it supplies neither a standard prompt response owner nor AIR task lifecycle/stop semantics.
- **Assume `session/load` or `session/resume` revives work.** Rejected: the ACP v1 contract restores session context, not an in-flight request or killed adapter-owned task.
- **Persist task prose or replay interrupted prompts.** Rejected: it expands sensitive storage and can duplicate side effects after an ambiguous process boundary.
- **Speak native progress summaries.** Rejected: AIR task fields are status metadata, not necessarily agent-authored narration. The voice-reading plan consumes only agent messages.

## Exact file map

| File | Change |
| --- | --- |
| `Sources/VoiceActivationCore/AgentBackgroundTask.swift` | New bounded public task ID, state, usage, and update values with DocC. |
| `Sources/VoiceActivationCore/AgentRunEvent.swift` | Add the typed background-task event. |
| `Sources/VoiceActivationCore/AgentHarnessRunning.swift` | Add session envelope/handler and typed stop operation. |
| `Sources/VoiceActivationCore/ACPAgentCapabilities.swift` | Extend the shared exact-pin capability contract with AIR negotiation; do not duplicate durable restoration capabilities. |
| `Sources/VoiceActivationCore/ACPClientCapabilities.swift` | Extend the shared deep-merging initialize builder with AIR; preserve response-channel metadata. |
| `Sources/VoiceActivationCore/ACPEventDecoder.swift` | Decode the three exact AIR update shapes with limits. |
| `Sources/VoiceActivationCore/ACPClientConnection.swift` | Own persistent session event delivery and generation identity. |
| `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` | Advertise/parse capabilities and implement stop request. |
| `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift` | Select prompt/session delivery while decoding ordered received frames. |
| `Sources/VoiceActivationCore/ACPClientConnection+Delivery.swift` | Route updates exactly once and finish both delivery lifecycles. |
| `Sources/VoiceActivationCore/ACPAgentRunner.swift` | Store the session event handler. |
| `Sources/VoiceActivationCore/ACPAgentRunner+Delivery.swift` | Route verified prompt events and delegate session events without duplication. |
| `Sources/VoiceActivationCore/ACPAgentRunner+Connection.swift` | Bind persistent delivery to connection records and invalidate it during disposal. |
| `Sources/VoiceActivationCore/ACPAgentRunner+BackgroundTasks.swift` | New focused owner for session envelopes and typed task stop. |
| `Sources/VoiceActivationCore/AgentSessionContinuity.swift` | Consume durable-continuity bookmark/interruption types and reconciliation. |
| `Sources/VoiceActivationApp/AgentBackgroundTaskPresentation.swift` | New bounded UI projection. |
| `Sources/VoiceActivationApp/AgentSessionPresentationRegistry.swift` | Retain and select at most four identity-gated live session presentations. |
| `Sources/VoiceActivationApp/AgentRunPresentation.swift` | Match session identity and accept task events without changing prompt phase. |
| `Sources/VoiceActivationApp/AppModel+AgentConversation.swift` | Install session callback and map it via main-run-loop bridge. |
| `Sources/VoiceActivationApp/AppModel+Lifecycle.swift` | Detach session delivery before runner shutdown. |
| `Sources/VoiceActivationApp/AgentRunPanelContent.swift` | Render task rows/status and explicit stop button without activating app. |
| `Sources/VoiceActivationApp/AgentRunPanelPresenter.swift` | Preserve hide/show/background semantics and route stop action. |
| `Sources/VoiceActivationApp/MenuContentView.swift` | List retained sessions with active work and select their panel presentation. |
| `Tests/VoiceActivationCoreTests/*` | Capability, fixture, decode, routing, lifecycle, bounds, and recovery tests named below. |
| `Tests/VoiceActivationAppTests/*` | Presentation, panel, narration exclusion, and stale-callback tests named below. |
| `README.md`, `docs/agent-harness.md`, `docs/privacy-and-security.md` | Document provider matrix, live/restart contract, stop semantics, retention, and verification. |

If an edited Swift owner would exceed 700 physical lines, extract the named responsibility into the new file shown above; do not compress unrelated code or broad-format the repository.

---

## Phased TDD implementation

Follow each RED/GREEN checkpoint in order. A later task assumes the focused suites from every earlier task are green.

### Task 1: Prove AIR negotiation and decode its exact fixture shapes

**Files:**

- Create: `Sources/VoiceActivationCore/AgentBackgroundTask.swift`
- Modify: `Sources/VoiceActivationCore/AgentRunEvent.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentCapabilities.swift`
- Modify after Durable Continuity Task 1 creates: `Sources/VoiceActivationCore/ACPClientCapabilities.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift`
- Modify: `Sources/VoiceActivationCore/ACPEventDecoder.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPAsyncTaskFixtures.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentCapabilitiesTests.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPClientConnectionInitializationTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPEventDecoderTests.swift`

- [ ] **Step 1: Add failing initialize capability tests**

Add these exact tests:

- `ACPAgentCapabilitiesTests.claude073_WhenBothSidesAdvertiseAIRAsyncTasks_EnablesAsyncTasks`
- `ACPAgentCapabilitiesTests.claude073_WhenClientOrAgentCapabilityIsMissing_DisablesAsyncTasks`
- `ACPAgentCapabilitiesTests.nonAllowlistedProvider_WhenAIRIsAdvertised_DisablesAsyncTasks`
- `ACPAgentCapabilitiesTests.airMetadata_WhenMalformedOrOversized_FailsInitialization`
- `ACPClientConnectionInitializationTests.initialize_AdvertisesAIRVersionOneAsyncTasks`
- `ACPClientConnectionInitializationTests.initialize_WithVoiceAndAIR_PreservesBothMetadataNamespaces`

Use the checked-in fixture, not a hand-edited approximation inside each test. Assert the full nested client capability object so a spelling/casing drift fails loudly, including simultaneous `ciobanu.org.voiceActivation.responseChannels` and `jetbrains.air` contributions.

Run:

```bash
swift test --filter ACPAgentCapabilitiesTests
swift test --filter ACPClientConnectionInitializationTests.initialize_AdvertisesAIRVersionOneAsyncTasks
```

Expected RED: compilation fails because `supportsAIRAsyncTasks` is absent, followed by an initialize-params mismatch once the property compiles.

- [ ] **Step 2: Add failing exact decoder-contract tests**

Add these exact tests:

- `ACPEventDecoderTests.asyncTaskSpawnedFixture_DecodesEveryPinnedField`
- `ACPEventDecoderTests.asyncTaskProgressFixture_DecodesUsageAndOptionalFields`
- `ACPEventDecoderTests.asyncTaskStateFixture_DecodesEveryTerminalState`
- `ACPEventDecoderTests.asyncTaskUpdate_WhenRequiredIdentityIsInvalid_ReturnsBoundedUnknown`
- `ACPEventDecoderTests.asyncTaskUpdate_WhenOptionalContentExceedsLimit_DropsOptionalContent`
- `ACPEventDecoderTests.unknownExtensionUpdate_ReturnsBoundedUnknownWithoutRawContent`

The fixture must contain one line per exact 0.73.0 update type. Assert values using public cases, for example:

```swift
#expect(event == .backgroundTask(.stateChanged(
    id: AgentBackgroundTaskID(rawValue: "task-7"),
    state: .completed,
    summary: "Build passed",
    outputFilePath: nil,
    toolCallID: "tool-9"
)))
```

Run: `swift test --filter ACPEventDecoderTests.asyncTask`

Expected RED: the decoder produces `.unknown` because no typed event exists.

- [ ] **Step 3: Implement the smallest bounded capability and event types**

Add useful DocC to every public Core symbol. Parse initialize metadata into the existing aggregate, intersect exact provider/preset/version with both advertised sides, and decode only the documented shapes. Reuse existing ACP JSON accessors and event delivery; do not add `Any`, dictionary payloads, or raw JSON retention.

Run:

```bash
swift test --filter ACPAgentCapabilitiesTests
swift test --filter ACPClientConnectionInitializationTests
swift test --filter ACPEventDecoderTests
```

Expected GREEN: exact Claude fixtures enable/decode; unsupported, malformed, oversized, and unknown fixtures remain disabled or bounded.

- [ ] **Step 4: Preserve the provider evidence with the implementation**

Add a comment next to the underscore capability and method constants linking the exact Claude 0.73.0 tagged files named above. The comment documents compatibility provenance; it must not claim standard ACP support.

### Task 2: Keep one ordered session event path alive between prompts

**Files:**

- Modify: `Sources/VoiceActivationCore/ACPClientConnection.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Delivery.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPClientConnectionPromptTests.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPClientConnectionBackgroundTaskTests.swift`

- [ ] **Step 1: Add a failing between-turn delivery test**

Add `ACPClientConnectionBackgroundTaskTests.updateAfterPromptResponse_IsDeliveredOnceToSessionObserver`:

1. initialize the scripted transport with the negotiated Claude fixture;
2. install a session observer;
3. start and complete one prompt;
4. inject `async_task_spawned` after the response;
5. assert exactly one session event and zero extra prompt events.

Run: `swift test --filter ACPClientConnectionBackgroundTaskTests.updateAfterPromptResponse_IsDeliveredOnceToSessionObserver`

Expected RED: no event arrives because `activeEventDelivery` stopped with the prompt.

- [ ] **Step 2: Pin the response/update race and stale-delivery rules**

Add these exact tests:

- `ACPClientConnectionBackgroundTaskTests.updateRacingPromptResponse_IsDeliveredToExactlyOneObserver`
- `ACPClientConnectionBackgroundTaskTests.backgroundUpdateBeforePromptResponse_StaysOnPromptObserver`
- `ACPClientConnectionBackgroundTaskTests.unnegotiatedAsyncUpdate_DoesNotReachSessionObserver`
- `ACPClientConnectionBackgroundTaskTests.permissionRequestBetweenTurns_IsCancelledWithoutObserverDelivery`
- `ACPClientConnectionBackgroundTaskTests.shutdown_InvalidatesSessionObserverBeforeTransportTermination`
- `ACPClientConnectionBackgroundTaskTests.sessionObserver_WhenBackpressured_PreservesBoundAndOrder`

Drive the race with the existing controlled transport and explicit continuations, never sleeps. The test should release response parsing and notification parsing in both orders.

Run: `swift test --filter ACPClientConnectionBackgroundTaskTests`

Expected RED: the observer API and session delivery do not exist.

- [ ] **Step 3: Implement actor-isolated event handoff**

Add a connection method with this exact ownership surface:

```swift
func setSessionEventHandler(
    _ handler: (@Sendable (AgentRunEvent) async -> Void)?
) async
```

Create persistent delivery only after successful initialization/session creation. In the actor-isolated prompt response transition owned by `ACPClientConnection+Receive.swift`, finish/retire the prompt delivery and select the already-installed session delivery before processing the next received frame. Retain the Voice-First plan's connection/session-owned response router across that transition so a between-turn result uses the same deterministic channel parser. Reuse the current delivery capacity and overflow behavior. Filter between-turn events to negotiated background-task and agent-message cases; cancel post-settlement permission requests.

Run:

```bash
swift test --filter ACPClientConnectionBackgroundTaskTests
swift test --filter ACPClientConnectionPromptTests
swift test --filter ACPClientConnectionLifecycleTests
```

Expected GREEN: every controlled ordering delivers once, cancellation settles, and existing prompt ordering remains unchanged.

- [ ] **Step 4: Verify malformed/late frames cannot retain the connection**

Add `ACPClientConnectionBackgroundTaskTests.lateUpdateFromRetiredProcessGeneration_IsIgnored` using a retired scripted transport. Assert its delivery and handler are released after shutdown; do not rely only on absence of UI change.

Run: `swift test --filter ACPClientConnectionBackgroundTaskTests.lateUpdateFromRetiredProcessGeneration_IsIgnored`

Expected GREEN: the stale callback is rejected and the weak lifecycle probe deallocates.

### Task 3: Forward session events through the runner and app lifecycle

**Files:**

- Modify: `Sources/VoiceActivationCore/AgentHarnessRunning.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+Connection.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+Delivery.swift`
- Create: `Sources/VoiceActivationCore/ACPAgentRunner+BackgroundTasks.swift`
- Modify: `Sources/VoiceActivationApp/AppModel.swift`
- Modify: `Sources/VoiceActivationApp/AppModel+AgentConversation.swift`
- Modify: `Sources/VoiceActivationApp/AppModel+Lifecycle.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerLifecycleTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerCachingTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AppModelConversationTests.swift`

- [ ] **Step 1: Add failing runner identity tests**

Add these exact tests:

- `ACPAgentRunnerLifecycleTests.backgroundUpdate_EmitsProfileAndSessionEnvelope`
- `ACPAgentRunnerLifecycleTests.backgroundUpdateFromRetiredConnection_IsIgnored`
- `ACPAgentRunnerLifecycleTests.backgroundUpdate_IsQualifiedAsLiveNotRestored`
- `ACPAgentRunnerLifecycleTests.resetSession_InvalidatesObserverBeforeCancellingConnection`
- `ACPAgentRunnerLifecycleTests.shutdown_FinishesSessionDeliveryExactlyOnce`
- `ACPAgentRunnerCachingTests.evictedSession_CannotEmitBackgroundUpdate`
- `ACPAgentRunnerCachingTests.activeTaskSession_IsPinnedAgainstLRUEviction`
- `ACPAgentRunnerCachingTests.fifthSession_WhenAllFourArePinned_FailsBeforeProcessLaunch`
- `ACPAgentRunnerCachingTests.terminalTask_UnpinsSessionForOrdinaryLRUEviction`

Use distinct profile IDs, session IDs, and connection generations. Assert the complete envelope, not just the task event.

Run:

```bash
swift test --filter ACPAgentRunnerLifecycleTests.backgroundUpdate
swift test --filter ACPAgentRunnerCachingTests.evictedSession_CannotEmitBackgroundUpdate
```

Expected RED: `setSessionEventHandler` and `AgentSessionEventEnvelope` do not exist.

- [ ] **Step 2: Implement the runner contract and explicit identity gate**

Add the protocol signatures from the architecture section to the production runner and every named test double. The connection callback captures an immutable connection generation and session identity, then calls an actor-isolated runner method:

```swift
private func receiveSessionEvent(
    _ streamEvent: AgentRunStreamEvent,
    profileID: UUID,
    sessionID: String,
    connectionGeneration: UInt64
)
```

That method compares all identities against the cached session before constructing an envelope. Persistent session delivery may pass `.live` only; a token-qualified `.restored` value can enter only through Durable Continuity's restoration path. Reset, eviction, failed initialization, and shutdown increment/invalidate generation before closing the process.

Run:

```bash
swift test --filter ACPAgentRunnerLifecycleTests
swift test --filter ACPAgentRunnerCachingTests
swift test --filter VoiceActivationCoordinatorTests
```

Expected GREEN: live envelopes are correlated; retired processes and sessions are silent; all existing fakes compile with explicit behavior.

- [ ] **Step 3: Add failing main-run-loop and app shutdown tests**

Add these exact tests:

- `AppModelConversationTests.backgroundUpdate_HopsThroughModeAwareMainRunLoopBeforePresentationMutation`
- `AppModelConversationTests.backgroundUpdateForDifferentSession_DoesNotMutatePresentation`
- `AppModelConversationTests.shutdown_DetachesSessionHandlerBeforeRunnerShutdown`
- `AppModelConversationTests.hiddenPanel_BackgroundUpdateStillMutatesMatchingPresentation`
- `AppModelConversationTests.newVisibleConversation_DoesNotDiscardOtherActiveSessionPresentation`
- `AppModelConversationTests.backgroundLiveMessage_NarratesOnceWithoutStartingPromptWorkingPulse`
- `AppModelConversationTests.restoredMessage_NeverEntersBackgroundNarration`

The first test uses the existing scheduler spy/mode-aware bridge and asserts mutation occurs only after the scheduled closure runs. The shutdown test captures a callback before shutdown and invokes it afterward to prove stale rejection.

Run: `swift test --filter AppModelConversationTests.backgroundUpdate`

Expected RED: the app never installs or consumes a session event handler.

- [ ] **Step 4: Bind once for app lifetime, detach before shutdown**

Install the handler from the existing app composition/startup path, not per panel render. Hop through the established main-run-loop scheduler before touching the `@MainActor` session registry. Verify app run generation, presentation run ID, profile ID, session ID, and source again at mutation time. Background audio handles only newly admitted `.live` agent messages/typed narration; it never handles restored events/task metadata and never calls the prompt `setWorking(true)` path. During shutdown, invalidate app generation and detach the handler before coordinator/runner shutdown.

Run:

```bash
swift test --filter AppModelConversationTests
swift test --filter AgentConversationAudioLifecycleTests
```

Expected GREEN: hidden-panel updates arrive without focus changes; post-shutdown callbacks cannot mutate or narrate.

### Task 4: Project bounded task state and provide a typed stop control

**Files:**

- Create: `Sources/VoiceActivationApp/AgentBackgroundTaskPresentation.swift`
- Create: `Sources/VoiceActivationApp/AgentSessionPresentationRegistry.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPresentation.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPanelContent.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPanelPresenter.swift`
- Modify: `Sources/VoiceActivationApp/MenuContentView.swift`
- Modify: `Sources/VoiceActivationApp/AppModel+AgentConversation.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+BackgroundTasks.swift`
- Create: `Tests/VoiceActivationAppTests/AgentRunPresentationBackgroundTaskTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AgentRunPanelPresenterTests.swift`
- Modify: `Tests/VoiceActivationAppTests/MenuContentViewTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AppModelConversationTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AgentConversationAudioPresenterTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPClientConnectionBackgroundTaskTests.swift`

- [ ] **Step 1: Add failing presentation reducer tests**

Add these exact tests:

- `AgentRunPresentationBackgroundTaskTests.spawn_AfterPromptCompletion_PreservesListeningAndSetsActiveTaskFlag`
- `AgentRunPresentationBackgroundTaskTests.progressBeforeSpawn_CreatesGenericBoundedRow`
- `AgentRunPresentationBackgroundTaskTests.duplicateSpawn_UpdatesWithoutReordering`
- `AgentRunPresentationBackgroundTaskTests.thirtyThirdTask_EvictsOldestTerminalRow`
- `AgentRunPresentationBackgroundTaskTests.thirtyThirdActiveTask_IsIgnoredWithContentFreeDiagnostic`
- `AgentRunPresentationBackgroundTaskTests.updateForRetiredRunProfileSessionOrSource_IsIgnored`
- `AgentRunPresentationBackgroundTaskTests.terminalState_DoesNotEndSessionEventAcceptance`
- `AgentRunPresentationBackgroundTaskTests.endConversation_RetainsActiveTaskRegistryEntry`
- `AgentRunPresentationBackgroundTaskTests.closeDelete_DisabledUntilAllTasksTerminal`
- `AgentRunPresentationBackgroundTaskTests.fifthSession_WhenFourHaveActiveTasks_IsRefusedWithoutEviction`

Use an explicit reducer entry point:

```swift
mutating func applySessionEvent(
    _ envelope: AgentSessionEventEnvelope,
    appRunGeneration: UInt64
) -> AgentSessionEventEffect
```

`AgentSessionEventEffect` may request panel refresh and `.live` agent-message narration; it must never return narration for `.restored` or `.backgroundTask`, and background narration must not start the prompt working pulse.

Run: `swift test --filter AgentRunPresentationBackgroundTaskTests`

Expected RED: no task collection, active-task flag, session registry, or session reducer exists.

- [ ] **Step 2: Implement the bounded reducer before building UI**

Implement first-spawn ordering, duplicate updates, progress-before-spawn, terminal eviction, all-active overflow, pending-stop state, registry retention, and `hasActiveBackgroundTasks` without adding a prompt phase. Keep native captions fixed and localized: **Working in background**, **Background task**, **Stop background task**, **Stop requested**, **Couldn’t stop task**, and **Interrupted when Voice Activation exited**.

Run: `swift test --filter AgentRunPresentationBackgroundTaskTests`

Expected GREEN: every transition is deterministic and identity-gated without AppKit.

- [ ] **Step 3: Add failing stop-wire tests**

Add these exact tests:

- `ACPClientConnectionBackgroundTaskTests.stopTask_WhenNegotiated_WritesExactAIRMethodAndParams`
- `ACPClientConnectionBackgroundTaskTests.stopTask_WhenUnnegotiated_PerformsNoWrite`
- `ACPClientConnectionBackgroundTaskTests.stopTaskResponseTrue_DoesNotFabricateTerminalEvent`
- `ACPClientConnectionBackgroundTaskTests.stopTaskResponseMalformed_ThrowsWithoutRetry`
- `ACPAgentRunnerLifecycleTests.stopTaskForStaleSession_PerformsNoWrite`

Assert exact method `_session/async_task/stop` and exact keys `sessionId` and `asyncTaskId`; assert that description/name are never sent.

Run:

```bash
swift test --filter ACPClientConnectionBackgroundTaskTests.stopTask
swift test --filter ACPAgentRunnerLifecycleTests.stopTaskForStaleSession
```

Expected RED: no stop request API exists.

- [ ] **Step 4: Implement one-shot typed stop ownership**

Validate ID byte bounds and negotiated capability before allocating a request ID. Allow one in-flight stop per session/task; repeated clicks remain disabled until response/failure. Verify the same connection generation before applying the response. Return the provider Boolean and wait for provider state update to change task state.

Run:

```bash
swift test --filter ACPClientConnectionBackgroundTaskTests
swift test --filter ACPAgentRunnerLifecycleTests
```

Expected GREEN: the exact extension write occurs only on the matching negotiated connection and never invents task completion.

- [ ] **Step 5: Add the non-activating panel behavior and accessibility tests**

Add these exact tests:

- `AgentRunPanelPresenterTests.minimizeDuringBackground_DoesNotCancelOrActivate`
- `AgentRunPanelPresenterTests.backgroundCompletion_PreservesForegroundApplicationFocus`
- `MenuContentViewTests.activeBackgroundSessions_AreListedAndSelectable`
- `AppModelConversationTests.stopBackgroundTask_RoutesVisibleTaskIdentityOnce`
- `AppModelConversationTests.stopBackgroundTask_WhenResponseIsFalse_RestoresActionAndShowsFailure`
- `AgentConversationAudioPresenterTests.backgroundTaskMetadata_IsNeverNarrated`
- `AgentConversationAudioPresenterTests.backgroundAgentMessage_IsNarratedOnce`

Each task row needs a combined accessibility label with name/state and a separate **Stop background task** button only when stoppable. Use semantic colors plus text/icon state; never color alone. Preserve current reduce-motion and non-activating panel policy.

Run:

```bash
swift test --filter AgentRunPanelPresenterTests
swift test --filter AppModelConversationTests.stopBackgroundTask
swift test --filter AgentConversationAudioPresenterTests.background
```

Expected RED before UI wiring, then GREEN after the panel renders reducer state and the button calls the typed app method. AppKit window assertions remain in the isolated UI lane if required by the existing suite.

### Task 5: Integrate durable session identity without claiming task resurrection

**Dependency:** Implement the durable-continuity plan's `AgentSessionContinuity.swift`, `ACPSessionRestorationCapabilities`, bookmark store, and startup reconciliation first. This task consumes them; it does not invent a second persistence layer.

**Files:**

- Modify after durable-continuity Task 1 creates: `Sources/VoiceActivationCore/AgentSessionContinuity.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+Connection.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+BackgroundTasks.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPresentation.swift`
- Create: `Tests/VoiceActivationCoreTests/AgentBackgroundTaskContinuityTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerLifecycleTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AgentRunPresentationBackgroundTaskTests.swift`

- [ ] **Step 1: Add failing interrupted-work persistence tests**

Add these exact tests:

- `AgentBackgroundTaskContinuityTests.promptMarker_IsActiveBeforePromptCanWrite`
- `AgentBackgroundTaskContinuityTests.taskSpawnMarker_StoresOnlyOpaqueIdentityAndActiveState`
- `AgentBackgroundTaskContinuityTests.startupReconciliation_AtomicallyMarksActiveWorkInterruptedByProcessExit`
- `AgentBackgroundTaskContinuityTests.terminalEvent_ClearsOnlyMatchingOccurrenceKey`
- `AgentBackgroundTaskContinuityTests.reusedProviderTaskID_CreatesDistinctOccurrences`
- `AgentBackgroundTaskContinuityTests.persistedRepresentation_ExcludesPromptTaskProseUsageAndPath`

The privacy test serializes a bookmark/marker and asserts the representation contains the opaque IDs and enum state but none of the fixture's distinctive prompt, description, summary, tool name, usage, or path strings.

Run: `swift test --filter AgentBackgroundTaskContinuityTests`

Expected RED: prompt/task lifecycle is not wired to markers, or the shared types are absent until the durable plan lands.

- [ ] **Step 2: Make the process boundary transactional**

Before the first externally writable prompt frame, persist:

```swift
AgentInterruptedWorkMarker(
    key: AgentInterruptedWorkKey(
        profileID: profileID,
        sessionID: sessionID,
        occurrenceID: UUID()),
    turnID: opaqueTurnID,
    providerTaskID: nil,
    state: .active
)
```

`opaqueTurnID` is included only if the provider exposes one; do not reach into `AgentTurnToken`'s private UUID. On accepted task spawn, allocate another local occurrence key and persist a marker with `turnID: nil` and `providerTaskID: taskID.rawValue`. Clear only that exact key after the matching prompt response or typed terminal task state. On startup, reconcile every `.active` marker to `.interruptedByProcessExit` in the bookmark store's existing atomic replace operation before launching an adapter.

Run:

```bash
swift test --filter AgentBackgroundTaskContinuityTests
swift test --filter ACPAgentRunnerLifecycleTests
```

Expected GREEN: a simulated process exit leaves a durable interruption marker, while clean terminal paths leave none.

- [ ] **Step 3: Prove load/resume restores context, not work state**

Add these exact tests:

- `ACPAgentRunnerLifecycleTests.resumeAfterInterruptedPrompt_DoesNotReplayPromptOrCreateActiveTurn`
- `ACPAgentRunnerLifecycleTests.resumeAfterInterruptedAsyncTask_DoesNotMarkTaskRunning`
- `ACPAgentRunnerLifecycleTests.resumeFailure_StartsFreshSessionAndRetainsInterruptionNotice`
- `AgentRunPresentationBackgroundTaskTests.restoredInterruptedTask_ShowsInterruptedWithoutActiveControls`
- `AgentRunPresentationBackgroundTaskTests.freshLiveTaskEventAfterResume_CreatesNewCurrentOccurrence`

The scripted provider must count wire methods: after either load or resume, assert zero automatic replayed `session/prompt`, zero `_session/async_task/stop`, and no native running task until a new `.live` update is injected. Load replay is source-qualified, visible-only history and cannot create a current running task.

Run:

```bash
swift test --filter ACPAgentRunnerLifecycleTests.resumeAfterInterrupted
swift test --filter AgentRunPresentationBackgroundTaskTests.restoredInterrupted
```

Expected RED before integration; GREEN proves honest recovery semantics. Never loosen this assertion based on provider marketing or an observed lucky process.

- [ ] **Step 4: Record the restart boundary in user-facing copy**

Use **Interrupted when Voice Activation exited** for historical active markers. If session resume succeeds, the normal durable-continuity notice may say the conversation context was restored; it must not say the turn or background task resumed. Do not include provider task prose in notifications.

### Task 6: Document and verify the complete provider matrix

**Files:**

- Modify: `README.md`
- Modify: `docs/agent-harness.md`
- Create: `docs/privacy-and-security.md`
- Modify: `.agents/skills/acp-integration/references/protocol-v1.md`
- Modify: `.agents/skills/acp-integration/references/claude.md`
- Modify: `.agents/skills/acp-integration/references/codex.md`
- Modify: `.agents/skills/acp-integration/references/cursor.md`
- Modify: `.agents/skills/testing-and-debugging/references/verification-matrix.md`

- [ ] **Step 1: Update product and privacy documentation**

Document this exact matrix:

| Provider path | While app runs | Between turns | After app process exits |
| --- | --- | --- | --- |
| Stable ACP v1 prompt | Prompt remains owned until response/cancel | No standard detached task stream | Mark interrupted; optionally restore session context; never replay |
| Claude Agent ACP 0.73.0 with negotiated AIR | Typed spawn/progress/state plus explicit typed stop | Persistent session consumer accepts negotiated typed events | Adapter-owned task is interrupted; no survival claim |
| Codex ACP 1.8.0 | Standard prompt only | No AIR task lifecycle | Mark interrupted; session context only if restoration succeeds |
| Cursor 2026.01.23 | Standard prompt only | No proven AIR task lifecycle | Mark interrupted; session context only if restoration succeeds |
| Unknown/custom provider | Negotiated stable capabilities only | Unknown extensions bounded and ignored | No work-resumption claim |

Also document: panel minimize is not cancellation; close/delete behavior; exact stop button semantics; 32-row UI bound; stored opaque bookmark/marker fields; excluded transcript/task prose; session-cache bound of four; and the difference between agent messages and unspeakable task metadata.

- [ ] **Step 2: Update owned compatibility baselines**

Add dated, source-linked rows for Claude 0.73.0 AIR and its nonstandard status. Record that Codex/Cursor do not enter this path. Keep the evidence tied to exact pins, and instruct future pin upgrades to rerun fixture tests and the safe initialize-only probe before changing the allowlist.

- [ ] **Step 3: Run focused Core verification**

```bash
swift test --filter ACPAgentCapabilitiesTests
swift test --filter ACPEventDecoderTests
swift test --filter ACPClientConnectionBackgroundTaskTests
swift test --filter ACPClientConnectionPromptTests
swift test --filter ACPClientConnectionPermissionTests
swift test --filter ACPAgentRunnerLifecycleTests
swift test --filter ACPAgentRunnerCachingTests
swift test --filter AgentBackgroundTaskContinuityTests
swift test --filter VoiceActivationCoordinatorConversationTests
```

Expected: all focused Core tests pass with no live provider, credentials, network, sound, or paid model calls.

- [ ] **Step 4: Run focused app verification**

```bash
swift test --filter AgentRunPresentationBackgroundTaskTests
swift test --filter AgentRunPanelPresenterTests
swift test --filter AppModelConversationTests
swift test --filter AppModelLifecycleTests
swift test --filter AgentConversationAudioLifecycleTests
swift test --filter AgentConversationAudioPresenterTests
```

Expected: all deterministic presentation/audio tests pass; task metadata never enters the narration spy; hidden/minimized panels do not cancel or activate.

- [ ] **Step 5: Run proportional repository gates**

```bash
swift test
CONFIGURATION=debug make app
make check
git diff --check
```

Then run the testing guide's sanitizer lane for concurrency/lifetime changes and its isolated AppKit lane for real-panel focus behavior. Expected: zero failures, zero sanitizer reports, a signed debug bundle, SPDX/guidance checks clean, and no whitespace errors.

- [ ] **Step 6: Exercise the bundle with a deterministic local ACP fixture**

Use the bundled debug app and a local scripted ACP executable that performs only initialize/session JSON-RPC and emits the checked-in Claude fixture events; it must not authenticate or contact a model. Verify:

1. start a profile and display one spawned task;
2. minimize the panel while progress and completion arrive;
3. confirm the prior foreground app retains focus;
4. confirm agent-message content is narrated once and task metadata is silent;
5. click the stop button and inspect the scripted transport's exact method/params;
6. quit during an active marker, relaunch, and confirm **Interrupted when Voice Activation exited** with no prompt replay;
7. run an unnegotiated fixture and confirm no async-task controls appear.

Record the bundle path, fixture identity, exercised rows, and any environment-bound lane not run. Do not claim real-provider end-to-end behavior from this deterministic adapter. A separate optional smoke check may use an already authenticated provider, but is not required and must never print credentials or prompt content.

## Dependencies on the other feature plans

- **Mac context snapshot** (`2026-09-05-mac-context-snapshot.md`): the typed context envelope may accompany a normal prompt; it must not be retained in task metadata, markers, or background diagnostics.
- **Conversational control semantics** (`2026-09-05-conversational-control-semantics.md`): voice follow-ups use its capability-gated steering/FIFO route. Session events never settle, reorder, or reinterpret that input queue. Implement its shared `ACPAgentCapabilities` first.
- **Spoken confirmations and results** (`2026-09-05-spoken-confirmations-and-results.md`): explicit permission/control confirmation stays separate from AIR status. Task-stop transport acknowledgements are not fabricated agent results.
- **Voice-first response channel** (`2026-09-05-voice-first-response-channel.md`): only agent-authored message events are eligible for background narration; it owns interruption, replay, and channel choice.
- **Durable continuity** (`2026-09-05-durable-continuity.md`): it owns `AgentSessionContinuity.swift`, `AgentSessionBookmark`, `AgentInterruptedWorkMarker`, `AgentInterruptedWorkState`, `ACPSessionRestorationCapabilities`, atomic storage, and startup reconciliation. This plan supplies prompt/task marker lifecycle facts and consumes the restored identity.

Implementation order: Durable Continuity's generic client-capability composer, Conversational Control's agent-capability parser, and Voice-First's response contribution land first; Task 1 may then add AIR to the shared aggregates and prove the combined initialize object. Tasks 2–4 add live behavior, and Task 5 integrates persistence. If plans execute in parallel, keep types in their owning files and rebase before writing overlapping declarations.

## Explicit non-goals

- No local parser for “watch,” “continue,” “status,” “pause,” “resume,” or “stop” language.
- No local planner, scheduler, task executor, polling engine, shell command, or second agent.
- No upgrade of Claude, Codex, Cursor, or the ACP protocol dependency.
- No generic support claim for underscore-prefixed AIR methods.
- No detached standard ACP prompt, synthesized task handle, or prompt multiplexing beyond what a negotiated provider owns.
- No assertion that `session/load` or `session/resume` restores a standard in-flight prompt.
- No assertion that a Claude async task survives Voice Activation or adapter process exit.
- No automatic replay/retry of an interrupted prompt, task action, or ambiguous stop request.
- No persistence of transcripts, prompts, task names/descriptions/summaries, output paths, token usage, or provider payloads.
- No native opening/execution of provider `outputFilePath`.
- No narration of native status, task metadata, progress counters, or interruption markers.
- No background launch daemon, login-item worker, or hidden replacement ACP process.
- No change to direct-command profiles.

## Completion evidence

This feature is complete only when exact-pin fixtures prove bidirectional AIR negotiation and all three update shapes; the prompt/session response race delivers each event once; stale process/profile/session/task callbacks are rejected; the 32-task bound and privacy exclusions hold; stop emits the exact typed method without fabricating terminal state; standard providers preserve only live normal prompts; process-exit tests mark work interrupted with zero replay; focused, full, sanitizer, bundle, and isolated AppKit rows are recorded. The ACP agent does the work. Voice Activation keeps the wire honest. 💅
