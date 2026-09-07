<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Documentation Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mixed-purpose documentation set with focused, evidence-backed user, architecture, operations, and contributor guides.

**Architecture:** Keep documentation in a flat `docs/` directory and give every durable claim one canonical owner. Preserve familiar entry-point filenames, move detailed material to focused guides, and use task-based cross-links instead of repeating contracts.

**Tech Stack:** GitHub-flavored Markdown, SwiftPM source and Swift Testing suites as evidence, repository shell checks, and the existing MIT SPDX conventions.

**Spec:** `docs/superpowers/specs/2026-09-05-documentation-overhaul-design.md`

## Global Constraints

- Do not change application behavior, settings, protocol support, dependencies, or `Package.resolved`.
- Preserve unrelated work and inspect `git status --short` before every task.
- Keep `README.md` as the product landing page and `docs/index.md` as the complete task-based map.
- Keep topic files directly under `docs/`; do not introduce audience directories.
- Preserve `docs/architecture.md`, `docs/agent-harness.md`, `docs/configuration.md`, `docs/development.md`, and `docs/troubleshooting.md` as useful entry points.
- Give each detailed default, limit, lifecycle contract, and operational command one canonical owner; summarize and link elsewhere.
- Use **profile**, **passive wake**, **capture**, **conversation**, and **turn** consistently with the definitions added to `docs/index.md`.
- Put the MIT SPDX header within the first 12 lines of every Markdown file.
- Verify high-impact security and lifecycle claims against production code plus an independent focused test or build contract.
- Preserve direct `Foundation.Process` execution with explicit arguments, on-device passive recognition, Keychain-only ElevenLabs credentials, bounded retained content, and stale-callback rejection in every description.
- Run `make check` and `git diff --check` after each task. Run the full local-link and content-ownership audit in Task 8.

## File map

| File | Final responsibility |
| --- | --- |
| `README.md` | Product overview, requirements, minimal quick start, capability and safety summaries, documentation routes. |
| `docs/index.md` | Task-based navigation and shared terminology. |
| `docs/getting-started.md` | First build, permissions, first command, and stable local installation. |
| `docs/configuration.md` | Settings defaults, save behavior, validation, and links to task guides. |
| `docs/wake-profiles.md` | Wake matching, enablement, push-to-talk, capture timing, and spoken cancellation. |
| `docs/command-targets.md` | Direct executables, argument placeholders, examples, validation, and shell safety. |
| `docs/agent-providers.md` | Provider presets, discovery, authentication, working folders, prompts, and permission defaults. |
| `docs/agent-conversations.md` | Conversation workflow, panel behavior, follow-ups, permissions, narration, and output retention. |
| `docs/sound-design.md` | Cue timing, playback ownership, assets, and silent-test contract. |
| `docs/troubleshooting.md` | Symptom-oriented recovery paths. |
| `docs/architecture.md` | Module and subsystem ownership plus top-level state flow. |
| `docs/agent-harness.md` | ACP wire, process, session, prompt, event, permission, cancellation, recovery, and delivery contracts. |
| `docs/concurrency-and-lifecycle.md` | Actors, identities, callbacks, run-loop delivery, cancellation order, queues, audio callbacks, and shutdown. |
| `docs/privacy-and-security.md` | Data paths, process safety, credentials, persistence, redaction, and retained-resource bounds. |
| `docs/diagnostics.md` | JSONL trace schema, rotation, safe fields, commands, timing, and investigations. |
| `docs/development.md` | Repository map, prerequisites, commands, source conventions, and change workflow. |
| `docs/testing.md` | Test architecture, focused iteration, proportional verification, sanitizers, and CI. |
| `docs/packaging.md` | App bundle assembly, resources, signing, verification, installation, and Launch at Login. |
| `docs/documentation.md` | Documentation ownership, style, evidence, change triggers, and review checklist. |

---

### Task 1: Establish the documentation contract

**Files:**
- Create: `docs/documentation.md`
- Read: `AGENTS.md`
- Read: `.agents/skills/development/references/repository-workflow.md`
- Read: `docs/superpowers/specs/2026-09-05-documentation-overhaul-design.md`

**Interfaces:**
- Consumes: the approved file map, project SPDX requirement, source-of-truth policy, and existing guide ownership table.
- Produces: canonical terminology, writing rules, evidence rules, and the ownership matrix every later task follows.

- [ ] **Step 1: Confirm the task starts from the approved checkpoint**

Run:

```bash
git status --short
git log -2 --oneline
```

Expected: no unrelated worktree changes; the design commit is present.

- [ ] **Step 2: Create the documentation maintenance guide**

Create `docs/documentation.md` with these exact sections and responsibilities:

```markdown
# Documentation

## Choose the owning guide
## Shared terminology
## Write from evidence
## Update documentation with behavior
## Style and structure
## Headers and links
## Review checklist
## Related guides
```

The ownership table must include every file in the plan's file map. Define a
profile as one wake phrase plus one target, accent, enablement state, and optional
shortcut; passive wake as continuous on-device phrase recognition; capture as one
recognized utterance being collected; conversation as the retained agent session
and timeline; and turn as one request/response exchange inside that conversation.
State that production code and tests override prose, numeric contracts have one
owner, user guides use second person, reference uses precise present tense, and
every changed claim must name its production owner during review.

- [ ] **Step 3: Verify the guide is repository-compliant**

Run:

```bash
make check
git diff --check
```

Expected: all checks pass and the only new tracked path is
`docs/documentation.md`.

- [ ] **Step 4: Commit the documentation contract**

```bash
git add docs/documentation.md
git commit -m "docs: define documentation ownership"
```

---

### Task 2: Separate onboarding, profiles, commands, and settings reference

**Files:**
- Create: `docs/wake-profiles.md`
- Create: `docs/command-targets.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/configuration.md`
- Read: `Sources/YapOpsCore/ActivationTiming.swift`
- Read: `Sources/YapOpsCore/AppPreferences.swift`
- Read: `Sources/YapOpsCore/WakePhraseMatcher.swift`
- Read: `Sources/YapOpsCore/WakeProfile.swift`
- Read: `Sources/YapOpsCore/WakeProfileCollectionValidator.swift`
- Read: `Sources/YapOpsCore/CommandTemplate.swift`
- Read: `Sources/YapOpsCore/CommandRunner.swift`
- Read: `Tests/YapOpsCoreTests/YapOpsCoordinatorCaptureTests.swift`
- Read: `Tests/YapOpsCoreTests/WakePhraseMatcherTests.swift`
- Read: `Tests/YapOpsCoreTests/CommandRunnerTests.swift`

**Interfaces:**
- Consumes: terminology and ownership rules from `docs/documentation.md`.
- Produces: canonical user workflows for wake/capture and commands, plus the canonical settings/defaults reference used by the README and agent guides.

- [ ] **Step 1: Record the live profile and timing contracts before editing**

Run:

```bash
rg -n 'static let standard|defaultValue|passiveEnabled|readsAgentRepliesAloud|playsAgentWorkingSound|maximum|duplicate|placeholder' Sources/YapOpsCore Tests/YapOpsCoreTests
```

Confirm: 350 ms wake handoff, 5 s initial silence, 1.5 s inactivity, 30 s
capture maximum, 1 s passive restart, 250 ms command cooldown, default
`computer` profile, `/usr/bin/open`, Google `{urlText}` URL, blue accent, and the
Control-Option-Space migrated shortcut behavior.

- [ ] **Step 2: Write the wake-profile guide**

Create `docs/wake-profiles.md` with:

```markdown
# Wake profiles

## What a profile controls
## Match a wake phrase
## Enable or pause passive wake
## Assign push-to-talk
## Understand capture timing
## Cancel a capture by voice
## Recognition availability
## Related guides
```

Use one timing table containing the six confirmed timing values. Explain longest
normalized prefix matching, word boundaries, contextual vocabulary, per-profile
enablement versus **Pause all**, shortcut uniqueness and save-time registration,
on-device-only passive recognition, service-eligible interactive capture, and
the exact `cancel`, `stop`, and `dismiss` rules. Do not describe command or ACP
execution beyond linking to its owning guide.

- [ ] **Step 3: Write the direct-command guide**

Create `docs/command-targets.md` with:

```markdown
# Command targets

## Configure a command target
## Expand recognized text
## Open a search URL
## Open a custom URL scheme
## Run another executable
## Validate and diagnose a target
## Security boundary
## Related guides
```

Include the `{text}` and RFC 3986 `{urlText}` table, the existing Google and
custom-scheme examples, the absolute executable requirement, at least one
placeholder requirement, non-zero exit behavior, discarded standard streams,
and direct `Foundation.Process` execution without a shell.

- [ ] **Step 4: Rewrite configuration as reference instead of workflow**

Keep `docs/configuration.md` focused on:

```markdown
# Configuration reference

## When changes take effect
## Voice and application settings
## Wake-profile fields
## Command-target fields
## Agent-target fields
## Validation summary
## Persistence and credentials
## Related guides
```

Use tables for defaults and fields. State that profile, locale, shortcut, and
conversation-audio edits apply only after **Save Settings** succeeds; Launch at
Login applies immediately; the ElevenLabs key is stored in Keychain; all other
saved preferences and profiles use `UserDefaults`; invalid saves remain open.
Link workflows to `wake-profiles.md`, `command-targets.md`, and the existing ACP
guide without copying their timing or lifecycle paragraphs.

- [ ] **Step 5: Tighten Getting Started to the first successful command**

Retain requirements, clone/build, app path, launch command, permission steps,
default Google flow, cancellation, development signing summary, and a short
agent next step. Remove detailed panel, narration, activity-sound, permission,
and thinking-card behavior; those move to Task 3. End with related links rather
than a forced `Next:` sentence.

- [ ] **Step 6: Verify the user-guide split**

Run:

```bash
rg -n '1\.5 seconds|five seconds|30-second|250-millisecond|\{urlText\}|Foundation\.Process|shell' docs/getting-started.md docs/configuration.md docs/wake-profiles.md docs/command-targets.md
make check
git diff --check
```

Expected: detailed timing appears in `wake-profiles.md`; detailed placeholder
and process behavior appears in `command-targets.md`; the other files summarize
and link.

- [ ] **Step 7: Commit the user configuration split**

```bash
git add docs/getting-started.md docs/configuration.md docs/wake-profiles.md docs/command-targets.md
git commit -m "docs: split profiles and command configuration"
```

---

### Task 3: Add focused provider and conversation guides

**Files:**
- Create: `docs/agent-providers.md`
- Create: `docs/agent-conversations.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/configuration.md`
- Read: `Sources/YapOpsApp/AgentHarnessDraft.swift`
- Read: `Sources/YapOpsApp/AgentExecutableLocator.swift`
- Read: `Sources/YapOpsApp/AgentRunPanelChrome.swift`
- Read: `Sources/YapOpsApp/AgentRunPanelContent.swift`
- Read: `Sources/YapOpsApp/AppModel+AgentConversation.swift`
- Read: `Sources/YapOpsCore/AgentHarnessConfiguration.swift`
- Read: `Sources/YapOpsCore/YapOpsCoordinator+Execution.swift`
- Read: `Tests/YapOpsAppTests/AppModelConversationTests.swift`
- Read: `Tests/YapOpsAppTests/AgentRunPresentationTests.swift`

**Interfaces:**
- Consumes: agent field names from `configuration.md` and shared terms from `documentation.md`.
- Produces: canonical provider setup and user-visible conversation behavior consumed by README, troubleshooting, architecture, and ACP reference.

- [ ] **Step 1: Verify provider presets and panel actions**

Run:

```bash
rg -n 'cursor-agent|codex-acp|claude-agent-acp|permissionPolicy|systemPrompt|maximumPendingAgentPrompts|Stop turn|End conversation|Copy output|Delete' Sources Tests
```

Confirm: Cursor uses `cursor-agent acp`; Codex uses
`npx -y @agentclientprotocol/codex-acp@1.8.0`; Claude uses
`npx -y @agentclientprotocol/claude-agent-acp@0.73.0`; custom arguments are
direct argv; at most 16 follow-ups wait; and stop, end, close, copy, and delete
have distinct semantics.

- [ ] **Step 2: Write the provider setup guide**

Create `docs/agent-providers.md` with:

```markdown
# Agent providers

## Before you begin
## Choose a preset
## Find the executable
## Choose a working folder
## Set the permission policy
## Add a profile system prompt
## Authenticate with the provider CLI
## Configure a custom ACP process
## Related guides
```

Include a preset table with the exact live executable and arguments. Describe
the inherited `PATH`, `/opt/homebrew/bin`, `/usr/local/bin`, ChatGPT resources,
`~/.local/bin`, and installed NVM bins; explain **Detect** versus explicit file
selection; require absolute executable and working-folder paths; keep provider
credentials with provider CLIs; and distinguish Codex developer instructions
from the portable ACP harness instruction behavior.

- [ ] **Step 3: Write the conversation workflow guide**

Create `docs/agent-conversations.md` with:

```markdown
# Agent conversations

## Start a conversation
## Read the timeline
## Continue by voice or push-to-talk
## Resolve permissions
## Stop a turn or end the conversation
## Minimize, restore, close, and delete
## Listen to replies
## Copy retained output
## Recover after provider failure
## Related guides
```

Document the non-activating panel, ordered Markdown timeline, per-burst Thinking
card, bottom-follow policy, persistent movable status pill, live conversation
recognition, 16-follow-up bound, exact spoken permission commands, turn versus
conversation cancellation, narration interruption, macOS/ElevenLabs fallback,
close versus delete retention, copy contents, one-shot lost-session recovery,
and fresh-session behavior after useful-output failure. Leave ACP wire details
to `agent-harness.md`.

- [ ] **Step 4: Replace temporary agent summaries with canonical links**

Update `getting-started.md` to end its agent setup section with links to both new
guides. Update `configuration.md` so agent field tables link to provider setup
and conversation behavior rather than repeating them.

- [ ] **Step 5: Verify the agent user guides**

Run:

```bash
rg -n '1\.8\.0|0\.73\.0|cursor-agent|16|allow all|Stop turn|End conversation|Delete|Keychain' docs/agent-providers.md docs/agent-conversations.md Sources/YapOpsApp Sources/YapOpsCore
make check
git diff --check
```

Expected: preset pins and user-visible actions match live code; checks pass.

- [ ] **Step 6: Commit the agent user guides**

```bash
git add docs/agent-providers.md docs/agent-conversations.md docs/getting-started.md docs/configuration.md
git commit -m "docs: add agent provider and conversation guides"
```

---

### Task 4: Reduce the ACP guide to its technical contract

**Files:**
- Modify: `docs/agent-harness.md`
- Read: `Sources/YapOpsCore/ACPAgentRunner.swift`
- Read: `Sources/YapOpsCore/ACPAgentRunner+Connection.swift`
- Read: `Sources/YapOpsCore/ACPClientConnection.swift`
- Read: `Sources/YapOpsCore/ACPClientConnection+Requests.swift`
- Read: `Sources/YapOpsCore/ACPClientConnection+Receive.swift`
- Read: `Sources/YapOpsCore/ACPProcessTransport.swift`
- Read: `Sources/YapOpsCore/AgentRunEventDelivery.swift`
- Read: `Sources/YapOpsCore/AgentRunEventNormalization.swift`
- Read: `Tests/YapOpsCoreTests/ACPAgentRunnerLifecycleTests.swift`
- Read: `Tests/YapOpsCoreTests/ACPClientConnectionPromptTests.swift`
- Read: `Tests/YapOpsCoreTests/AgentRunEventDeliveryTests.swift`

**Interfaces:**
- Consumes: provider and user-workflow boundaries from Task 3.
- Produces: the canonical ACP process, wire, lifecycle, permission, recovery, and delivery reference used by architecture, privacy, diagnostics, and troubleshooting.

- [ ] **Step 1: Extract the live ACP contract and limits**

Run:

```bash
rg -n 'maximum|Timeout|Grace|Period|protocolVersion|session/new|session/prompt|session/cancel|permission|missing.session|auth_required' Sources/YapOpsCore Tests/YapOpsCoreTests
```

Record the verified values: 8 KiB prompt, 1 MiB frame, four cached sessions,
16 KiB stderr, 12 s startup timeout with one retry, 2 s cancellation grace,
500 ms exit drain, 25 ms prompt settle, 32 pending permissions, 256 delivery
entries, and the delivery byte bounds already enforced in code.

- [ ] **Step 2: Rewrite the guide around technical ownership**

Use this structure:

```markdown
# ACP agent harness

## Contract and ownership
## Process and transport
## Initialize and authenticate
## Create and cache sessions
## Submit prompts and receive updates
## Resolve permissions
## Cancel work
## Recover or discard a session
## Bound untrusted input and delivery
## Compatibility boundaries
## Protocol references
## Related guides
```

Keep exact JSON-RPC identifier handling, NDJSON framing, stable update coverage,
cross-session rejection, ambient CLI authentication, prompt presentation
contract, Codex system-prompt injection, unknown request handling, bounded
two-stage delivery, cache eviction, no-replay recovery boundary, pipe teardown,
and cancellation settlement. Remove panel layout, narration timing, sound cues,
generic privacy narrative, and test-suite inventory; link to their new owners.

- [ ] **Step 3: Check that audience-specific material left the ACP guide**

Run:

```bash
rg -n '620 by 420|372 by 84|Test voice|every 3\.2|Build & test|Thread Sanitizer|Copy output' docs/agent-harness.md
```

Expected: no matches. Then run:

```bash
make check
git diff --check
```

- [ ] **Step 4: Commit the focused ACP reference**

```bash
git add docs/agent-harness.md
git commit -m "docs: focus ACP harness reference"
```

---

### Task 5: Split system overview from concurrency and lifecycle

**Files:**
- Modify: `docs/architecture.md`
- Create: `docs/concurrency-and-lifecycle.md`
- Read: `Sources/YapOpsCore/YapOpsCoordinator.swift`
- Read: `Sources/YapOpsCore/YapOpsCoordinator+Speech.swift`
- Read: `Sources/YapOpsCore/YapOpsCoordinator+Execution.swift`
- Read: `Sources/YapOpsCore/MainRunLoopScheduler.swift`
- Read: `Sources/YapOpsApp/AppModel.swift`
- Read: `Sources/YapOpsApp/AppModel+Lifecycle.swift`
- Read: `Sources/YapOpsApp/AppleSpeechSession.swift`
- Read: `Sources/YapOpsApp/SpeechAudioBufferSink.swift`
- Read: `Tests/YapOpsCoreTests/YapOpsCoordinatorCancellationTests.swift`
- Read: `Tests/YapOpsAppTests/AppModelLifecycleTests.swift`

**Interfaces:**
- Consumes: focused user and ACP guides from Tasks 2–4.
- Produces: the canonical component map and asynchronous lifecycle contract used by contributors and privacy documentation.

- [ ] **Step 1: Map current modules and split-file owners**

Run:

```bash
find Sources/YapOpsCore Sources/YapOpsApp -maxdepth 1 -name '*.swift' -print | sort
rg -n 'generation|runID|turnToken|MainRunLoopScheduler|@MainActor|nonisolated|stop|shutdown' Sources/YapOpsCore Sources/YapOpsApp
```

Group the result into speech/capture, direct commands, ACP, presentation,
conversation audio, settings/persistence, diagnostics, and macOS adapters.

- [ ] **Step 2: Rewrite architecture as the subsystem map**

Use:

```markdown
# Architecture

## Package boundaries
## Runtime composition
## Speech and capture
## Direct-command execution
## Agent execution and presentation
## Settings and persistence
## Diagnostics
## State flow
## Deeper contracts
```

Keep a corrected Mermaid state diagram and name the production owners for every
subsystem. Explain Core versus App framework ownership and same-module extension
splits. Summarize asynchronous invariants, privacy, and ACP behavior in one
paragraph each and link to the canonical detailed guides.

- [ ] **Step 3: Write the concurrency and lifecycle reference**

Create `docs/concurrency-and-lifecycle.md` with:

```markdown
# Concurrency and lifecycle

## Isolation model
## Speech-session generations
## Execution and conversation identities
## Ordered main-run-loop delivery
## Cancellation order
## Bounded queues and backpressure
## Audio callback boundary
## Process and foreign API isolation
## Shutdown and stale work
## Verification invariants
## Related guides
```

Document main-actor ownership, speech generation, execution generation, run ID,
turn token, run-loop modes, invalidate-before-cancel ordering, natural drain
versus forced discard, real-time audio sink behavior, dedicated queues for
Keychain/diagnostics/Service Management, ACP backpressure, and shutdown guards.
Use tests as regression evidence without listing every test case.

- [ ] **Step 4: Verify responsibility separation**

Run:

```bash
rg -n '^## ' docs/architecture.md docs/concurrency-and-lifecycle.md
rg -n 'MainRunLoopScheduler|generation|run identifier|turn token|invalidate|backpressure' docs/architecture.md docs/concurrency-and-lifecycle.md
make check
git diff --check
```

Expected: architecture gives the map; lifecycle owns detailed asynchronous
contracts; checks pass.

- [ ] **Step 5: Commit the architecture split**

```bash
git add docs/architecture.md docs/concurrency-and-lifecycle.md
git commit -m "docs: split architecture and lifecycle"
```

---

### Task 6: Add privacy and diagnostics references, then simplify troubleshooting

**Files:**
- Create: `docs/privacy-and-security.md`
- Create: `docs/diagnostics.md`
- Modify: `docs/troubleshooting.md`
- Read: `Sources/YapOpsApp/JSONLYapOpsDiagnosticRecorder.swift`
- Read: `Sources/YapOpsCore/YapOpsDiagnostics.swift`
- Read: `Sources/YapOpsApp/AgentSpeechCredentialStore.swift`
- Read: `Sources/YapOpsCore/CommandRunner.swift`
- Read: `Sources/YapOpsCore/ACPAgentRunner.swift`
- Read: `Sources/YapOpsCore/AgentRunEventDelivery.swift`
- Read: `Sources/YapOpsApp/AgentRunPresentation.swift`
- Read: `Tests/YapOpsAppTests/JSONLYapOpsDiagnosticRecorderTests.swift`
- Read: `Tests/YapOpsAppTests/AgentSpeechCredentialStoreTests.swift`

**Interfaces:**
- Consumes: process, lifecycle, retention, and conversation contracts from Tasks 3–5.
- Produces: canonical privacy/retention and operations references that troubleshooting and README can summarize safely.

- [ ] **Step 1: Verify every privacy and retention claim**

Run:

```bash
rg -n 'maximum|sensitive|redact|Keychain|UserDefaults|standardError|outputBytes|timeline|audio|transcript|Process' Sources/YapOpsCore Sources/YapOpsApp Tests
```

Confirm diagnostic rotation at 5 MiB with three archives, 512-character field
values, sensitive-key redaction, 512 KiB copyable output, 64 KiB timeline text,
256 timeline items, 32 tools, 16 notices, 16 KiB diagnostics, four cached ACP
sessions, 16 queued follow-ups, 8 KiB prompts/system prompts, 1 MiB frames, and
Keychain-only ElevenLabs credentials.

- [ ] **Step 2: Write the privacy and security guide**

Create `docs/privacy-and-security.md` with:

```markdown
# Privacy and security

## Trust boundaries
## Speech and audio
## Direct commands
## Agent providers and credentials
## Saved configuration
## In-memory conversation data
## Diagnostics and redaction
## Resource limits
## What YapOps does not provide
## Related guides
```

Include one canonical resource-limit table separated into input, transport,
delivery, presentation, and process/session bounds. Distinguish on-device
passive recognition from Apple-service-eligible interactive capture and
ElevenLabs narration. State exactly what persists: explicit settings and
profile system prompts in preferences, optional ElevenLabs key in Keychain, and
rotated redacted diagnostics on disk; no audio, prompt history, run history, raw
tool payloads, or agent output persistence.

- [ ] **Step 3: Write the diagnostics guide**

Create `docs/diagnostics.md` with:

```markdown
# Diagnostics

## Find the current trace
## Understand an entry
## Protect sensitive data
## Filter warnings and errors
## Trace one run
## Compare subsystem timing
## Diagnose a stalled stage
## Understand rotation
## Share a safe report
## Related guides
```

Move the canonical JSONL path and `tail`/`jq` commands from troubleshooting.
Document session ID, sequence, uptime, elapsed time, process ID, category, event,
level, bounded fields, `queue_delay_ms`, `duration_ms`, `main_delivery_ms`,
`run_loop_mode`, and `task_priority`. Explain that a start without a matching
finish identifies the stalled boundary, and require redaction review before
sharing even though sensitive keys are filtered at write time.

- [ ] **Step 4: Rewrite troubleshooting around symptoms**

Keep these symptom headings: missing menu icon, Starting status, on-device
recognition error, empty capture, wake mismatch, missing overlay, failed direct
command, failed provider start, stopped output/open panel, permission wait,
missing speech/sounds, unresponsive push-to-talk, audio-device changes, Launch at
Login, and repeated privacy prompts. Replace the long diagnostic preface with a
short **Collect diagnostics first** section linking to `diagnostics.md`. Link
each remedy to its canonical guide and remove repeated architecture or retention
explanations.

- [ ] **Step 5: Verify privacy and operations claims**

Run:

```bash
rg -n '5 MiB|three|512 KiB|64 KiB|256|32|16 KiB|8 KiB|1 MiB|Keychain|UserDefaults' docs/privacy-and-security.md Sources Tests
rg -n 'yapops\.jsonl|queue_delay_ms|duration_ms|main_delivery_ms|run_loop_mode|task_priority' docs/diagnostics.md Sources Tests
make check
git diff --check
```

Expected: detailed limits live in privacy/ACP; log operations live in
diagnostics; troubleshooting stays symptom-oriented.

- [ ] **Step 6: Commit privacy, diagnostics, and troubleshooting**

```bash
git add docs/privacy-and-security.md docs/diagnostics.md docs/troubleshooting.md
git commit -m "docs: add privacy and diagnostics guides"
```

---

### Task 7: Separate development, testing, and packaging

**Files:**
- Modify: `docs/development.md`
- Create: `docs/testing.md`
- Create: `docs/packaging.md`
- Read: `Package.swift`
- Read: `Makefile`
- Read: `scripts/build-app.sh`
- Read: `scripts/check-license-headers.sh`
- Read: `scripts/check-agent-guidance.sh`
- Read: `scripts/check-swift-structure.sh`
- Read: `scripts/check-swift-documentation.swift`
- Read: `.github/workflows/swift.yml`
- Read: `.agents/skills/testing-and-debugging/references/verification-matrix.md`

**Interfaces:**
- Consumes: canonical architecture, privacy, and documentation contracts.
- Produces: focused contributor workflow, verification, and distribution guides used by README and index.

- [ ] **Step 1: Verify commands, package layout, and CI jobs**

Run:

```bash
sed -n '1,220p' Makefile
sed -n '1,220p' scripts/build-app.sh
sed -n '1,180p' .github/workflows/swift.yml
swift test list | sed -n '1,80p'
```

Confirm Swift tools 6.2, macOS 15, Core/App targets, `make build`, `make test`,
`make app`, `make run`, all quality targets, debug/release configuration, ad-hoc
default signing, bundled resources, CI job names, sanitizer job, and package
dependency ordering.

- [ ] **Step 2: Rewrite the development guide**

Use:

```markdown
# Development

## Prerequisites
## Repository layout
## Common commands
## Make a focused change
## Source conventions
## Public Core documentation
## Update the owning guide
## Related guides
```

Keep repository paths, four-space Swift formatting, 700-line Swift limit,
public Core DocC requirement, no `.xcodeproj`, dependency-change rule, and the
smallest coherent change loop. Move test-suite detail and bundle mechanics to
their new guides.

- [ ] **Step 3: Write the testing guide**

Create `docs/testing.md` with:

```markdown
# Testing

## Test boundaries
## Find and run a focused test
## Core suites
## App suites
## Environment-free test contract
## Proportional verification
## Sanitizers
## Continuous integration
## Report evidence
## Related guides
```

Describe Swift Testing, deterministic speech and ACP fakes, real child-process
fixtures where used, silent/network-free audio tests, process-global AppKit
isolation, `swift test list` before filtering, the focused-to-full progression,
Thread Sanitizer triggers, the CI-equivalent command sequence, and the rule that
an unrun command is not a pass.

- [ ] **Step 4: Write the packaging guide**

Create `docs/packaging.md` with:

```markdown
# Packaging

## Build the app bundle
## Choose a configuration
## Include required resources
## Sign the bundle
## Verify the bundle
## Install a stable development copy
## Enable Launch at Login
## Store the optional narration key
## CI packaging
## Related guides
```

Document `.build/YapOps.app`, the exact bundle contents, `CONFIGURATION`
defaulting to `release`, `SIGN_IDENTITY` defaulting to `-`, `plutil` and
`codesign` verification, why `swift run` is insufficient, installing to
`/Applications`, and stdin-only `--store-elevenlabs-key-from-stdin` provisioning
without showing or persisting a credential.

- [ ] **Step 5: Verify contributor guide ownership**

Run:

```bash
rg -n '^## ' docs/development.md docs/testing.md docs/packaging.md
rg -n 'swift test --sanitize=thread|CONFIGURATION|SIGN_IDENTITY|codesign|store-elevenlabs-key-from-stdin|700|DocC' docs/development.md docs/testing.md docs/packaging.md Makefile scripts .github
make check
git diff --check
```

Expected: workflow stays in development, verification in testing, and bundle
mechanics in packaging.

- [ ] **Step 6: Commit contributor guides**

```bash
git add docs/development.md docs/testing.md docs/packaging.md
git commit -m "docs: split testing and packaging guides"
```

---

### Task 8: Normalize the landing pages, links, sound reference, and full set

**Files:**
- Modify: `README.md`
- Modify: `docs/index.md`
- Modify: `docs/sound-design.md`
- Modify: every guide under `docs/` only when needed to remove duplication, normalize terms, or repair links
- Read: every Markdown file under `docs/`

**Interfaces:**
- Consumes: all canonical guides and shared terminology from Tasks 1–7.
- Produces: the final coherent documentation graph, concise repository landing page, complete task-based index, and verified documentation set.

- [ ] **Step 1: Rewrite the README as a landing page**

Use:

```markdown
# YapOps

## What it does
## Requirements
## Quick start
## Core capabilities
## Privacy and safety
## Documentation
## Development
## License
```

Keep the product description, three prerequisites, `make test`/`make run`, app
path, permission expectation, default `computer` flow, concise capability list,
direct-process/no-server/no-account/on-device-passive/Keychain safety summary,
and links to Getting Started, documentation index, privacy, and development.
Remove detailed ACP recovery, panel geometry, queue, narration, cue, and timing
contracts.

- [ ] **Step 2: Rewrite the documentation index**

Use:

```markdown
# YapOps documentation

## Start here
## Use YapOps
## Understand the system
## Contribute
## Terminology
```

List every final guide exactly once in the audience section where readers first
need it. Define the five shared terms exactly as in `documentation.md`. Use
short “Use it to” descriptions and ensure no guide is orphaned.

- [ ] **Step 3: Normalize the sound reference**

Keep the six-cue table, exact assets and durations, 1.6-second initial thinking
delay, 3.2-second interval, transition deduplication, narration arbitration,
bundled-asset behavior, generation provenance, and silent-test contract. Add
the standard purpose introduction and related-guide section. Remove any generic
conversation workflow better owned by `agent-conversations.md`.

- [ ] **Step 4: Normalize every guide's presentation**

For each non-superpowers guide, ensure it has the SPDX header, one H1, a purpose
paragraph, task-oriented or contract-oriented H2s, consistent terms, and a
**Related guides** section. Replace `Next:` links, promotional adjectives, and
copied numeric contracts with canonical links. Do not rewrite the approved spec
or implementation plan during this presentation pass.

- [ ] **Step 5: Resolve every local Markdown link**

Run this read-only validator from the repository root:

```bash
python3 - <<'PY'
from pathlib import Path
import re
import sys

files = [Path("README.md"), *sorted(Path("docs").rglob("*.md"))]
failures = []
for source in files:
    text = source.read_text()
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        path = target.split("#", 1)[0]
        if not path or "://" in path or path.startswith("mailto:"):
            continue
        resolved = (source.parent / path).resolve()
        if not resolved.exists():
            failures.append(f"{source}: {target}")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"Resolved local links in {len(files)} Markdown files.")
PY
```

Expected: `Resolved local links in … Markdown files.` and exit 0.

- [ ] **Step 6: Audit guide coverage and duplicate contracts**

Run:

```bash
rg -n '^# ' README.md docs --glob '*.md'
rg -n '^## Related guides$' docs --glob '*.md' --glob '!superpowers/**'
rg -n '1\.5 seconds|30 seconds|12 seconds|512 KiB|64 KiB|1 MiB|1\.8\.0|0\.73\.0|3\.2 seconds' README.md docs --glob '*.md' --glob '!superpowers/**'
```

Inspect every match. Keep a repeated number only when a task-oriented summary
needs it and the canonical guide is linked in the same section. Confirm every
major source subsystem—speech, profiles, commands, ACP, presentation,
conversation audio, settings, diagnostics, hotkeys, login items, and packaging—
appears in `architecture.md` or has an explicit link from it.

- [ ] **Step 7: Run the final documentation verification**

Run:

```bash
make check
git diff --check
git status --short
git diff --stat b8db7fb
```

Expected: repository checks pass, no whitespace errors, only documentation files
changed after the design checkpoint, and all 19 final documentation
responsibilities are present.

- [ ] **Step 8: Review the complete diff for stale and missing claims**

Run:

```bash
git diff --word-diff=plain b8db7fb -- README.md docs ':!docs/superpowers/**'
```

For each guide, verify its acceptance criterion from the spec, compare high-risk
claims to the evidence named in its task, and correct contradictions or orphaned
content before committing.

- [ ] **Step 9: Commit the normalized documentation set**

```bash
git add README.md docs
git commit -m "docs: normalize documentation navigation"
```

- [ ] **Step 10: Re-run checks on the committed tree**

Run:

```bash
make check
git diff --check HEAD^
git status --short
```

Expected: checks pass and the worktree is clean.
