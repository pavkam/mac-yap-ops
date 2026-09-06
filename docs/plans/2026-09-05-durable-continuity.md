<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Durable Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reopen a profile's compatible ACP conversation after Voice Activation relaunches, reconstruct visible history without replaying it aloud, and report interrupted work honestly instead of silently starting over.

**Architecture:** Persist a bounded `AgentSessionBookmark` containing only profile identity, an opaque provider session identifier, and a fingerprint of session-defining configuration. On the next turn, initialize the selected ACP adapter, negotiate its runtime capabilities, and choose `session/load`, `session/resume`, or `session/new` with a deterministic policy. Historical `session/update` notifications are source-tagged so they can rebuild the panel without triggering speech, sounds, permissions, or live-task state. A separate bounded marker records only opaque identifiers for work that was active when the process ended; startup reconciles it to `interruptedByProcessExit`. Voice Activation never reconstructs agent memory itself.

**Tech Stack:** Swift 6.2, macOS 15, SwiftPM, Foundation `UserDefaults`, CryptoKit SHA-256, ACP v1 newline-delimited JSON-RPC, Swift Testing.

**Spec:** This document is the owning feature specification; the capability matrix, restoration policy, voice scenarios, and failure behavior below are normative.

## Global Constraints

- Voice Activation is a thin native voice/runtime bridge. It may capture bounded native context, transport typed ACP content/events, speak agent-authored output, and retain opaque provider/session/task identifiers.
- The ACP agent owns semantic interpretation, planning, tool use, memory content/logic, and task execution.
- Do not add local intent parsing, local memory summarization, app-owned task planning, or a second agent inside Voice Activation.
- Persist identifiers and compatibility metadata only. Never persist transcripts, prompts, agent messages, reasoning, tool arguments/results, permission details, native Mac context, audio, credentials, or provider authorization.
- Treat all provider capability fields as runtime-negotiated. Missing means unsupported; a preset name must never imply a capability.
- A restored session preserves agent-owned context, not execution. A normal ACP turn that was active when the app or adapter process ended is interrupted and is never claimed to be running after relaunch.
- Keep protocol policy and persistence interfaces in `VoiceActivationCore`; keep `UserDefaults` and app launch reconciliation in `VoiceActivationApp`.
- A retired session, restoration attempt, run, turn, or task cannot mutate current state. Cancellation invalidates identity before closing transport or settling replay.
- Keep bookmarks, work markers, replay events, diagnostics, and UI history bounded. Every Swift file stays below 700 physical lines and every new public Core symbol has useful DocC.

---

## Feature contract

### Observable voice scenarios

1. Alex finishes a conversation, quits Voice Activation, relaunches it, and says, “Computer, what was the next step?” With the same profile and compatible provider configuration, the app loads the bookmarked ACP session before sending the new utterance. The provider replays history into the panel, no historical text is spoken, and the new agent answer is spoken normally.
2. The same sequence runs against a provider that advertises `sessionCapabilities.resume` but not `loadSession`. The agent continues with provider-owned context, the panel displays a concise “Previous history is available to the agent but this provider cannot replay it” notice, and only the new turn appears locally.
3. The provider advertises neither capability. The app starts a fresh session, removes the unusable bookmark, and presents one concise client-status notice: “This provider cannot reopen the previous conversation. I started a new one.” A typed continuity-status block lets the ACP agent include that limitation in its spoken answer when relevant. The utterance is sent exactly once; Voice Activation does not speak locally authored prose.
4. The saved profile now points at a different executable, arguments, working directory, preset, or system prompt. The fingerprint does not match, so the old session identifier is never sent to that process. A fresh session starts and replaces the bookmark.
5. Voice Activation or its ACP adapter exits during a normal turn. On relaunch, the visible restoration state says the previous turn was interrupted. The app may reopen the provider's session, but it never labels that turn as active or completed and never automatically repeats the prompt.
6. An ACP provider task ID created by the separate Background Task Continuity feature was active at shutdown. The app retains the opaque ID and marks the local execution interrupted. It delegates any later status lookup or reconnection to that feature's explicitly negotiated provider-task capability; ACP session recovery alone does not prove the task survived.
7. `session/load` returns “session not found,” corrupt data is found in the local bookmark store, or restoration exceeds the existing connection-startup deadline. The app clears only that profile's stale record, opens a fresh session, sends the utterance once, and presents a bounded recovery notice. A late replay or response from the discarded connection is ignored.
8. The user deletes or materially edits a profile. Its session bookmark and interrupted-work markers are removed; unrelated profiles remain recoverable.

### What “durable” means

This feature guarantees durable **references and a deterministic recovery attempt**, not app-owned conversation memory and not immortal work:

| State | Survives app relaunch? | Owner | Relaunch behavior |
| --- | --- | --- | --- |
| Opaque ACP session ID | Yes, bounded | Voice Activation transports it; provider owns session | Capability-gated load/resume |
| Provider conversation context | Only if provider retained the session | ACP provider | Provider resolves the saved ID |
| Visible transcript | No local copy | Provider | Rebuilt only from `session/load` replay |
| Ordinary in-flight prompt | No | Dead adapter process/connection | Mark interrupted; never auto-repeat |
| Provider task ID | Identifier only | Background Task Continuity feature/provider | Mark local execution interrupted; status handling is delegated |
| Prompts, output, reasoning, tools, native context | No | Provider/live presentation | Never written by this feature |

### Runtime capability policy

`initialize` returns `agentCapabilities`. Decode exactly these optional fields:

```json
{
  "agentCapabilities": {
    "loadSession": true,
    "sessionCapabilities": {
      "resume": {}
    }
  }
}
```

An absent or null value is unsupported. `loadSession`, when present, must be Boolean. `resume`, when present, must be an object as defined by ACP v1; object presence means supported. A Boolean/string/array `resume` makes the initialize result malformed. Silently guessing would turn a protocol violation into unsafe behavior.

| Restoration need | `loadSession` | `resume` | Exact operation and fallback |
| --- | ---: | ---: | --- |
| Rebuild visible panel history | true | either | Call `session/load`; accept bounded replay before its response |
| Rebuild visible panel history | false | true | Call `session/resume`; show no-history notice; continue with context only |
| Continue without replaying history | either | true | Call `session/resume`; never narrate or synthesize history |
| Continue without replaying history | true | false | Call `session/load`; drain bounded source-tagged replay into a discard sink |
| Any need | false | false | Do not call either method; remove bookmark and call `session/new` |

For `session/load` and `session/resume`, send exactly the saved `sessionId`, current compatible `cwd`, and `mcpServers: []`. If an optional restore method returns a session-unavailable error **before any live prompt frame is published**, close that connection, clear the bookmark, connect once more with `session/new`, and send the user's utterance once. Do not fall back after a prompt may have reached the provider.

### Verified provider support on 2026-09-05

The repository's initialize-only probe was run against the exact project pins without authenticating, opening a session, or making a model call:

```text
Cursor CLI 2026.01.23-916f423  protocol v1  loadSession, promptCapabilities
Codex CLI 0.153.1 + codex-acp 1.8.0  protocol v1  loadSession, sessionCapabilities
Claude CLI 2.1.220 + claude-agent-acp 0.73.0  protocol v1  loadSession, sessionCapabilities
```

| Provider | `loadSession` | `resume` | Implementable restart contract |
| --- | ---: | ---: | --- |
| Cursor CLI `2026.01.23-916f423` | true | not advertised | Use `session/load`; never send `session/resume` |
| `@agentclientprotocol/codex-acp` `1.8.0` | true | true | Load for panel rebuild; resume when replay is unnecessary |
| `@agentclientprotocol/claude-agent-acp` `0.73.0` | true | true | Load for panel rebuild; resume when replay is unnecessary |
| Custom ACP v1 | runtime value | runtime value | Apply the table above; absent capability means fresh session |

The official ACP session setup specification requires clients to gate `session/load` on `loadSession`; load replays the complete conversation as `session/update` notifications before returning. It separately gates `session/resume` on `sessionCapabilities.resume`; resume restores context without replay ([ACP Session Setup](https://agentclientprotocol.com/protocol/v1/session-setup), [resume stabilization announcement](https://agentclientprotocol.com/announcements/session-resume-stabilized)). Cursor documents reopening conversations through load ([Cursor ACP documentation](https://cursor.com/docs/cli/acp)). The pinned [Codex adapter source](https://github.com/agentclientprotocol/codex-acp/blob/v1.8.0/src/CodexAcpServer.ts) advertises load plus resume and obtains history only on load. The pinned [Claude adapter source](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/acp-agent.ts) advertises load plus resume and calls `replaySessionHistory` only on load.

Those capabilities recover a provider session. They do not say that a request survived the death of the adapter process. In particular, Claude adapter async tasks may remain live only while that adapter process and its session survive; after Voice Activation relaunches the child process is gone, so this plan marks the local work interrupted and makes no resume claim.

## Current-state evidence

- `ACPClientConnection.start()` in `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` initializes with empty client capabilities, parses protocol/auth/agent information, then always sends `session/new`. It parses neither `agentCapabilities.loadSession` nor `agentCapabilities.sessionCapabilities.resume`.
- `ACPClientConnection` in `Sources/VoiceActivationCore/ACPClientConnection.swift` retains only an in-memory `sessionID`. `connect(...)` returns after a new session is created and exposes no activation result.
- `ACPClientConnection.receive(_:)` in `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift` accepts `session/update` only for the current `sessionID`. A correct load implementation must install the saved ID and a bounded restoration sink **before** sending `session/load`, because history arrives before the response.
- `ACPEventDecoder` in `Sources/VoiceActivationCore/ACPEventDecoder.swift` decodes live agent messages, thoughts, tool calls, plan updates, permissions, and metadata. It currently reduces `user_message_chunk` to metadata, so it cannot faithfully rebuild user turns from load replay.
- `ACPAgentRunner` in `Sources/VoiceActivationCore/ACPAgentRunner.swift` caches at most four `ACPAgentConnectionRecord` values. `connectionRecord(...)` in `ACPAgentRunner+Connection.swift` reuses them only while the current process lives and configuration remains equal. Relaunch loses the dictionary and every child transport.
- `ACPAgentRunner.run(...)` already retries a missing remote session once only before provider activity. That safe-before-publish boundary must also govern persisted restoration fallback.
- `AgentHarnessRunning.run(...)` in `Sources/VoiceActivationCore/AgentHarnessRunning.swift` streams unqualified `AgentRunEvent` values. The coordinator therefore cannot distinguish provider-replayed history from live events.
- `AgentRunLifecycleEvent.event` in `Sources/VoiceActivationCore/VoiceActivationCoordinator.swift` goes to both `AgentRunPresentation.receive` and `AgentConversationAudioPresenter.handle` through `AppModel.handleAgentRunLifecycleEvent(_:)`. Replayed `agent_message_chunk` events would be spoken and replayed tool sounds would fire unless source is carried end to end.
- `AppPreferences` in `Sources/VoiceActivationCore/AppPreferences.swift` stores user configuration in `UserDefaults`, but no source persists session IDs, task IDs, conversation content, or continuity state today.
- `VoiceActivationApp` constructs the default `AppModel` in `Sources/VoiceActivationApp/VoiceActivationApp.swift`; this is the composition seam for one App-owned bookmark store.
- `docs/agent-harness.md` correctly describes today's lifetime as one cached process/session per profile while the app remains alive. It promises no restart recovery.

## Chosen architecture

### Persistence model

Persist one versioned envelope under `voiceActivation.agentContinuity.v1`:

```swift
public struct AgentSessionBookmark: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let sessionID: String
    public let providerFingerprint: String
    public let lastAccessOrdinal: UInt64
}

public enum AgentInterruptedWorkState: String, Codable, Equatable, Sendable {
    case active
    case interruptedByProcessExit
}

public struct AgentInterruptedWorkKey: Codable, Hashable, Sendable {
    public let profileID: UUID
    public let sessionID: String
    public let occurrenceID: UUID
}

public struct AgentInterruptedWorkMarker: Codable, Equatable, Sendable {
    public let key: AgentInterruptedWorkKey
    public let turnID: String?
    public let providerTaskID: String?
    public let state: AgentInterruptedWorkState
}

public struct AgentContinuityEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var bookmarks: [AgentSessionBookmark]
    public var interruptedWork: [AgentInterruptedWorkMarker]
}
```

The store enforces:

- at most 64 bookmarks and 64 work markers;
- at most 4,096 UTF-8 bytes per ACP session, turn, or task identifier, matching `ACPEventDecoder.maximumOpaqueIdentifierBytes`;
- exactly 64 lowercase hexadecimal characters in `providerFingerprint`;
- at most 512 KiB for the encoded envelope;
- unique profile IDs in bookmarks and unique `AgentInterruptedWorkKey` values; a fresh local `occurrenceID` is allocated for every prompt or provider-task lifecycle, so provider task-ID reuse can never merge two lifecycles;
- LRU eviction by `lastAccessOrdinal`, never by parsing an opaque identifier;
- strict decode into schema version 1. Unknown versions and malformed records are quarantined in memory as empty, diagnosed without content, and replaced only on the next explicit mutation.

`AgentSessionBookmark` is written immediately after a successful `session/new`, `session/load`, or `session/resume`. Bookmark write failure does not fail the live turn; it produces privacy-safe diagnostic `continuity_store.save_failed` and means only that the next launch cannot restore.

Allocate a fresh `occurrenceID`, then set an `.active` work marker immediately before publishing `session/prompt`; clear that exact key after the terminal prompt response and ordered event delivery settle. On app launch, atomically rewrite every remaining `.active` marker to `.interruptedByProcessExit` before allowing a new turn. Return the rewritten markers to presentation. Ordinary-turn keys stay persisted until the first post-launch prompt for that profile successfully carries the consume-once interruption flag; failure or exit before frame publication leaves them for the next launch. A marker carrying `providerTaskID` is acknowledged only after Background Task Continuity accepts its interrupted presentation handoff. `acknowledgeInterruptedWork(_:)` removes exact keys only. The marker supports honest UI and background-task handoff; it is not evidence that work remains alive.

### Provider compatibility fingerprint

`AgentProviderFingerprint.make(configuration:)` returns lowercase SHA-256 of this versioned, length-prefixed UTF-8 sequence:

```text
voice-activation.agent-provider-fingerprint.v1
preset.rawValue
executablePath
each argument, preserving order and empty values
workingDirectory
systemPrompt
```

Each field is prefixed with an unsigned 64-bit big-endian byte length and argument count is included before arguments. Display name, permission policy, response speech settings, presentation preferences, and profile wake phrase are excluded because they do not identify the provider's session namespace or working context. No raw configuration field is persisted. A mismatch suppresses the old ID entirely, removes its bookmark/work markers, and starts a new session.

### Negotiation and session activation

```swift
public struct ACPSessionRestorationCapabilities: Equatable, Sendable {
    public let loadSession: Bool
    public let resumeSession: Bool
}

public enum AgentSessionRestorationNeed: Equatable, Sendable {
    case visibleHistory
    case contextOnly
}

public enum AgentSessionActivation: Equatable, Sendable {
    case new(sessionID: String)
    case loaded(sessionID: String)
    case resumed(sessionID: String)
    case freshAfterUnavailableBookmark(sessionID: String)
    case freshBecauseRestorationUnsupported(sessionID: String)
}

public enum AgentContinuityPromptSessionState: String, Codable, Equatable, Sendable {
    case loaded
    case resumedWithoutHistory = "resumed_without_history"
    case freshAfterUnavailableBookmark = "fresh_after_unavailable_bookmark"
    case freshBecauseRestorationUnsupported = "fresh_because_restoration_unsupported"
}

public struct AgentContinuityPromptContext: Codable, Equatable, Sendable {
    public let schema: String
    public let sessionState: AgentContinuityPromptSessionState
    public let previousTurnInterrupted: Bool
}

public struct AgentRestorationToken: Hashable, Sendable {
    public let rawValue: UUID
}

public enum AgentRunStreamEvent: Equatable, Sendable {
    case restorationStarted(token: AgentRestorationToken, sessionID: String)
    case restored(token: AgentRestorationToken, event: AgentRunEvent)
    case restorationCompleted(token: AgentRestorationToken, activation: AgentSessionActivation)
    case restorationAborted(token: AgentRestorationToken)
    case live(AgentRunEvent)
}
```

`AgentSessionRestorationPolicy.operation(need:capabilities:)` is a pure Core function returning `.load`, `.loadDiscardingReplay`, `.resume`, or `.new`. Provider presets never enter the decision.

Change connection construction to:

```swift
public struct ACPConnectionResult: Sendable {
    public let connection: ACPClientConnection
    public let activation: AgentSessionActivation
    public let capabilities: ACPSessionRestorationCapabilities
}

public static func connect(
    transport: any ACPTransport,
    configuration: AgentHarnessConfiguration,
    restoration: AgentSessionRestorationRequest?,
    onRestoredEvent: @escaping @Sendable (AgentRunEvent) async -> Void,
    diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared
) async throws -> ACPConnectionResult
```

`AgentSessionRestorationRequest` contains the validated session ID and need. `ACPClientConnection.start(restoration:onRestoredEvent:)` performs initialize, parses capabilities, chooses the operation, and returns activation metadata. Existing callers pass `nil` and receive a new session.

For load, install the saved `sessionID`, a fresh restoration token, a restoration-owned response-channel router, and a dedicated bounded `AgentRunEventDelivery` before sending the request. `receive(_:)` routes matching updates to that sink until the load response arrives. It rejects permission requests during replay, flushes the response router to presentation only, finishes delivery, clears the sink, then publishes `.restorationCompleted`. A failed, overflowing, or cancelled attempt emits `.restorationAborted(token:)`, invalidates the token before cancelling delivery, clears staged replay, resets that router, and closes the transport. A later callback from attempt one therefore cannot mutate attempt two.

Resume rejects only historical conversation updates (`user_message_chunk`, agent/thought message chunks, tool calls, plans, and permission requests) before its response. Provider setup/state publications needed to rebuild the live session—such as available commands and current-goal state—are allowlisted, tagged as silent setup state, and never enter presentation or audio. This matches the pinned Codex adapter, which can publish setup state during resume without replaying conversation history.

### End-to-end source and identity flow

```text
app launch
  -> UserDefaultsAgentContinuityStore.reconcileInterruptedWork()
  -> .active identifiers become .interruptedByProcessExit

voice activation for profile P
  -> compute provider fingerprint from live configuration
  -> read bookmark P; reject mismatch/corruption before process launch
  -> start pinned/custom ACP adapter; initialize and parse runtime capabilities
  -> policy selects load, resume, or new
      load: install session/replay token -> session/load -> bounded restored events
      resume: session/resume -> no historical events
      new: session/new
  -> derive continuity status from the completed activation
  -> copy it into the immutable AgentPrompt
  -> save returned/confirmed opaque session bookmark
  -> allocate local work occurrence; mark its exact key active
  -> send new session/prompt once
  -> live events use current turn token
  -> settle event delivery, clear active marker, retain bookmark
```

The coordinator maps `AgentRunStreamEvent.restored` to `AgentRunLifecycleEvent.historyEvent`; presentation accepts it only for the current run and restoration token. Audio ignores history lifecycle events entirely—no narration segmentation, speech queue, working pulse, or tool sound. `restorationCompleted` converts any historical in-progress tool or plan row to interrupted and adds a provider-history divider before the current turn. Every restoration attempt owns a separate response-channel router; typed and marker-delimited restored content is rendered but never spoken, while legacy content remains visible and silent.

Connection activation happens before final prompt encoding. The runner derives `AgentContinuityPromptContext` from the actual `ACPConnectionResult.activation` and the consume-once interrupted-work flag, copies that value into the immutable `AgentPrompt`, and only then calls `session/prompt`. `MacContextPromptEncoder` serializes instruction → continuity status → captured context → resource links → untouched request. The status JSON is bounded below 512 bytes and contains only enums/Booleans—never an identifier or remembered content. The first successfully published post-launch prompt for a profile consumes `previousTurnInterrupted`; failure before the prompt frame is written retains it, and later prompts do not repeat it. This lets the ACP agent decide whether its answer should mention lost history or interrupted work. Voice Activation displays fixed client status in the panel but never synthesizes that locally authored text.

### Failure, cancellation, and identity rules

- The existing 12-second connection-startup deadline covers one process launch, initialize, and load/resume attempt. Safe fresh fallback gets one new connection under the same 12-second per-attempt deadline, so worst-case restoration plus fallback is bounded at 24 seconds.
- A restore failure gets one fresh-connection retry only when no prompt frame and no live event have been published. The failed connection is closed before the replacement process starts.
- `session/load` replay shares current `AgentRunEventDelivery` text/control bounds and ordering. Overflow closes the restoring connection and falls back fresh before the prompt.
- A load update must match the saved `sessionID`, current run, and current non-persisted restoration token. A callback after cancellation, timeout, fresh fallback, profile edit, or run replacement is ignored.
- A historical permission request encountered during load is rejected and never shown or answered. Only a newly emitted `.live` `session/request_permission` with a current turn token is actionable.
- Active work identity is persisted before prompt publication. A confirmed terminal result clears its exact `AgentInterruptedWorkKey`; cancellation or connection loss without a confirmed terminal response leaves it active, and the next launch reconciliation changes it to interrupted before presentation.
- `shutdown()` closes transports but retains compatible bookmarks; `reset(profileIDs:)` closes/removes those profiles and deletes their persisted bookmarks and work markers.
- A session-unavailable error on a later live turn keeps today's safe retry rule: retry only if the request cannot have been published. Any ambiguous post-publication loss fails visibly and never duplicates the utterance.
- Diagnostics may record provider preset, operation (`new`, `load`, `resume`), capability Booleans, counts, timing, and failure category. They never record session/turn/task identifiers or a fingerprint.

### Rejected alternatives

- **Persist the panel snapshot or transcript:** rejected. It duplicates provider memory, stores sensitive conversation data, and still cannot reconstruct provider tool state.
- **Summarize the conversation locally before quit:** rejected. It is semantic memory work and a second agent. It also cannot run reliably after a crash.
- **Always call `session/load`:** rejected. ACP forbids it when `loadSession` is absent/false, and load replays history even when the caller only needs context.
- **Always call `session/resume`:** rejected. Cursor's current initialize result does not advertise resume, and the method deliberately cannot rebuild visible history.
- **Infer capability from Cursor/Codex/Claude preset:** rejected. Custom commands, adapter upgrades, and future protocol changes make runtime initialization the only authoritative source.
- **Automatically resend the interrupted prompt:** rejected. The first request may have reached the provider; replay can duplicate tool side effects.
- **Treat Claude async work as durable after relaunch:** rejected. Its ACP capability describes session recovery, not survival of an adapter-owned async task after that adapter process dies.
- **Search provider session lists when a bookmark is missing:** rejected. That requires provider-specific ownership/matching semantics and risks attaching the wrong conversation. Only an exact app-retained opaque ID is eligible.
- **Keep adapter processes alive through an app update/quit:** rejected. It complicates ownership, orphan cleanup, signing, and cancellation while still not surviving crashes or logout.

## File map and interfaces

| File | Change | Responsibility |
| --- | --- | --- |
| `Sources/VoiceActivationCore/AgentSessionContinuity.swift` | Create | Bookmark, work marker, capabilities, restoration need/activation, stream-source types |
| `Sources/VoiceActivationCore/ACPClientCapabilities.swift` | Create | Generic deep-merging initialize capability composer; later plans add namespaced fragments |
| `Sources/VoiceActivationCore/AgentSessionRestorationPolicy.swift` | Create | Pure capability-to-operation decision table |
| `Sources/VoiceActivationCore/AgentProviderFingerprint.swift` | Create | Versioned SHA-256 compatibility fingerprint |
| `Sources/VoiceActivationCore/AgentContinuityStoring.swift` | Create | Async framework-neutral persistence protocol and in-memory implementation |
| `Sources/VoiceActivationCore/AgentPrompt.swift` | Dependency integration after Mac Context Snapshot lands | Add optional fixed-schema continuity context without persisting it |
| `Sources/VoiceActivationCore/AgentHarnessRunning.swift` | Modify | Stream `AgentRunStreamEvent`; accept restoration need |
| `Sources/VoiceActivationCore/ACPClientConnection.swift` | Modify | Store parsed capabilities/restoration identity; return `ACPConnectionResult` |
| `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift` | Modify | Decode capabilities; issue capability-gated new/load/resume |
| `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift` | Modify | Route pre-response load replay to bounded restoration delivery |
| `Sources/VoiceActivationCore/ACPEventDecoder.swift` | Modify | Decode replayed user message chunks as typed events |
| `Sources/VoiceActivationCore/AgentRunEvent.swift` | Modify | Add `userMessageDelta(messageID:text:)` |
| `Sources/VoiceActivationCore/ACPAgentRunner.swift` | Modify | Inject continuity store; retain four live connections while bookmarks remain durable |
| `Sources/VoiceActivationCore/ACPAgentRunner+Connection.swift` | Modify | Read compatible bookmark, select restore, retry fresh before publish, save activation |
| `Sources/VoiceActivationCore/ACPAgentRunnerSupport.swift` | Modify | Persist/clear active work at prompt lifecycle boundaries |
| `Sources/VoiceActivationCore/VoiceActivationCoordinator.swift` | Modify | Add source-qualified lifecycle cases and restoration identity |
| `Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift` | Modify | Request visible-history restore for a relaunched conversation and reject stale events |
| `Sources/VoiceActivationApp/UserDefaultsAgentContinuityStore.swift` | Create | Bounded versioned storage and atomic startup reconciliation |
| `Sources/VoiceActivationApp/AppModel.swift` | Modify | Inject one continuity store and publish interrupted state |
| `Sources/VoiceActivationApp/AppModel+Lifecycle.swift` | Modify | Reconcile markers before listener startup and retain exact profile-reset ownership |
| `Sources/VoiceActivationApp/AppModel+AgentConversation.swift` | Modify | Route restored history to presentation only |
| `Sources/VoiceActivationApp/AgentConversationAudio.swift` | Modify | Exhaustively ignore restoration lifecycle events |
| `Sources/VoiceActivationApp/AgentRunPresentation.swift` | Modify | Rebuild bounded history, mark unfinished historical rows interrupted |
| `Sources/VoiceActivationApp/VoiceActivationApp.swift` | Modify | Compose store and reconcile before coordinator start |
| `Tests/VoiceActivationCoreTests/ACPSessionRestorationCapabilitiesTests.swift` | Create | Strict decode and missing=false contract |
| `Tests/VoiceActivationCoreTests/AgentSessionRestorationPolicyTests.swift` | Create | Complete load/resume/new truth table |
| `Tests/VoiceActivationCoreTests/AgentProviderFingerprintTests.swift` | Create | Stable canonicalization and exact field sensitivity |
| `Tests/VoiceActivationCoreTests/ACPClientConnectionRestorationTests.swift` | Create | Wire order, replay, bounds, cancellation, malformed capability behavior |
| `Tests/VoiceActivationCoreTests/ACPAgentRunnerContinuityTests.swift` | Create | Bookmark lookup/save/invalidation and safe fresh retry |
| `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift` | Modify | Lifecycle source and stale restoration rejection |
| `Tests/VoiceActivationAppTests/UserDefaultsAgentContinuityStoreTests.swift` | Create | Schema, bounds, corruption, LRU, reconciliation |
| `Tests/VoiceActivationAppTests/AppModelLifecycleTests.swift` | Modify | Startup ordering and safe reconciliation failure |
| `Tests/VoiceActivationAppTests/AppModelSettingsTests.swift` | Modify | Exact affected-profile reset behavior remains the bookmark invalidation seam |
| `Tests/VoiceActivationAppTests/AppModelTestSupport.swift` | Modify | Inject one shared store through the existing fixture |
| `Tests/VoiceActivationAppTests/AgentConversationAudioPresenterTests.swift` | Modify | Historical events never produce speech/sounds |
| `Tests/VoiceActivationAppTests/AgentRunPresentationRestorationTests.swift` | Create | History reconstruction, stale-token rejection, and interrupted rows without exceeding the existing 662-line suite |
| `docs/agent-harness.md` | Modify | Capability matrix, exact restore wire flow, lifetime contract |
| `docs/configuration.md` | Modify | What changes invalidate a bookmark |
| `docs/architecture.md` | Modify | Identifier-only persistence boundary and restart ownership |
| `docs/troubleshooting.md` | Modify | Unsupported/stale/missing session and interrupted work behavior |
| `README.md` | Modify | Durable conversation capability and limitation summary |

Core storage interface:

```swift
public protocol AgentContinuityStoring: Sendable {
    func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark?
    func save(bookmark: AgentSessionBookmark) async throws
    func remove(profileIDs: Set<UUID>) async throws
    func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws
    func clearWork(_ key: AgentInterruptedWorkKey) async throws
    func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker]
    func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws
}
```

`InMemoryAgentContinuityStore` is the runner's test/default dependency. Production explicitly injects `UserDefaultsAgentContinuityStore`; no Core type imports AppKit or assumes a preferences suite.

Runner interface after the change:

```swift
func run(
    profileID: UUID,
    configuration: AgentHarnessConfiguration,
    prompt: AgentPrompt,
    restorationNeed: AgentSessionRestorationNeed,
    onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
) async throws -> AgentRunResult
```

`AgentPrompt` is supplied by the Mac Context Snapshot plan. Add `continuity: AgentContinuityPromptContext?` to that value. The caller supplies request/context, but the runner performs a post-activation composition step: it derives continuity from `ACPConnectionResult.activation`, copies it into the prompt, and asks `MacContextPromptEncoder` to emit instruction → continuity-status JSON → Mac-context JSON/resource links → untouched request. Until that dependency lands, this task keeps `prompt: String` and changes only `restorationNeed` plus the stream event. There is no temporary untyped context serialization.

## ACP wire and data flow

### Load with visible replay

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"_meta":{"ciobanu.org.voiceActivation":{"responseChannels":{"version":1}}}},"clientInfo":{"name":"voice-activation","title":"Voice Activation","version":"0.1.0"}}}
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true,"sessionCapabilities":{"resume":{}}}}}
{"jsonrpc":"2.0","id":2,"method":"session/load","params":{"sessionId":"opaque-provider-id","cwd":"/compatible/current/cwd","mcpServers":[]}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"opaque-provider-id","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"historical request","_meta":{"ciobanu.org.voiceActivation":{"promptBlockRole":"request"}}}}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"opaque-provider-id","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"historical answer"}}}}
{"jsonrpc":"2.0","id":2,"result":{}}
{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"opaque-provider-id","prompt":[{"type":"text","text":"System instruction …"},{"type":"text","text":"new request"}]}}
```

Notifications between request 2 and response 2 are `.restored`; updates after request 3 are `.live`. The app never persists any text shown above.

### Resume without replay

```json
{"jsonrpc":"2.0","id":2,"method":"session/resume","params":{"sessionId":"opaque-provider-id","cwd":"/compatible/current/cwd","mcpServers":[]}}
{"jsonrpc":"2.0","id":2,"result":{}}
```

Receiving any historical conversation update before response 2 violates the selected resume contract; close and use safe fresh fallback before publishing the user's prompt. Allowlisted provider setup/state updates remain silent and do not count as replay.

### Unsupported or stale bookmark

Do not send its ID. Send the existing `session/new` request, validate the returned identifier against the 4,096-byte bound, save a replacement bookmark, and then send the prompt. This is a negotiated fallback, not an error guess.

## TDD implementation tasks

### Task 1: Define strict capability decoding and restoration policy

**Files:**
- Create: `Sources/VoiceActivationCore/AgentSessionContinuity.swift`
- Create: `Sources/VoiceActivationCore/AgentSessionRestorationPolicy.swift`
- Create: `Sources/VoiceActivationCore/ACPClientCapabilities.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPSessionRestorationCapabilitiesTests.swift`
- Create: `Tests/VoiceActivationCoreTests/AgentSessionRestorationPolicyTests.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPClientCapabilitiesTests.swift`

**Produces:** the exact capability, restoration need, activation, operation, bookmark, marker, stream-source types, and generic additive client-capability composer in this plan. **Consumes:** Foundation and existing `AgentRunEvent` only.

- [ ] **Step 1: Write the strict decoder tests.**

```swift
@Test func decode_WhenCapabilitiesAreOmitted_TreatsOptionalMethodsAsUnsupported() throws {
    let capabilities = try ACPSessionRestorationCapabilities.decode(from: .object([:]))
    #expect(capabilities == .init(loadSession: false, resumeSession: false))
}

@Test func decode_WhenLoadSessionIsNotBoolean_ThrowsMalformedResponse() {
    #expect(throws: ACPClientError.self) {
        try ACPSessionRestorationCapabilities.decode(
            from: .object(["loadSession": .string("yes")]))
    }
}

@Test func decode_WhenResumeObjectIsPresent_TreatsResumeAsSupported() throws {
    let capabilities = try ACPSessionRestorationCapabilities.decode(from: .object([
        "sessionCapabilities": .object(["resume": .object([:])]),
    ]))
    #expect(capabilities.resumeSession)
}

@Test func decode_WhenResumeIsBoolean_ThrowsMalformedResponse() {
    #expect(throws: ACPClientError.self) {
        try ACPSessionRestorationCapabilities.decode(from: .object([
            "sessionCapabilities": .object(["resume": .bool(true)]),
        ]))
    }
}
```

- [ ] **Step 2: Run and confirm RED because `ACPSessionRestorationCapabilities` does not exist.**

Run: `swift test --filter ACPSessionRestorationCapabilitiesTests`

Expected RED: compile failure `cannot find 'ACPSessionRestorationCapabilities' in scope`.

- [ ] **Step 3: Implement strict capability-shape decoding and the complete pure policy.** `loadSession` is an optional Boolean. ACP v1 defines `sessionCapabilities.resume` as an empty capability object: object presence means supported, absent or null means unsupported, and Boolean/string/array values are malformed. The pinned Codex and Claude adapters both emit `{}`.

```swift
static func operation(
    need: AgentSessionRestorationNeed,
    capabilities: ACPSessionRestorationCapabilities
) -> AgentSessionRestorationOperation {
    switch need {
    case .visibleHistory where capabilities.loadSession:
        .load
    case .contextOnly where capabilities.resumeSession:
        .resume
    case .visibleHistory where capabilities.resumeSession:
        .resume
    case .contextOnly where capabilities.loadSession:
        .loadDiscardingReplay
    default:
        .new
    }
}
```

- [ ] **Step 4: Cover all eight `(need, load, resume)` combinations.**

Exact test: `operation_ForEveryCapabilityCombination_MatchesNormativeTable`.

Also prove `ACPClientCapabilities.compose` deep-merges distinct object paths, rejects a scalar/object collision, and returns `{}` with no contributions. It owns composition only; it has no provider or feature policy.

- [ ] **Step 5: Run GREEN and check the new files.**

Run: `swift test --filter 'ACPSessionRestorationCapabilitiesTests|AgentSessionRestorationPolicyTests|ACPClientCapabilitiesTests'`

Expected GREEN: both suites pass; no provider preset participates in policy.

- [ ] **Step 6: Commit this isolated slice.**

```bash
git add Sources/VoiceActivationCore/AgentSessionContinuity.swift Sources/VoiceActivationCore/AgentSessionRestorationPolicy.swift Sources/VoiceActivationCore/ACPClientCapabilities.swift Tests/VoiceActivationCoreTests/ACPSessionRestorationCapabilitiesTests.swift Tests/VoiceActivationCoreTests/AgentSessionRestorationPolicyTests.swift Tests/VoiceActivationCoreTests/ACPClientCapabilitiesTests.swift
git commit -m "feat: define capability-gated ACP restoration"
```

### Task 2: Implement compatibility fingerprint and identifier-only store

**Files:**
- Create: `Sources/VoiceActivationCore/AgentProviderFingerprint.swift`
- Create: `Sources/VoiceActivationCore/AgentContinuityStoring.swift`
- Create: `Sources/VoiceActivationApp/UserDefaultsAgentContinuityStore.swift`
- Create: `Tests/VoiceActivationCoreTests/AgentProviderFingerprintTests.swift`
- Create: `Tests/VoiceActivationAppTests/UserDefaultsAgentContinuityStoreTests.swift`

**Produces:** stable fingerprint, injectable store, bounded app adapter. **Consumes:** `AgentHarnessConfiguration`, `AgentSessionBookmark`, and `AgentInterruptedWorkMarker`.

- [ ] **Step 1: Write exact sensitivity and non-sensitivity tests.**

```swift
@Test func make_WhenSessionDefiningFieldChanges_ChangesFingerprint() {
    let baseline = AgentProviderFingerprint.make(configuration: try! fixtureConfiguration())
    #expect(AgentProviderFingerprint.make(configuration: try! fixtureConfiguration(
        arguments: ["--mode", "other"])) != baseline)
    #expect(AgentProviderFingerprint.make(configuration: try! fixtureConfiguration(
        workingDirectory: "/tmp/other")) != baseline)
}

@Test func make_WhenOnlyDisplayOrPermissionChanges_PreservesFingerprint() {
    let baseline = AgentProviderFingerprint.make(configuration: try! fixtureConfiguration())
    #expect(AgentProviderFingerprint.make(configuration: try! fixtureConfiguration(
        displayName: "Renamed")) == baseline)
    #expect(AgentProviderFingerprint.make(configuration: try! fixtureConfiguration(
        permissionPolicy: .rejectAlways)) == baseline)
}
```

The test file defines `fixtureConfiguration(displayName:arguments:workingDirectory:permissionPolicy:)` by calling the existing public `AgentHarnessConfiguration` initializer; it adds no production mutation helper.

- [ ] **Step 2: Write store tests with a unique ephemeral `UserDefaults` suite.**

Exact tests:

- `save_WhenEnvelopeExceedsBounds_EvictsLeastRecentlyUsedBookmark`
- `bookmark_WhenIdentifierExceeds4096Bytes_ThrowsWithoutWriting`
- `bookmark_WhenSchemaIsUnknown_ReturnsNilAndDoesNotRewriteData`
- `reconcileInterruptedWork_WhenMarkerWasActive_PersistsInterruptedState`
- `acknowledgeInterruptedWork_WhenMarkerMatches_RemovesOnlyInterruptedMarker`
- `clearWork_WhenTwoOccurrencesShareProviderTaskID_RemovesOnlyExactKey`
- `clearWork_WhenTwoPromptsAreActiveInOneProfile_PreservesOtherOccurrence`
- `remove_WhenGivenOneProfile_PreservesUnrelatedRecords`
- `diagnostics_WhenStoreFails_ContainNoIdentifiersOrFingerprint`

- [ ] **Step 3: Run and confirm RED on missing fingerprint/store symbols.**

Run: `swift test --filter 'AgentProviderFingerprintTests|UserDefaultsAgentContinuityStoreTests'`

Expected RED: compile failures for the not-yet-created types.

- [ ] **Step 4: Implement canonical length-prefix hashing and a serialized App store.**

```swift
actor UserDefaultsAgentContinuityStore: AgentContinuityStoring {
    static let key = "voiceActivation.agentContinuity.v1"
    static let maximumRecords = 64
    static let maximumEncodedBytes = 512 * 1_024

    private let defaults: UserDefaults

    func reconcileInterruptedWork() throws -> [AgentInterruptedWorkMarker] {
        var envelope = try readEnvelope()
        let interrupted = envelope.interruptedWork.map {
            AgentInterruptedWorkMarker(
                key: $0.key,
                turnID: $0.turnID,
                providerTaskID: $0.providerTaskID,
                state: .interruptedByProcessExit)
        }
        envelope.interruptedWork = interrupted
        try writeEnvelope(envelope)
        return interrupted
    }

    func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) throws {
        // Remove only exact keys currently persisted as interrupted; never another occurrence.
    }
}
```

All writes encode and validate a complete replacement envelope before the single `UserDefaults.set` call. Tests remove their suite in teardown; production never calls `synchronize()`.

- [ ] **Step 5: Run GREEN plus Core/App actor checks.**

Run: `swift test --filter 'AgentProviderFingerprintTests|UserDefaultsAgentContinuityStoreTests'`

Expected GREEN: deterministic digest fixtures and every bound/corruption/reconciliation test pass.

- [ ] **Step 6: Commit the persistence slice.**

```bash
git add Sources/VoiceActivationCore/AgentProviderFingerprint.swift Sources/VoiceActivationCore/AgentContinuityStoring.swift Sources/VoiceActivationApp/UserDefaultsAgentContinuityStore.swift Tests/VoiceActivationCoreTests/AgentProviderFingerprintTests.swift Tests/VoiceActivationAppTests/UserDefaultsAgentContinuityStoreTests.swift
git commit -m "feat: persist bounded agent session bookmarks"
```

### Task 3: Implement exact ACP load/resume wire behavior

**Files:**
- Modify: `Sources/VoiceActivationCore/ACPClientConnection.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Requests.swift`
- Modify: `Sources/VoiceActivationCore/ACPClientConnection+Receive.swift`
- Modify: `Sources/VoiceActivationCore/ACPEventDecoder.swift`
- Modify: `Sources/VoiceActivationCore/AgentRunEvent.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPClientConnectionRestorationTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPClientConnectionPromptTests.swift`

**Produces:** an initialized `ACPConnectionResult` and ordered source-tagged replay. **Consumes:** Task 1 policy/types and current `ACPTransport` framing.

- [ ] **Step 1: Write scripted-transport tests for the exact load order.**

```swift
@Test func connect_WhenLoadIsSelected_InstallsIdentityBeforeHistoryReplay() async throws {
    let transport = ScriptedACPTransport.load(
        sessionID: "saved",
        updatesBeforeResponse: [
            .userMessage("old question", promptBlockRole: .request),
            .agentMessage("old answer"),
        ])
    let recorder = AgentEventRecorder()

    let result = try await ACPClientConnection.connect(
        transport: transport,
        configuration: configuration,
        restoration: .init(sessionID: "saved", need: .visibleHistory),
        onRestoredEvent: { await recorder.record($0) })

    #expect(result.activation == .loaded(sessionID: "saved"))
    #expect(await recorder.recordedEvents() == [
        .userMessageDelta(messageID: nil, text: "old question"),
        .agentMessageDelta(messageID: nil, text: "old answer"),
    ])
    #expect(await transport.requestMethods == ["initialize", "session/load"])
}
```

- [ ] **Step 2: Add exact negative-path tests.**

Exact tests:

- `connect_WhenLoadCapabilityIsAbsent_DoesNotSendSessionLoad`
- `connect_WhenResumeIsSelected_SendsResumeAndAcceptsNoReplay`
- `connect_WhenResumeEmitsHistoricalMessage_ClosesAsMalformed`
- `connect_WhenResumePublishesAllowlistedSetupState_KeepsItSilentAndSucceeds`
- `connect_WhenLoadUpdateUsesAnotherSession_IgnoresIt`
- `connect_WhenReplayContainsPermission_RejectsAndCloses`
- `connect_WhenReplayOverflowsBound_ClosesBeforePrompt`
- `connect_WhenCancelledDuringLoad_IgnoresLateHistoryAndTerminatesOnce`
- `connect_WhenFirstRestoreAborts_DiscardsStagedReplayAndRejectsLateFirstToken`
- `connect_WhenRestoredUserChunkHasNonRequestRole_DoesNotExposeIt`
- `connect_WhenRestoredUserChunkLacksRoleMetadata_SuppressesIt`
- `connect_WhenRestorationIsAdded_PreservesAllComposedClientCapabilities`
- `connect_WhenLoadFailsWithMissingSession_ReportsUnavailableBeforePrompt`
- `connect_WhenCapabilityValueIsMalformed_ClosesBeforeSessionRequest`

- [ ] **Step 3: Run and confirm RED on missing `session/load`/source support.**

Run: `swift test --filter ACPClientConnectionRestorationTests`

Expected RED: compile failure for the new connection signature and `userMessageDelta`.

- [ ] **Step 4: Parse capabilities and route setup using the pure policy.** Build initialize params through the shared additive `ACPClientCapabilities` composer; restoration adds no client metadata and must preserve every response-channel/AIR contribution.

```swift
let capabilitiesObject = try optionalObject(
    result["agentCapabilities"],
    named: "agentCapabilities") ?? [:]
sessionRestorationCapabilities = try ACPSessionRestorationCapabilities.decode(
    from: .object(capabilitiesObject))

switch AgentSessionRestorationPolicy.operation(
    need: restoration.need,
    capabilities: sessionRestorationCapabilities)
{
case .load, .loadDiscardingReplay:
    return try await loadSession(restoration)
case .resume:
    return try await resumeSession(restoration)
case .new:
    return try await newSession(restorationWasUnsupported: true)
}
```

Set `sessionID` and the restoration delivery/token before `sendRequest(method: "session/load", …)`. Clear and await that delivery before returning connection readiness. Do not reuse the live prompt delivery as a shortcut.

`ACPClientConnectionRestorationTests.swift` defines a private `ScriptedACPTransport` on top of the existing `FakeACPTransport` feed/sent-message primitives; it scripts only initialize/setup frames and never launches a process.

- [ ] **Step 5: Decode `user_message_chunk` with its namespaced prompt-block role.** The Mac Context plan marks outbound blocks under `_meta.ciobanu.org.voiceActivation.promptBlockRole`. During restoration, render only `.request`. If a provider preserves a non-request role, suppress it; if replay drops the metadata, suppress the restored user chunk because ACP has no standard origin field and it may contain app instructions or captured Mac context. Live providers may still emit user chunks, but source and role remain explicit rather than heuristic.

Route restored agent content through the restoration token's response-channel router: typed response metadata wins, then valid marker framing, then silent legacy-visible fallback. Flush on load completion and reset on abort. Never share partial marker state between restoration attempts.

- [ ] **Step 6: Run GREEN and retain existing prompt framing behavior.**

Run:

```bash
swift test --filter ACPClientConnectionRestorationTests
swift test --filter ACPClientConnectionPromptTests
swift test --filter ACPEventDecoderTests
```

Expected GREEN: restore suite passes; existing initialize → new → prompt tests still pass when no restoration request is supplied.

- [ ] **Step 7: Commit the protocol slice.**

```bash
git add Sources/VoiceActivationCore/ACPClientConnection.swift Sources/VoiceActivationCore/ACPClientConnection+Requests.swift Sources/VoiceActivationCore/ACPClientConnection+Receive.swift Sources/VoiceActivationCore/ACPEventDecoder.swift Sources/VoiceActivationCore/AgentRunEvent.swift Tests/VoiceActivationCoreTests/ACPClientConnectionRestorationTests.swift Tests/VoiceActivationCoreTests/ACPClientConnectionPromptTests.swift
git commit -m "feat: restore negotiated ACP sessions"
```

### Task 4: Integrate runner persistence, retry, and interrupted-work lifecycle

**Files:**
- Dependency integration after Mac Context Snapshot lands: `Sources/VoiceActivationCore/AgentPrompt.swift`
- Modify: `Sources/VoiceActivationCore/AgentHarnessRunning.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunner+Connection.swift`
- Modify: `Sources/VoiceActivationCore/ACPAgentRunnerSupport.swift`
- Create: `Tests/VoiceActivationCoreTests/ACPAgentRunnerContinuityTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerCachingTests.swift`
- Modify: `Tests/VoiceActivationCoreTests/ACPAgentRunnerStartupTests.swift`

**Produces:** restart restoration behind the existing harness abstraction. **Consumes:** Tasks 1–3 and current safe-before-activity retry semantics.

- [ ] **Step 1: Write a two-runner restart test over one shared in-memory store.**

```swift
@Test func run_AfterRunnerReplacement_LoadsSavedCompatibleSessionBeforePrompt() async throws {
    let store = InMemoryAgentContinuityStore()
    let first = makeRunner(store: store, scriptedSessionID: "persisted")
    _ = try await first.run(
        profileID: profileID,
        configuration: configuration,
        prompt: .init(request: "first", context: nil, continuity: nil),
        restorationNeed: .visibleHistory,
        onEvent: { _ in })
    await first.shutdown()

    let second = makeRunner(store: store, scriptedSessionID: "unused-new-id")
    let recorder = RunnerStreamEventRecorder()
    _ = try await second.run(
        profileID: profileID,
        configuration: configuration,
        prompt: .init(request: "follow-up", context: nil, continuity: nil),
        restorationNeed: .visibleHistory,
        onEvent: { await recorder.record($0) })

    #expect(await second.recordedRequestMethods() == [
        "initialize", "session/load", "session/prompt",
    ])
    #expect(await second.recordedPrompt().continuity?.sessionState == .loaded)
    #expect(await recorder.recordedEvents().contains(
        .restorationCompleted(
            token: second.restorationToken,
            activation: .loaded(sessionID: "persisted"))))
}
```

The test file's private `makeRunner` returns a harness that wraps the existing fake transport factory and exposes only recorded JSON-RPC method names; `RunnerStreamEventRecorder` is an actor storing `[AgentRunStreamEvent]`.

- [ ] **Step 2: Add exact runner safety tests.**

Exact tests:

- `run_WhenFingerprintDiffers_NeverSendsSavedSessionID`
- `run_WhenRestoreUnsupported_ClearsBookmarkAndStartsNewSession`
- `run_WhenRestoreUnsupported_SendsTypedContinuityStatusBeforeUntouchedRequest`
- `run_WhenLoadSaysMissingBeforePrompt_ClosesThenRetriesNewExactlyOnce`
- `run_WhenConnectionFailsAfterPromptPublication_DoesNotRetryPrompt`
- `run_WhenBookmarkSaveFails_CompletesLiveTurnAndRecordsSafeDiagnostic`
- `run_WhenPromptBegins_WritesActiveMarkerBeforePromptFrame`
- `run_WhenPromptSettles_ClearsOnlyMatchingOccurrenceKey`
- `run_WhenProviderTaskIDIsReused_PreservesEachLocalOccurrence`
- `run_WhenLoadCompletes_ComposesContinuityBeforeEncodingPrompt`
- `run_WhenResumeCompletes_ComposesResumeContinuityBeforeEncodingPrompt`
- `run_WhenFreshFallbackCompletes_ComposesFreshContinuityBeforeEncodingPrompt`
- `shutdown_RetainsBookmarksButMarksActiveWorkInterrupted`
- `reset_RemovesOnlySpecifiedBookmarksAndMarkers`
- `run_WhenCancelledDuringRestore_DoesNotPublishLateRestoredOrLiveEvents`

- [ ] **Step 3: Run and confirm RED because the runner has no store/restoration dependency.**

Run: `swift test --filter ACPAgentRunnerContinuityTests`

Expected RED: initializer/run signature mismatch.

- [ ] **Step 4: Inject the store and preserve the four-process LRU.**

```swift
public init(
    transportFactory: any ACPTransportCreating = ACPProcessTransportFactory(),
    continuityStore: any AgentContinuityStoring = InMemoryAgentContinuityStore(),
    clock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
    drainClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
    settleClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
    diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared
) {
    self.transportFactory = transportFactory
    self.continuityStore = continuityStore
    self.clock = clock
    startupClock = ContinuousACPAgentRunnerClock()
    self.drainClock = drainClock
    self.settleClock = settleClock
    testingHooks = ACPAgentRunnerTestingHooks()
    self.diagnostics = diagnostics
}
```

Evicting one of four live connection records closes only the process; it does not delete the persisted bookmark. A configuration mismatch or explicit `reset` does delete it.

- [ ] **Step 5: Put store and prompt-composition transitions on precise publication boundaries.**

Save bookmark after setup response validation. Derive continuity from the completed activation, copy it into the prompt, encode the full ordered block list, and only then publish. Allocate a local `AgentInterruptedWorkKey` after the event sink/turn identity exist and before `sendPromptRequest` writes. Clear only that key after prompt response and ordered delivery settle. On cancellation or connection loss, leave the active marker for launch reconciliation; never clear ambiguous work as successful.

- [ ] **Step 6: Run GREEN plus existing caching/startup/cancellation suites.**

Run:

```bash
swift test --filter ACPAgentRunnerContinuityTests
swift test --filter ACPAgentRunnerCachingTests
swift test --filter ACPAgentRunnerStartupTests
swift test --filter ACPAgentRunnerCancellationTests
```

Expected GREEN: persisted restoration works across runner instances; all live-cache and cancellation invariants remain green.

- [ ] **Step 7: Commit the runner slice.**

```bash
git add Sources/VoiceActivationCore/AgentPrompt.swift Sources/VoiceActivationCore/AgentHarnessRunning.swift Sources/VoiceActivationCore/ACPAgentRunner.swift Sources/VoiceActivationCore/ACPAgentRunner+Connection.swift Sources/VoiceActivationCore/ACPAgentRunnerSupport.swift Tests/VoiceActivationCoreTests/ACPAgentRunnerContinuityTests.swift Tests/VoiceActivationCoreTests/ACPAgentRunnerCachingTests.swift Tests/VoiceActivationCoreTests/ACPAgentRunnerStartupTests.swift
git commit -m "feat: retain ACP continuity across launches"
```

### Task 5: Restore presentation without replaying audio or active controls

**Files:**
- Modify: `Sources/VoiceActivationCore/VoiceActivationCoordinator.swift`
- Modify: `Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift`
- Modify: `Sources/VoiceActivationApp/AppModel.swift`
- Modify: `Sources/VoiceActivationApp/AppModel+AgentConversation.swift`
- Modify: `Sources/VoiceActivationApp/AgentConversationAudio.swift`
- Modify: `Sources/VoiceActivationApp/AgentRunPresentation.swift`
- Modify: `Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AgentConversationAudioPresenterTests.swift`
- Create: `Tests/VoiceActivationAppTests/AgentRunPresentationRestorationTests.swift`

**Produces:** source-qualified lifecycle and truthful restored UI. **Consumes:** Task 4 stream events and existing run/turn identity.

- [ ] **Step 1: Add source-qualified lifecycle cases and failing routing tests.**

```swift
public enum AgentRunLifecycleEvent: Equatable, Sendable {
    // existing cases remain
    case historyRestorationStarted(
        runID: UUID, token: AgentRestorationToken, sessionID: String)
    case historyEvent(
        runID: UUID, token: AgentRestorationToken, event: AgentRunEvent)
    case historyRestorationCompleted(
        runID: UUID, token: AgentRestorationToken, activation: AgentSessionActivation)
    case historyRestorationAborted(runID: UUID, token: AgentRestorationToken)
}
```

Exact tests:

- `handleLifecycle_WhenEventIsHistorical_UpdatesPresentationWithoutCallingAudioPlayer`
- `handleLifecycle_WhenHistoryCompletes_MarksHistoricalRunningToolsInterrupted`
- `handleLifecycle_WhenResumeHasNoReplay_ShowsProviderHistoryNotice`
- `handleLifecycle_WhenRestoreUnsupported_ShowsFreshConversationNotice`
- `handleLifecycle_WhenRestorationTokenIsStale_IgnoresHistory`
- `handleLifecycle_WhenFirstAttemptAborts_ClearsItsPartialRowsBeforeFallback`
- `handleLifecycle_WhenNewLiveAnswerArrives_SpeaksOnlyThatAnswer`

- [ ] **Step 2: Run and confirm RED on missing history lifecycle cases.**

Run: `swift test --filter 'VoiceActivationCoordinatorConversationTests|AgentConversationAudioPresenterTests|AgentRunPresentationRestorationTests'`

Expected RED: exhaustive-switch and missing-case compile failures.

- [ ] **Step 3: Route history exclusively to presentation.**

```swift
case .historyEvent(let runID, let token, let event):
    agentRunPresentation.receiveRestored(runID: runID, token: token, event: event)
    // Deliberately no call to agentConversationAudioPresenter.
```

`AgentConversationAudioPresenter.handle` explicitly no-ops for all four history cases. Do not depend on an empty narration string; the historical event must never enter narration or activity-sound state.

- [ ] **Step 4: Bound restored presentation using existing panel limits.**

Use existing message/tool/plan normalization and caps. A historical `userMessageDelta` creates a user row only when its preserved namespaced role is `.request`; missing/non-request role metadata is suppressed. Historical agent deltas create agent rows. History completion marks unresolved tool calls and in-progress plan entries interrupted. Historical permissions are rejected during restoration and never become rows or controls; only a newly emitted live `session/request_permission` is actionable.

- [ ] **Step 5: Run GREEN and verify current live narration.**

Run:

```bash
swift test --filter VoiceActivationCoordinatorConversationTests
swift test --filter AgentConversationAudioPresenterTests
swift test --filter AgentRunPresentationRestorationTests
swift test --filter AgentNarrationSegmenterTests
```

Expected GREEN: historical output produces zero speech/tool-sound calls; the first live answer still produces the existing ordered speech segments.

- [ ] **Step 6: Commit the presentation slice.**

```bash
git add Sources/VoiceActivationCore/VoiceActivationCoordinator.swift Sources/VoiceActivationCore/VoiceActivationCoordinator+Execution.swift Sources/VoiceActivationApp/AppModel.swift Sources/VoiceActivationApp/AppModel+AgentConversation.swift Sources/VoiceActivationApp/AgentConversationAudio.swift Sources/VoiceActivationApp/AgentRunPresentation.swift Tests/VoiceActivationCoreTests/VoiceActivationCoordinatorConversationTests.swift Tests/VoiceActivationAppTests/AgentConversationAudioPresenterTests.swift Tests/VoiceActivationAppTests/AgentRunPresentationRestorationTests.swift
git commit -m "feat: rebuild restored conversations silently"
```

### Task 6: Compose launch reconciliation and profile invalidation

**Files:**
- Modify: `Sources/VoiceActivationApp/AppModel.swift`
- Modify: `Sources/VoiceActivationApp/VoiceActivationApp.swift`
- Modify: `Sources/VoiceActivationApp/AppModel+Lifecycle.swift`
- Modify: `Tests/VoiceActivationAppTests/AppModelLifecycleTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AppModelSettingsTests.swift`
- Modify: `Tests/VoiceActivationAppTests/AppModelTestSupport.swift`

**Produces:** production store injection and atomic launch reconciliation. **Consumes:** Task 2 store and Task 4 runner.

- [ ] **Step 1: Add a launch test proving reconciliation precedes activation.**

```swift
@Test @MainActor
func start_WhenWorkMarkerWasActive_PublishesInterruptedStateBeforeListening() async {
    let store = RecordingContinuityStore(activeMarkers: [marker])
    let model = makeAppModel(continuityStore: store)

    await model.start()

    #expect(store.calls.prefix(1) == [.reconcileInterruptedWork])
    #expect(model.interruptedAgentWork == [marker.asInterrupted()])
}
```

- [ ] **Step 2: Add profile lifecycle tests.**

Exact tests:

- `saveSettings_WhenAgentProfileIsRemoved_ResetsItsSessionAndBookmark`
- `saveSettings_WhenProviderFingerprintChanges_ResetsItsSessionAndBookmark`
- `saveSettings_WhenOnlyWakePhraseChanges_PreservesSessionBookmark`
- `start_WhenReconciliationFails_StillStartsListeningAndReportsSafeDiagnostic`
- `firstPostLaunchPrompt_WhenProfileWasInterrupted_CarriesConsumeOnceFlag`
- `secondPostLaunchPrompt_DoesNotRepeatInterruptedFlag`
- `firstPostLaunchPrompt_WhenFrameWriteFails_RetainsInterruptedFlag`

- [ ] **Step 3: Run and confirm RED on missing injected store/start ordering.**

Run: `swift test --filter 'AppModelTests/start_WhenWorkMarkerWasActive|AppModelTests/saveSettings_WhenAgentProfilesChange'`

Expected RED: missing `continuityStore` AppModel initializer argument and interrupted presentation state.

- [ ] **Step 4: Inject one production store and await reconciliation before coordinator start.**

The App-owned actor serializes all UserDefaults access. Failure must not disable wake listening or erase unrelated app preferences. Remove records by profile UUID; never sweep the whole defaults domain. `AppModel` defaults to an in-memory store for isolated tests; `VoiceActivationApp.init()` constructs one `UserDefaultsAgentContinuityStore`, passes that same instance to `ACPAgentRunner` and `AppModel`, then installs the model into SwiftUI `State`.

```swift
init() {
    let continuityStore = UserDefaultsAgentContinuityStore()
    let runner = ACPAgentRunner(continuityStore: continuityStore)
    _model = State(initialValue: AppModel(
        agentRunner: runner,
        continuityStore: continuityStore,
        startsAutomatically: false))
}
```

`AppModel.start()` awaits `reconcileInterruptedWork()`, publishes the bounded markers, and records their exact keys by profile in a bounded, App-owned pending-interruption map before wiring and starting the coordinator. A prompt for that profile receives the flag through the coordinator/runner bridge; the runner combines it with the actual activation result. Only after the prompt frame is accepted does the bridge acknowledge those exact ordinary-turn keys and consume the flag. Failure before write retains both. Markers with a provider task ID remain until Background Task Continuity accepts their interrupted presentation handoff.

- [ ] **Step 5: Run GREEN and build the bundled app.**

Run:

```bash
swift test --filter AppModelTests
CONFIGURATION=debug make app
```

Expected GREEN: focused tests pass and the signed/bundled debug app composes the store without actor-isolation errors.

- [ ] **Step 6: Commit composition.**

```bash
git add Sources/VoiceActivationApp/AppModel.swift Sources/VoiceActivationApp/AppModel+Lifecycle.swift Sources/VoiceActivationApp/VoiceActivationApp.swift Tests/VoiceActivationAppTests/AppModelLifecycleTests.swift Tests/VoiceActivationAppTests/AppModelSettingsTests.swift Tests/VoiceActivationAppTests/AppModelTestSupport.swift
git commit -m "feat: reconcile interrupted agent work on launch"
```

### Task 7: Document, probe, and verify the product contract

**Files:**
- Modify: `docs/agent-harness.md`
- Modify: `docs/configuration.md`
- Modify: `docs/architecture.md`
- Modify: `docs/troubleshooting.md`
- Modify: `README.md`

- [ ] **Step 1: Update behavior and privacy documentation.**

Document the capability table, load-versus-resume behavior, exact fingerprint invalidators, identifier-only persistence, unsupported/missing-session fallback, interrupted-turn wording, and the explicit limit that ACP restoration does not keep ordinary work running after process death.

- [ ] **Step 2: Re-run the safe initialize-only provider probe.**

Run: `.agents/skills/acp-integration/scripts/probe-local-clients.sh all`

Expected evidence: protocol version 1 from all available pinned adapters; `loadSession` from Cursor/Codex/Claude; `sessionCapabilities.resume` only where actually returned. Do not authenticate, call `session/new`, start a model turn, or access secrets.

- [ ] **Step 3: Run focused and proportional verification.**

```bash
swift test --filter 'ACPSessionRestorationCapabilitiesTests|AgentSessionRestorationPolicyTests|AgentProviderFingerprintTests'
swift test --filter 'ACPClientConnectionRestorationTests|ACPAgentRunnerContinuityTests'
swift test --filter 'VoiceActivationCoordinatorConversationTests|UserDefaultsAgentContinuityStoreTests'
swift test --filter 'AgentConversationAudioPresenterTests|AgentRunPresentationRestorationTests'
swift test
CONFIGURATION=debug make app
make check
git diff --check
```

Expected: every focused suite, full suite, bundled app build, repository check, SPDX check, file-length check, and whitespace check pass. The provider probe output matches runtime-gated expectations; it is evidence, not a hard-coded production allowlist.

- [ ] **Step 4: Perform bounded manual verification with a disposable provider session only after explicit operator approval.**

In the bundled app: create one non-sensitive turn; quit; relaunch; speak one follow-up; confirm historical panel rows return exactly once and are silent; confirm only the new answer is spoken. Repeat with Accessibility context disabled to prove restoration is independent. Force-quit during a disposable turn and verify interrupted—not running or completed—appears after launch. Skip and report this row when authenticated provider state, TCC, audio hardware, or paid calls are unavailable.

- [ ] **Step 5: Inspect privacy-safe diagnostics.**

Confirm lifecycle entries contain operation/capability/count/timing fields but no prompt, transcript, message, selected Mac context, raw session/turn/task ID, or fingerprint.

- [ ] **Step 6: Commit documentation after verification.**

```bash
git add README.md docs/agent-harness.md docs/architecture.md docs/configuration.md docs/troubleshooting.md
git commit -m "docs: define durable ACP conversation recovery"
```

## Dependencies on the other five voice plans

| Plan | Dependency contract |
| --- | --- |
| [Mac Context Snapshot](./2026-09-05-mac-context-snapshot.md) | Its `AgentPrompt` may carry per-turn context, but continuity never persists that context. Fingerprint excludes captured values; each follow-up captures fresh native state. |
| [Conversational Control Semantics](./2026-09-05-conversational-control-semantics.md) | It decides user-visible “continue/end/start over” control semantics. This plan supplies exact session activation/interruption state and never parses those phrases inside the runner. |
| [Spoken Confirmations and Results](./2026-09-05-spoken-confirmations-and-results.md) | It lets the ACP agent acknowledge the typed fresh/unsupported/interrupted status in agent-authored speech. Restored history remains explicitly non-narratable. |
| [Voice-First Response Channel](./2026-09-05-voice-first-response-channel.md) | Its connection/session-owned router handles both `.live` and restored content. Restored routing is presentation-only; history lifecycle events bypass speech, barge-in, and audio feedback. |
| [Background Task Continuity](./2026-09-05-background-task-continuity.md) | It owns negotiation and monitoring for durable provider task IDs. This plan persists an optional opaque ID and local interrupted state but never infers task liveness or executes recovery. |

Implementation order: land the typed stream source and continuity store first; Conversational Control and Voice-First Response can then consume stable lifecycle cases. Integrate `AgentPrompt` when Mac Context lands. Background Task Continuity must build on `AgentInterruptedWorkMarker` rather than introduce a second persistence model.

## Explicit non-goals

- No local transcript, summary, embeddings, vector store, memory model, or conversation reconstruction.
- No app-authored semantic interpretation of “continue,” “that,” “again,” or any other utterance.
- No automatic prompt replay after crash, timeout, ambiguous transport loss, or provider error.
- No claim that an ordinary ACP turn or Claude adapter async task survives adapter-process death.
- No provider session discovery/list matching, cross-provider session migration, or profile-to-session guessing.
- No authentication storage, refresh, prompting, or migration; provider CLIs remain responsible.
- No provider-specific persistence path, filesystem scraping, SQLite inspection, or private API.
- No background process keeper, launch daemon, orphaned adapter, or app-owned task executor.
- No restored permission interaction, tool execution, sound effect, speech, or notification.
- No unlimited bookmark count, identifier size, replay queue, panel history, retry loop, or startup wait.
- No change to direct-command profiles; they never create or restore ACP sessions.

## Completion evidence

This path is implementable across today's three pinned providers, degrades deterministically for every conforming ACP v1 adapter, and tells the truth when execution died. Continuity without mythology—gorgeous. 💅
