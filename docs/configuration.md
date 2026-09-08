<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Configuration reference

Use this reference to check saved defaults, field meanings, and validation.
Open **Settings…** from the menu-bar panel to edit the configuration. Settings
uses the standard macOS window with three labeled tabs and remembers the
last selected tab:

- **General**: Launch at Login and focused Mac context, including Accessibility.
- **Profiles**: assistant identity, trigger, target, shortcut, and reply voice.
- **Speech & Audio**: speech language, wake listening, default reply voice,
  the optional ElevenLabs API key, and activity sounds.

Switching tabs preserves your edits. **Save Settings** applies edits from every
tab; validation errors remain visible beside Save regardless of the active tab.

## When changes take effect

Profile, locale, shortcut, Mac context, and conversation-audio edits take effect
only after **Save Settings** succeeds. A successful save closes Settings and restarts the
affected runtime boundaries. A validation error keeps the window open and shows
the field that needs attention.

**Launch at Login** changes the macOS registration immediately. **Always listen
for wake phrases** also applies immediately. Both controls say so next to the
switch; neither waits for **Save Settings**.

## Voice and application settings

| Setting | Initial value | Behavior |
| --- | --- | --- |
| Always listen | On | Runs passive wake recognition when at least one profile is enabled. |
| Speech language | Current macOS locale | Shows English language and region names, such as English (United States). Selects the Apple Speech recognizer and matching system voice. |
| Read replies aloud | On | Allows profiles set to Inherit to use the app-wide voice. |
| Default reply voice | Automatic macOS voice | Selects the backend and voice inherited by profiles. |
| Agent activity sounds | On | Plays bounded thinking and tool-transition cues. |
| Include Mac context | On | Sends one bounded focused-app snapshot only with admitted ACP requests. Direct commands never receive it. |
| Launch at Login | Off in a fresh macOS registration | Registers the current bundle through Service Management. |

The speech-language picker lists the languages Apple Speech supports. It keeps
the current selection even if that locale is missing from Apple's list.
Names are displayed in English; the underlying locale identifier stays in
preferences and changes only after **Save Settings**. A listed language may
still require downloaded on-device support for passive listening.

Each profile may inherit the default reply voice, disable narration, or select
an explicit macOS or ElevenLabs voice. The selected profile and resolved voice
are pinned when its trigger or shortcut starts a conversation; follow-ups never
switch profiles or voices. ElevenLabs uses one global API key stored in macOS
Keychain, while backend and voice IDs are saved in preferences. See
[Agent conversations](agent-conversations.md) for playback and fallback behavior.

## Wake-profile fields

| Field | Meaning |
| --- | --- |
| Name | User-facing assistant identity shown in the menu and Settings. |
| Icon | A curated or custom SF Symbol name, or one emoji. |
| Enabled | Includes the phrase in passive wake recognition. |
| Trigger phrase | Phrase that must begin a recognized utterance. |
| Target | Direct command or ACP agent. |
| Accent | Color used in menu, capture, and conversation presentation. |
| Push-to-talk | Optional profile-specific global shortcut. |
| Reply voice | Inherit, Off, or one backend-specific voice. |

The initial profile is enabled, blue, and named `Computer`. It opens a Google
search and receives Control-Option-Space during first-run preference migration.
See [Wake profiles](wake-profiles.md) for matching, enablement, shortcuts, and
capture timing.

## Command-target fields

| Field | Meaning |
| --- | --- |
| Executable | Absolute path launched directly with `Foundation.Process`. |
| Argument templates | Ordered arguments; at least one must contain `{text}` or `{urlText}`. |

The initial executable is `/usr/bin/open` and its argument is
`https://www.google.com/search?q={urlText}`. See
[Command targets](command-targets.md) for expansion and examples.

## Agent-target fields

| Field | Meaning |
| --- | --- |
| Provider | Cursor, Codex, Claude, or a custom ACP v1 process. |
| Executable | Detected command or absolute provider-process path. |
| Working folder | Absolute project directory sent during ACP session creation. |
| Permission policy | Ask, scoped allow, or scoped deny behavior. |
| System prompt | Optional bounded instructions saved with the profile. |
| Adapter arguments | Explicit provider-process arguments with no shell parsing. |

The harness name follows the selected provider automatically. Use the profile’s
name to personalize your assistant; there is no separate harness-name field.
Saving older settings replaces a previously edited harness name with the
provider name while retaining its launch configuration.

See [Agent providers](agent-providers.md) for setup, authentication, and prompt
usage. [ACP agent harness](agent-harness.md) owns the exact prompt bound plus the
wire and lifecycle contract.

## Focused Mac context and Accessibility

The **General** tab groups **Launch at Login** and
**Include Mac context**. Context details stay behind
**What your agent receives**; the permission action appears only when needed.

**Ready for Mac context** means capture is enabled and Accessibility is
authorized. **App name only** means the agent can identify the focused app, but
needs Accessibility access for window details and selections. **Mac context is
off** means capture is disabled.
Save Settings to apply a changed toggle.

**Include Mac context** defaults to On. After a successful **Save Settings**,
each admitted ACP request may include a one-shot
snapshot for the app that was frontmost when that utterance was admitted. It is
not a continuous observer and it does not re-read a later selection while a
turn is queued. Turning it off prevents target lookup and native context capture;
the provider receives the normal instruction and request blocks only.

An initial request starts only after an explicit matched wake phrase or a
profile's push-to-talk release. An active ACP conversation may accept its own
follow-ups; YapOps does not continuously observe the foreground app.

The Settings status check and lifecycle refresh only ask macOS whether
Accessibility is already authorized; neither can show a privacy prompt.
**Enable Accessibility…** is the sole Settings action that asks macOS to show
that prompt. Until access is granted, an ACP request still receives the frozen
application name and bundle identifier with
`captureState: "accessibility_not_authorized"` when a target is available.

The snapshot can contain the application, focused window title, document URL,
selected text, and selected resource links. A selected item that exposes only an
absolute filename is converted to a file link; relative or malformed filenames
are omitted. The app does not open the file to build this link.
For selections such as Finder list rows, YapOps looks through the selected
item's structural children to find its file link. It stops at the first link
for each selected item and skips unselected nested rows. This lookup is bounded
to three child levels, 64 elements total, and the capture's 500 ms time budget.
The snapshot does not include screenshots,
clipboard data, file contents, a full Accessibility tree, or background updates.
YapOps neither persists nor logs snapshot values or content; it may
record safe capture metadata. The selected ACP provider receives the prompt
blocks and may retain or replay them under its own session policy; YapOps does not restore an old snapshot after restart.
See [ACP agent harness](agent-harness.md) for the exact schema and bounds.

Each request in the conversation shows a compact summary of its captured app,
window, text selection, and selected items. **No selection** means the app did
not provide selected text or items; permission and timeout messages explain
limited captures. A queued follow-up keeps its own captured context even when
you switch apps before it runs. These summaries describe capture, while the
separate delivery status shows whether the follow-up was queued or submitted.
Summaries stay in memory and do not include selected text, window titles, or
file paths. Restored provider history does not recreate old context summaries.

## Validation summary

A valid saved configuration has:

- at least one profile;
- a phrase containing a spoken letter or number for every profile;
- wake phrases that remain unique after canonical normalization;
- unique physical push-to-talk bindings;
- a command executable with an absolute path and a transcript placeholder; and
- an agent absolute executable, absolute working folder, and bounded system
  prompt; the harness name is supplied automatically.

If shortcut registration fails because another application owns a combination,
YapOps restores the previously saved binding set.

## Persistence and credentials

Profiles, locale, audio choices, provider selection, Voice ID, and agent system
prompts are stored in the app's `UserDefaults` domain. Provider authentication
stays in each provider CLI. The optional ElevenLabs API key is stored only as a
generic password in macOS Keychain.

For ACP profiles, a separate strict schema-1 `UserDefaults` value stores at most
64 profile/session bookmarks and 64 interrupted-work markers. It contains only
profile, session, occurrence, optional turn/provider-task identifiers; a
64-character provider compatibility fingerprint; work state; and bookmark
access ordinals. Opaque identifiers are nonempty and limited to 4 KiB each; the
complete encoded value is limited to 512 KiB. Invalid, unknown-schema,
unknown-field, duplicate, over-limit, or malformed data is quarantined as empty
until an explicit valid mutation replaces it.

The fingerprint includes exactly a version marker, provider preset, executable
path, argument count plus every ordered argument (including empty values),
working folder, and system prompt. Every string is length-prefixed before
SHA-256 hashing; the system prompt has already been trimmed of leading and
trailing whitespace and newlines by configuration validation. Display name and
permission policy are excluded. Wake phrase,
enabled state, icon, accent, shortcut, speech settings, activity sounds, and the
focused-Mac-context preference or captured values are outside the fingerprint.

After a successful Settings application, YapOps resets one profile's
live and durable ACP continuity only when that agent profile is removed, changed
to a direct command, or one of those fingerprint inputs changes. Display,
permission, wake, shortcut, speech, audio, and Mac-context-only edits preserve
the bookmark. Validation, shortcut-registration, and credential-storage failures
happen before reset and preserve existing continuity. Direct-command edits do
not touch agent continuity.

YapOps does not persist conversation prompts, Mac-context snapshot
values or content, agent output, reasoning, raw tool or permission payloads,
audio, or provider credentials. The provider owns actual conversation content
and retention. See
[Privacy and security](privacy-and-security.md) for the complete data and
retention boundary.

## Related guides

- [Getting started](getting-started.md)
- [Wake profiles](wake-profiles.md)
- [Command targets](command-targets.md)
- [Agent providers](agent-providers.md)
- [Privacy and security](privacy-and-security.md)
