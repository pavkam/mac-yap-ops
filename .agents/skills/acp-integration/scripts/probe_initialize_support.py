# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

"""Bounded frame, lifecycle, and output helpers for the ACP initialize probe."""

from collections.abc import Callable
import json
import os
import selectors
import signal
import subprocess
import time
from typing import BinaryIO


MAX_FRAME_BYTES = 1_048_576
READ_TIMEOUT_SECONDS = 20.0
READ_CHUNK_BYTES = 65_536


def terminate(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=3)


def read_frame(
    stream: BinaryIO,
    timeout_seconds: float = READ_TIMEOUT_SECONDS,
    clock: Callable[[], float] = time.monotonic,
) -> bytes:
    deadline = clock() + timeout_seconds
    frame = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(stream, selectors.EVENT_READ)
        while True:
            remaining = deadline - clock()
            if remaining <= 0 or not selector.select(timeout=remaining):
                raise RuntimeError("timed out waiting for initialize response")
            chunk = os.read(stream.fileno(), READ_CHUNK_BYTES)
            if not chunk:
                raise RuntimeError(
                    "ACP process closed stdout before newline-delimited "
                    "initialize response")
            newline = chunk.find(b"\n")
            prefix = chunk if newline < 0 else chunk[:newline]
            if len(frame) + len(prefix) > MAX_FRAME_BYTES:
                raise RuntimeError(
                    "initialize response exceeded the 1 MiB frame limit")
            frame.extend(prefix)
            if newline >= 0:
                return bytes(frame)


def _reject_non_json_constant(_: str) -> None:
    raise ValueError


def decode_message(frame: bytes) -> dict[str, object]:
    try:
        text = frame.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise RuntimeError("initialize response was not valid UTF-8") from error
    try:
        message = json.loads(
            text,
            parse_constant=_reject_non_json_constant,
        )
    except (json.JSONDecodeError, ValueError) as error:
        raise RuntimeError("initialize response was not valid JSON") from error
    if not isinstance(message, dict):
        raise RuntimeError("initialize response was not a JSON object")
    return message


def _protocol_shape(result: dict[str, object]) -> object:
    if "protocolVersion" not in result:
        return "absent"
    value = result["protocolVersion"]
    if type(value) is int:
        return 1 if value == 1 else "unsupported"
    return "invalid-shape"


def _load_shape(capabilities: object) -> object:
    if capabilities is None:
        return "absent"
    if not isinstance(capabilities, dict):
        return "invalid-shape"
    value = capabilities.get("loadSession")
    if value is None:
        return "absent"
    return value if type(value) is bool else "invalid-shape"


def _resume_shape(capabilities: object) -> str:
    if capabilities is None:
        return "absent"
    if not isinstance(capabilities, dict):
        return "invalid-shape"
    if "sessionCapabilities" not in capabilities:
        return "absent"
    sessions = capabilities["sessionCapabilities"]
    if sessions is None:
        return "null"
    if not isinstance(sessions, dict):
        return "invalid-shape"
    if "resume" not in sessions:
        return "absent"
    resume = sessions["resume"]
    if resume is None:
        return "null"
    return "object" if isinstance(resume, dict) else "invalid-shape"


def summarize(result: dict[str, object]) -> dict[str, object]:
    capabilities = result.get("agentCapabilities")
    return {
        "protocolVersion": _protocol_shape(result),
        "loadSession": _load_shape(capabilities),
        "resume": _resume_shape(capabilities),
    }
