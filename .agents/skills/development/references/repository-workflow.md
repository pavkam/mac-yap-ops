<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Repository workflow

## Before editing

1. Run `git status --short`; inspect overlapping diffs and preserve user work.
2. Read the affected production type, focused tests, and the relevant guide.
3. Search with `rg` before inventing a helper, abstraction, or setting.
4. Identify the owning module/actor and trace the state or callback end to end.
5. Define observable success and failure. For behavior, write and run the
   smallest failing test before production code.

This is SwiftPM, not an Xcode-project repository. Do not create or commit an
`.xcodeproj`. Change `Package.resolved` only when dependencies actually change.

## Repository files

Every source, test, script, configuration, and Markdown file needs the MIT SPDX
header in its first 12 lines. Non-commentable binary resources are declared in
`REUSE.toml`.

Update the owning guide when behavior, configuration, privacy, diagnostics,
packaging, tests, or developer commands change. The canonical topic-to-guide
map and evidence rules live in `docs/documentation.md`; do not duplicate that
map in agent guidance.

## Commands

```bash
make build                 # Debug SwiftPM build
make test                  # Full suite
CONFIGURATION=debug make app
make check                 # SPDX, guidance, Swift size, public DocC
git diff --check
```

Use `swift test list | rg '<name>'` before guessing a filter. `swift run` is not
evidence for bundle resources, `Info.plist`, signing, Keychain identity, Service
Management, or privacy grants.

For completion checks, use `testing-and-debugging`; its matrix
selects full tests, app packaging, sanitizers, and manual flows by risk.

## Scope discipline

- Prefer the smallest coherent patch. Keep unrelated renames, formatting, and
  dependency updates out.
- Preserve four-space Swift formatting; no broad formatter is configured.
- Add a protocol only for a real substitution boundary. Add a file only for a
  focused responsibility.
- A command not run is not a pass. Report skipped manual or environment-bound
  checks explicitly.
