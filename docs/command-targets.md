<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
SPDX-License-Identifier: MIT
-->

# Command targets

Use a command target to pass recognized text to an executable as explicit
arguments. Command targets never invoke a shell or interpret speech as shell
syntax.

## Configure a command target

Open Settings, edit a profile, and choose **Command** as its target. Supply:

1. An absolute executable path.
2. An ordered list of argument templates.
3. At least one argument containing `{text}` or `{urlText}`.

Select **Save Settings** to validate and apply the target.

## Expand recognized text

| Placeholder | Expansion |
| --- | --- |
| `{text}` | Inserts the recognized text literally into that one argument. |
| `{urlText}` | Percent-encodes the text as an RFC 3986 query value. |

Expansion does not split the resulting value into more arguments. Spaces,
quotes, semicolons, dollar signs, and other punctuation remain ordinary data
inside the existing argument.

## Open a search URL

The initial profile uses:

```text
Executable: /usr/bin/open
Arguments:
  https://www.google.com/search?q={urlText}
```

Saying `computer local weather` opens a Google query with the recognized text
encoded as one URL value.

## Open a custom URL scheme

Use the same `/usr/bin/open` executable for an application URL scheme:

```text
Wake phrase: ask assistant
Executable:  /usr/bin/open
Arguments:
  my-app://command?prompt={urlText}
```

The destination application decides how to handle the URL after macOS opens it.

## Run another executable

Command targets are not limited to URLs. For example, an executable can receive
literal recognized text as one argument:

```text
Executable: /absolute/path/to/voice-command
Arguments:
  --request
  {text}
```

Use a real absolute path and model every fixed flag or value as a separate row.
There is no quoting layer because there is no shell.

## Validate and diagnose a target

Saving rejects a relative executable or an argument list without a transcript
placeholder. At runtime, the executable must still exist and have execute
permission.

YapOps waits asynchronously for completion. Exit status zero is
success; a non-zero status becomes a visible error. Standard input, output, and
error are attached to the null device, so a command cannot use the app as an
interactive terminal and its own output is not captured.

Test a new executable and its arguments directly before assigning it to a
profile. Runtime lifecycle metadata appears in the diagnostic trace without the
recognized transcript or expanded arguments.

## Security boundary

YapOps creates `Foundation.Process` with the validated executable URL
and expanded argument array. It does not run `/bin/sh`, evaluate substitutions,
expand wildcards, source login files, or reinterpret recognized punctuation.

The destination executable still receives the recognized text and owns what it
does next. Treat custom URL handlers and executables as trusted profile
configuration.

## Related guides

- [Wake profiles](wake-profiles.md)
- [Configuration reference](configuration.md)
- [Privacy and security](privacy-and-security.md)
- [Troubleshooting](troubleshooting.md)
