<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Documentation overhaul design

## Purpose

YapOps has grown from a wake-phrase command launcher into a menu-bar
application with per-profile shortcuts, persistent agent conversations, ACP
provider integration, streamed presentation, narration, sound feedback,
diagnostics, bounded resource handling, and substantial lifecycle policy. The
documentation describes most of these features, but large pages mix user
workflows, configuration, architecture, protocol contracts, troubleshooting,
and verification. Important facts are repeated across several pages, while
diagnostics, privacy, testing, packaging, and documentation ownership have no
focused home.

The overhaul will give each durable claim one clear owner, provide separate
navigation paths for users and contributors, and keep familiar top-level file
names where they remain useful entry points.

## Goals

- Make the shortest path to first use obvious from the repository landing page.
- Separate task-oriented user guides from implementation and protocol reference.
- Split the oversized architecture and ACP material at stable responsibility
  boundaries.
- Add focused guides for diagnostics, privacy and security, testing, packaging,
  and documentation maintenance.
- Normalize terminology, tone, headings, examples, links, and related-guide
  sections across the documentation set.
- Verify behavioral claims against current production code and focused tests.
- Preserve the repository's privacy, direct-process, bounded-resource,
  cancellation, and stale-callback invariants.

## Non-goals

- Changing application behavior, settings, protocol support, or dependencies.
- Publishing a generated API reference or duplicating public DocC comments.
- Documenting provider behavior that YapOps neither controls nor
  verifies.
- Creating a deep documentation directory hierarchy for a repository of this
  size.
- Turning agent-only guidance under `.agents/` into public product documentation.

## Audience and navigation model

The documentation serves two audiences without forcing either through the
other's material:

1. Users follow task-oriented guides: install, configure a profile, run a
   command, start an agent conversation, and diagnose a problem.
2. Contributors follow system-oriented guides: understand ownership, lifecycle,
   privacy, ACP, diagnostics, tests, packaging, and documentation maintenance.

`README.md` remains the product landing page. `docs/index.md` becomes the full
task-based map and groups guides under **Use YapOps**, **Understand the
system**, and **Contribute**. Topic files remain directly under `docs/`; a flat
layout keeps links short and makes discovery with `rg --files docs` immediate.

## Information architecture

### Repository landing and onboarding

| File | Responsibility |
| --- | --- |
| `README.md` | Product purpose, core capabilities, requirements, minimal quick start, safety summary, and links into the documentation. |
| `docs/index.md` | Complete task-based navigation, terminology, and guide ownership. |
| `docs/getting-started.md` | Clone, build, launch, grant permissions, run the first command, and choose the next guide. |

### User guides and configuration

| File | Responsibility |
| --- | --- |
| `docs/configuration.md` | Saved settings, defaults, validation rules, persistence timing, and a routing table to task guides. |
| `docs/wake-profiles.md` | Passive wake, profile enablement, matching, accents, push-to-talk, capture timing, and spoken cancellation. |
| `docs/command-targets.md` | Direct executable and argument configuration, placeholders, URL examples, validation, and shell-safety behavior. |
| `docs/agent-providers.md` | Cursor, Codex, Claude, and custom provider setup; detection; working folders; authentication; system prompts; permission defaults. |
| `docs/agent-conversations.md` | Starting and continuing conversations, panel behavior, follow-up queueing, turn versus conversation cancellation, permissions, narration, and retained output. |
| `docs/sound-design.md` | Canonical cue map, playback conditions, asset provenance, and silent-test contract. |
| `docs/troubleshooting.md` | Symptom-oriented remedies only, with links to diagnostics and the relevant canonical guide. |

### Architecture and operational reference

| File | Responsibility |
| --- | --- |
| `docs/architecture.md` | Module ownership, subsystem map, top-level state flow, and links to deeper contracts. |
| `docs/agent-harness.md` | ACP transport, initialization, sessions, prompt lifecycle, event delivery, permissions, cancellation, recovery, and provider-process bounds. |
| `docs/concurrency-and-lifecycle.md` | Actor and callback ownership, generation identities, main-run-loop bridging, cancellation order, queue backpressure, audio callbacks, and shutdown. |
| `docs/privacy-and-security.md` | Speech data paths, process execution, credentials, persistence, diagnostic redaction, in-memory retention, and resource limits. |
| `docs/diagnostics.md` | Log location, schema, rotation, safe fields, `jq` recipes, subsystem timing, and latency investigation workflow. |

### Contributor guides

| File | Responsibility |
| --- | --- |
| `docs/development.md` | Repository layout, prerequisites, common commands, source conventions, and change workflow. |
| `docs/testing.md` | Test architecture, focused iteration, proportional verification, sanitizer coverage, environment-free boundaries, and CI jobs. |
| `docs/packaging.md` | Bundle assembly, resources, configurations, signing, verification, stable installation, Launch at Login, and CI packaging. |
| `docs/documentation.md` | Canonical ownership, terminology, writing conventions, evidence expectations, change triggers, headers, links, and review checklist. |

## Canonical ownership rules

- Numeric speech deadlines live in `wake-profiles.md`; architecture pages
  describe the transition and link to the timing reference.
- ACP frame, queue, session, retry, permission, and process limits live in
  `agent-harness.md` unless they describe user-visible retained data, in which
  case `privacy-and-security.md` owns the retention table.
- User actions and panel affordances live in `agent-conversations.md`; the
  architecture pages describe ownership rather than repeating instructions.
- Log fields, rotation, and investigation commands live in `diagnostics.md`;
  troubleshooting links there instead of embedding an operations manual.
- Test inventory and required verification live in `testing.md`; other pages
  name only the focused proof relevant to their contract.
- Bundle construction and signing live in `packaging.md`; onboarding contains
  only what is needed to launch the first build.
- The sound cue timings and assets live only in `sound-design.md`.
- Security and privacy summaries may appear in the README, but detailed data
  handling and bounds live only in `privacy-and-security.md`.

## Content migration

Existing prose will be moved and rewritten rather than copied wholesale:

- The README's long agent section becomes a capability summary pointing to
  `agent-providers.md` and `agent-conversations.md`.
- `configuration.md` keeps settings reference while its wake, command, capture,
  and agent workflows move to their focused guides.
- `architecture.md` keeps the module and state overview. Detailed concurrency,
  cancellation, run-loop, audio, and shutdown contracts move to
  `concurrency-and-lifecycle.md`.
- `agent-harness.md` loses user-interface narration, speech synthesis details,
  generic privacy prose, and broad test inventory. It remains the technical ACP
  contract.
- The diagnostic-log introduction moves from `troubleshooting.md` to
  `diagnostics.md`; troubleshooting retains short commands only where they solve
  a specific symptom.
- Build/test/package material in `development.md` is separated into development,
  testing, and packaging guides.

After migration, redundant paragraphs are deleted. Cross-links replace repeated
contracts; no compatibility stub is needed because the familiar public file
names remain present.

## Writing conventions

- Start each guide with what it helps the reader accomplish and when to use it.
- Use second person for task guides and precise present tense for reference.
- Define **profile**, **passive wake**, **capture**, **conversation**, and
  **turn** once in the index and use those terms consistently.
- Prefer task-oriented headings over implementation-type names in user guides.
- Keep examples executable or directly transferable to Settings.
- Avoid promotional adjectives, hidden prerequisites, and chronological release
  history in behavioral documentation.
- Put the required MIT SPDX header within the first 12 lines of every file.
- End focused guides with a short **Related guides** section rather than a single
  forced linear “Next” link.

## Evidence and verification

Every migrated claim is checked against its production owner and, for
high-impact lifecycle or security behavior, an independent test or build
contract:

| Claim area | Primary evidence | Independent evidence |
| --- | --- | --- |
| Defaults and persistence | `AppPreferences`, `WakeProfile` | preference and draft tests |
| Capture and matching | coordinator speech extensions, matcher, timing | coordinator capture tests |
| Direct commands | `CommandTemplate`, `CommandRunner` | command tests |
| Provider setup | harness configuration, executable locator | draft and locator tests |
| ACP lifecycle and bounds | runner, connection, delivery, transport | focused ACP suites |
| Panel and conversation behavior | presentation, panel, app model | presentation and conversation tests |
| Narration and sounds | audio orchestrator, segmenter, speech queue | audio and sound tests |
| Diagnostics and privacy | diagnostic recorder and call sites | recorder/redaction tests and repository invariants |
| Build and packaging | `Makefile`, build script, resources | CI workflow and bundle verification |

The final documentation set must pass:

```bash
make check
git diff --check
```

Relative Markdown links will also be enumerated and resolved locally. A final
search will check that removed headings, old paths, numeric limits, and key terms
do not leave contradictory copies behind.

## Acceptance criteria

- A new user can build and run the default command from the README and Getting
  Started guide without reading architecture material.
- A user can find one focused guide for wake profiles, command targets, agent
  providers, and agent conversations from the documentation index.
- A contributor can locate canonical documentation for architecture, ACP,
  concurrency, privacy, diagnostics, testing, packaging, and documentation
  maintenance without searching a mixed-purpose page.
- README, architecture, ACP, troubleshooting, and development pages no longer
  combine unrelated audience concerns.
- Every current major subsystem represented under `Sources/` has a documented
  owner or an explicit link from the architecture map.
- Repeated hard limits and defaults have one canonical detailed owner and do not
  contradict live code or tests.
- Every local documentation link resolves, every Markdown file has the required
  SPDX header, repository guidance checks pass, and the final diff contains no
  whitespace errors.

