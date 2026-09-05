<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Getting started

Build Voice Activation, grant its macOS permissions, and run the default voice
command. This is the shortest path from a clone to a working menu-bar app.

## Requirements

- macOS 15 or later
- Swift 6.2 or later
- Xcode Command Line Tools or Xcode

Confirm the active toolchain:

```bash
swift --version
xcodebuild -version
```

## Clone and verify

```bash
git clone https://github.com/pavkam/mac-voice-activation.git
cd mac-voice-activation
make test
make app
```

The packaged application is written to `.build/VoiceActivation.app`. Launch it
with:

```bash
open .build/VoiceActivation.app
```

Voice Activation has no Dock icon. Its status icon appears on the right side of
the menu bar.

## Grant permissions

The first voice action requests two macOS privacy permissions:

1. Microphone access, to capture audio.
2. Speech Recognition access, to transcribe audio.

Both are required. If either request is denied, enable Voice Activation in the
corresponding **Privacy & Security** section of System Settings, quit the app,
and launch it again.

## Run the first command

The initial profile opens a Google search:

1. Wait until the menu status says **Ready**.
2. Say `computer`.
3. When the recording overlay appears, speak a search query.
4. Stop speaking and wait for the query to open in your browser.

The overlay shows the newest recognized words without taking focus from the
current app. A rising cue confirms that capture started; a descending cue marks
the end of capture.

To discard the current capture, select its close button, choose **Cancel
Recording** from the menu, or say only `cancel`, `stop`, or `dismiss`.

## Try push-to-talk

The first profile starts with Control-Option-Space. Hold the shortcut, speak
without the wake phrase, and release it to submit through that profile. Saved
shortcuts appear next to their profiles in the menu.

See [Wake profiles](wake-profiles.md) to change wake phrases, shortcuts, and
capture behavior.

## Use a stable development build

`make app` uses an ad-hoc signature by default. macOS may ask for privacy access
again when that executable changes. For regular use, sign with an installed
development identity and move the resulting app to `/Applications`:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app
```

See [Packaging](packaging.md) for bundle, signing, verification, installation,
and Launch at Login details.

## Start a local coding agent

Install and authenticate a supported Agent Client Protocol (ACP) provider, then
change a profile's **Target** to **Agent** in Settings. Choose the provider,
confirm its executable and working folder, select a permission policy, and save.

The first agent request opens a non-activating conversation panel and keeps the
microphone available for follow-ups. Continue with
[Agent providers](agent-providers.md) for setup and
[Agent conversations](agent-conversations.md) for the interaction model.

## Related guides

- [Configuration reference](configuration.md)
- [Wake profiles](wake-profiles.md)
- [Command targets](command-targets.md)
- [Troubleshooting](troubleshooting.md)
