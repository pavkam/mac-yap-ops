#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

"""Deterministic process-group ownership tests for the ACP probe."""

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("probe-initialize.py")
SPEC = importlib.util.spec_from_file_location("probe_initialize", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class ProbeProcessGroupTests(unittest.TestCase):
    def test_signal_group_ignores_permission_when_nothing_is_signalable(self) -> None:
        process = subprocess.Popen(["/usr/bin/true"])
        try:
            with mock.patch(
                "probe_process_group.os.killpg",
                side_effect=PermissionError,
            ):
                probe.terminate(process)
        finally:
            process.wait()

    def test_terminate_kills_descendant_when_leader_exits_on_term(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pid_path = Path(directory) / "descendant.pid"
            sentinel = Path(directory) / "survived"
            descendant = (
                "import os,pathlib,signal,sys,time;"
                "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                "pathlib.Path(sys.argv[1]).write_text(str(os.getpid()));"
                "time.sleep(0.5);pathlib.Path(sys.argv[2]).write_text('bad');"
                "time.sleep(30)"
            )
            leader = "\n".join((
                "import pathlib,subprocess,sys,time",
                f"descendant = {descendant!r}",
                "subprocess.Popen([sys.executable, '-c', descendant, "
                "sys.argv[1], sys.argv[2]])",
                "pid_path = pathlib.Path(sys.argv[1])",
                "while not pid_path.exists(): time.sleep(0.001)",
                "time.sleep(30)",
            ))
            process = subprocess.Popen(
                [sys.executable, "-c", leader, str(pid_path), str(sentinel)],
                start_new_session=True,
            )
            descendant_pid = None
            try:
                deadline = time.monotonic() + 2
                while not pid_path.exists() and time.monotonic() < deadline:
                    time.sleep(0.001)
                descendant_pid = int(pid_path.read_text())
                probe.terminate(process)
                time.sleep(0.6)
                self.assertFalse(sentinel.exists())
                with self.assertRaises(ProcessLookupError):
                    os.kill(descendant_pid, 0)
                probe.terminate(process)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                if descendant_pid is not None:
                    try:
                        os.kill(descendant_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1)


if __name__ == "__main__":
    unittest.main()
