# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

"""Process-group cleanup for the ACP initialize probe."""

import os
import signal
import subprocess
import time


TERMINATION_GRACE_SECONDS = 0.2
TERMINATION_POLL_SECONDS = 0.01


def _group_exists(process_group_id: int) -> bool:
    try:
        os.killpg(process_group_id, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _signal_group(process_group_id: int, requested_signal: signal.Signals) -> None:
    try:
        os.killpg(process_group_id, requested_signal)
    except (ProcessLookupError, PermissionError):
        pass


def terminate(
    process: subprocess.Popen[bytes],
    process_group_id: int | None = None,
) -> None:
    owned_group = process.pid if process_group_id is None else process_group_id
    _signal_group(owned_group, signal.SIGTERM)
    deadline = time.monotonic() + TERMINATION_GRACE_SECONDS
    while _group_exists(owned_group):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            _signal_group(owned_group, signal.SIGKILL)
            break
        time.sleep(min(TERMINATION_POLL_SECONDS, remaining))
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)
