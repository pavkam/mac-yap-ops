<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Diagnostics

Voice Activation writes one bounded, structured JSONL trace for application,
settings, UI, hot-key, recognition, command, ACP, agent, audio, and network
events. Start here when the visible error does not identify the failing boundary.

## Find the trace

The active file is:

```text
~/Library/Logs/VoiceActivation/voice-activation.jsonl
```

It rotates before the next entry would take it beyond 5 MiB. The three previous
files remain beside it as `.1`, `.2`, and `.3`.

Follow new entries:

```bash
voice_log_path="$HOME/Library/Logs/VoiceActivation/voice-activation.jsonl"
tail -f "$voice_log_path" | jq .
```

Show warnings and errors:

```bash
jq 'select(.level == "warning" or .level == "error")' "$voice_log_path"
```

## Understand an entry

Every record contains:

- `schema_version`, currently `1`;
- wall-clock `timestamp`, monotonic `uptime_ms`, and `session_elapsed_ms`;
- process-local `session_id` and increasing `sequence`;
- `process_id` and whether the caller was on `main_thread`;
- `category`, stable `event`, and `level`; and
- a string-to-string `fields` object with bounded operational metadata.

Event names are capped at 160 characters, field keys at 120 characters, and
field values at 512 characters on one line. Use `session_id` plus `sequence` for
ordering within one launch. Wall-clock time is useful for correlating the app
with another process, not for measuring a duration.

## Narrow before reading

List event counts by category:

```bash
jq -s 'group_by(.category) | map({category: .[0].category, count: length})' \
  "$voice_log_path"
```

Trace one application launch:

```bash
jq 'select(.session_id == "SESSION-ID") |
  {sequence, session_elapsed_ms, category, event, level, fields}' \
  "$voice_log_path"
```

Trace one agent run:

```bash
jq 'select(.fields.run_id == "RUN-ID") |
  {sequence, session_elapsed_ms, category, event, level, fields}' \
  "$voice_log_path"
```

Preserve any `run_id`, profile ID, ACP session/request ID, turn token, command
run ID, or generation while following an operation across categories. IDs from
different launches are not interchangeable.

## Locate a stall or delay

Find the first `started`, `requested`, or `queued` event without its matching
finished, failed, rejected, cancelled, or disposed outcome. That identifies the
boundary to inspect; it does not prove why that boundary stopped.

Where present, compare:

- `queue_delay_ms` for time waiting on an owned queue;
- `duration_ms` or `operation_duration_ms` for the measured operation;
- `main_delivery_ms` for delivery back to UI or audio state;
- `run_loop_mode` for the AppKit mode receiving that delivery; and
- `task_priority` for the originating Swift task.

For late output, follow the same run across provider transport, bounded event
delivery, main-run-loop presentation, narration synthesis, and playback. For a
recognition failure, compare session generation, mode, audio-configuration
changes, and the terminal recognition event.

## Protect sensitive data

Production events must not include prompts, transcripts, response text, API
keys, authorization, credentials, raw provider content, request or response
bodies, or audio. Field names containing `api_key`, `authorization`, `content`,
`credential`, `prompt`, `secret`, `text`, `token`, or `transcript` are replaced
with `<redacted>` before writing.

Redaction by field name is only a final guardrail. The trace can still contain
configured executable paths, working folders, provider names, locale IDs,
process IDs, and stable correlation IDs. Before sharing a trace:

1. Copy only the relevant session or run into a new file.
2. Review every remaining field for usernames, project names, and local paths.
3. Remove unrelated identifiers and events.
4. Never paste an unreviewed active or rotated log into chat, an issue, or a
   test fixture.

If the recorder cannot initialize, startup writes one bounded failure to
standard error. Production code otherwise has no parallel `print`, `NSLog`, or
`Logger` stream to reconcile.

## Related guides

- [Troubleshooting](troubleshooting.md)
- [Privacy and security](privacy-and-security.md)
- [Architecture](architecture.md)
- [Concurrency and lifecycle](concurrency-and-lifecycle.md)
- [Testing](testing.md)
