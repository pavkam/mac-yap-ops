<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Packaging

Voice Activation is a SwiftPM executable assembled into a macOS application
bundle by `scripts/build-app.sh`. Use the bundle for resources, signing,
permissions, Keychain identity, Service Management, and normal menu-bar
lifecycle; `swift run` does not exercise those boundaries.

## Build the app bundle

```bash
make app
```

The script builds the `VoiceActivation` product, replaces the previous bundle,
copies the required metadata and resources, signs it, and verifies the result.
The output is:

```text
.build/VoiceActivation.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/VoiceActivation
    └── Resources/
        ├── VoiceActivation.icns
        ├── AgentThinking.wav
        ├── CaptureStart.wav
        ├── CaptureEnd.wav
        ├── ToolStart.wav
        ├── ToolComplete.wav
        └── ToolFailed.wav
```

## Choose a configuration

`CONFIGURATION` is passed to `swift build -c` and defaults to `release`. Use a
debug executable when attaching a debugger or iterating on a bundled manual
flow:

```bash
CONFIGURATION=debug make app
```

Changing configuration replaces the same `.build/VoiceActivation.app` output.

## Include required resources

`Package.swift` excludes the plist, icon, and sound files from SwiftPM resource
handling because the packaging script places them at their macOS bundle paths.
When adding or renaming a required resource, update all of these together:

- `Package.swift` exclusions;
- `scripts/build-app.sh` copy operations;
- `REUSE.toml` for non-commentable binary files; and
- the CI bundle assertions in `.github/workflows/swift.yml`.

The checked-in `Info.plist` owns the bundle identifier, version, menu-bar agent
mode, minimum macOS version, icon, and privacy usage descriptions.

## Sign the bundle

`SIGN_IDENTITY` defaults to `-`, which creates an ad-hoc signature suitable for
CI and short-lived development builds:

```bash
make app
```

For repeated privacy, Keychain, or Launch at Login testing, use an installed
identity so the application identity remains stable:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app
```

Signing is applied with `codesign --force --deep`. The repository does not
create an Xcode project or archive, notarize the app, or produce a distribution
installer.

## Verify the bundle

The packaging script always runs plist and signature verification. These are
the direct checks used when diagnosing a bundle:

```bash
test -x .build/VoiceActivation.app/Contents/MacOS/VoiceActivation
plutil -lint .build/VoiceActivation.app/Contents/Info.plist
codesign --verify --deep --strict .build/VoiceActivation.app
codesign --display --verbose=4 .build/VoiceActivation.app
```

Also confirm the icon and all six sound files exist under `Contents/Resources`
when a resource changed.

## Install a stable development copy

Quit an existing Voice Activation process, replace the copy under
`/Applications`, and always launch that same path when testing permissions or
login registration:

```bash
ditto .build/VoiceActivation.app /Applications/VoiceActivation.app
open /Applications/VoiceActivation.app
```

The default ad-hoc signature can still cause macOS to request privacy access
again after an executable rebuild. A stable development signature plus a stable
installation path provides the predictable identity needed for repeated manual
testing.

## Enable Launch at Login

Launch at Login uses `SMAppService.mainApp`; macOS is the source of truth for its
registration and approval status. Run the installed `/Applications` copy before
enabling it in Settings. If approval is required, allow Voice Activation under
**System Settings > General > Login Items**, then retry the toggle.

Do not register the temporary bundle under `.build`. Unit tests inject a fake
service and never modify the real login-item database.

## Store the optional narration key

Automated local provisioning may pass exactly one ElevenLabs key through
standard input to the signed application executable. The process stores it in
Keychain under that bundle identity and exits before creating the menu-bar UI:

```bash
read -r -s narration_key
printf '%s\n' "$narration_key" | \
  /Applications/VoiceActivation.app/Contents/MacOS/VoiceActivation \
  --store-elevenlabs-key-from-stdin
unset narration_key
```

Never put the key in a command-line argument, environment variable, fixture,
preferences file, diagnostic record, or repository file. Interactive users can
save it through Settings instead.

## CI packaging

The `📦 Package app` job runs only after repository quality, build-and-test, and
Thread Sanitizer jobs succeed. It calls `make app`, then verifies the executable,
icon, capture sounds, `Info.plist`, and code signature. CI's ad-hoc signature
proves bundle integrity, not distribution readiness or notarization.

## Related guides

- [Getting started](getting-started.md)
- [Development](development.md)
- [Testing](testing.md)
- [Configuration reference](configuration.md)
- [Troubleshooting](troubleshooting.md)
