#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

"""Send one initialize request to an ACP process and print bounded metadata."""

import json
import subprocess
import sys

from probe_initialize_support import (
    MAX_FRAME_BYTES,
    decode_message,
    read_frame,
    summarize,
    terminate,
)


def main(command: list[str]) -> None:
    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": 1,
            "clientCapabilities": {},
            "clientInfo": {
                "name": "voice-activation-compatibility-probe",
                "title": "Voice Activation compatibility probe",
                "version": "1",
            },
        },
    }
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        assert process.stdin is not None
        assert process.stdout is not None
        encoded_request = (
            json.dumps(request, separators=(",", ":")) + "\n"
        ).encode("utf-8")
        process.stdin.write(encoded_request)
        process.stdin.flush()
        message = decode_message(read_frame(process.stdout))
        if message.get("id") != 1:
            raise RuntimeError("first response did not preserve request id 1")
        if "error" in message:
            raise RuntimeError("initialize returned a JSON-RPC error")
        result = message.get("result")
        if not isinstance(result, dict):
            raise RuntimeError("initialize result was not an object")
        print(json.dumps(summarize(result), indent=2, sort_keys=True))
    finally:
        terminate(process)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: probe-initialize.py COMMAND [ARG ...]")
    try:
        main(sys.argv[1:])
    except RuntimeError as error:
        print(f"probe failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
