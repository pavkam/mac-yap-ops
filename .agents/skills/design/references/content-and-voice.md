<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Content and voice

YapOps writes like a precise engineer who respects your attention. This is the
most distinctive thing about the product and the easiest thing to get wrong.

This page is the contract. Enforcing it across existing copy is project P3 in
`elevated-target.md`; new and changed strings follow it now.

## Voice

- **Declarative, never chatty.** "Wake phrase listening is off." Not "Oops,
  we're not listening right now!"
- **Second person for the user's things; no first person for the app.** "Your
  request is on its way." "Start YapOps when you log in." The app never says "I"
  or "we" — there is no assistant persona, because the assistant is the profile
  you configured, not YapOps.
- **Sentence case everywhere.** Titles, buttons, labels, section headers. The
  only uppercase is the 10pt tracked eyebrow (`PROFILES`, `LISTENING`), and that
  is a typographic treatment applied with `.textCase(.uppercase)`, not
  capitalisation in the string.
- **Title Case only for proper nouns of the system**: "Launch at Login",
  "Speech Recognition", "Privacy & Security", "Add Profile", "Save Settings",
  "Enable Accessibility…". These match macOS's own naming.
- **No exclamation marks. No emoji in UI copy.** Emoji appear only as user
  *data*, through `ProfileIcon.emoji`.

## Shape of a status message

Two-word title plus a one-clause detail. The rhythm is near-inviolable:

| Title | Detail |
| --- | --- |
| Ready | Listening for 3 wake phrases |
| Listening now | Speak your command |
| Running command | Your request is on its way |
| Agent working | You can keep speaking |
| Conversation paused | Microphone off · Resume when ready |
| Stopping turn | Conversation stays open |
| Needs attention | *(the real error string)* |
| No active wake phrases | Enable a profile to start listening |

Note "Needs attention" rather than "Error", and "Paused" rather than "Disabled".
The app describes the state it is in, not a judgement about it.

## Help text states consequence, not syntax

- "Detecting this phrase selects the profile for the entire conversation."
- "Recognition stays on-device. Changes apply immediately."
- "Pinned when this profile starts a conversation."
- "Sent before every spoken request on this profile."
- "Direct commands never receive this context."

Format guidance lives in the placeholder (`computer`, `/usr/bin/open`,
`/absolute/path/to/project`), never in the help line. The one exception is where
format *is* the consequence: "Use {text} for literal speech or {urlText} for
URL-encoded speech."

## Punctuation

**Middle dot joins peer facts on one line.** `"computer" · ^⌥Space · Hold to
talk`, `Paused · Microphone off`, `PDF document · 248 KB`, `4 steps · Show
details`. Never a comma, dash or pipe.

**Curly quotes for spoken phrases.** A wake phrase is always rendered
`“computer”`. This is how the app distinguishes something you *say* from
something it *shows* you. Use `’` for apostrophes too.

## Precision over reassurance

The documentation is unusually exact and the UI inherits it: "up to four live
sessions and 32 task rows per session", "0 / 8 192 bytes". When YapOps cannot
promise something it says so plainly — "process exit is interruption, never proof
that a task survived." Do not soften this.

## Privacy copy names kinds, never content

"Context from Xcode" followed by "Window · Document link · Selected text". The
app tells you *what categories* it captured and never displays the capture
itself. This is a guarantee, not a layout choice.

## Words the product owns

**profile**, **wake phrase** (never "hotword" or "trigger word", though the
Settings field is labelled "Trigger phrase"), **capture** (one recognised
utterance), **conversation** (one retained agent session), **turn** (one request
and its work), **passive wake**, **push to talk**, **target**, **provider**,
**artifact**/**result**, **Mac context**.

`docs/index.md` and `docs/documentation.md` own the definitions. Use the same
word in the UI that the documentation uses; a synonym in a label is a defect.
