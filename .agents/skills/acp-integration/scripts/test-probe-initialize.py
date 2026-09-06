#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

"""Deterministic framing and process-lifecycle tests for the ACP probe."""

import importlib.util
import os
from pathlib import Path
import threading
import unittest
SCRIPT = Path(__file__).with_name("probe-initialize.py")
SPEC = importlib.util.spec_from_file_location("probe_initialize", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)

class ProbeInitializeFrameTests(unittest.TestCase):
    def test_no_bytes_times_out(self) -> None:
        read_fd, write_fd = os.pipe()
        try:
            with os.fdopen(read_fd, "rb", buffering=0) as stream:
                with self.assertRaisesRegex(RuntimeError, "timed out"):
                    probe.read_frame(stream, timeout_seconds=0.01)
        finally:
            os.close(write_fd)
    def test_one_byte_then_stall_times_out(self) -> None:
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b"{")
        try:
            with os.fdopen(read_fd, "rb", buffering=0) as stream:
                with self.assertRaisesRegex(RuntimeError, "timed out"):
                    probe.read_frame(stream, timeout_seconds=0.01)
        finally:
            os.close(write_fd)
    def test_frame_over_one_mib_without_newline_fails(self) -> None:
        read_fd, write_fd = os.pipe()

        def write_oversized_frame() -> None:
            remaining = probe.MAX_FRAME_BYTES + 1
            try:
                while remaining:
                    count = os.write(write_fd, b"x" * min(65_536, remaining))
                    remaining -= count
            except BrokenPipeError:
                pass
            finally:
                os.close(write_fd)

        writer = threading.Thread(target=write_oversized_frame)
        writer.start()
        with os.fdopen(read_fd, "rb", buffering=0) as stream:
            with self.assertRaisesRegex(RuntimeError, "exceeded the 1 MiB"):
                probe.read_frame(stream, timeout_seconds=1)
        writer.join(timeout=1)
        self.assertFalse(writer.is_alive())
    def test_eof_before_newline_fails(self) -> None:
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b"{}")
        os.close(write_fd)
        with os.fdopen(read_fd, "rb", buffering=0) as stream:
            with self.assertRaisesRegex(RuntimeError, "before newline"):
                probe.read_frame(stream, timeout_seconds=1)
    def test_bounded_valid_frame_is_returned(self) -> None:
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b'{"id":1}\n')
        os.close(write_fd)
        with os.fdopen(read_fd, "rb", buffering=0) as stream:
            self.assertEqual(
                probe.read_frame(stream, timeout_seconds=1), b'{"id":1}')
    def test_bytes_after_first_frame_are_ignored(self) -> None:
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b'{}\n{"secret":"ignored"}\n')
        os.close(write_fd)
        with os.fdopen(read_fd, "rb", buffering=0) as stream:
            self.assertEqual(probe.read_frame(stream, timeout_seconds=1), b"{}")
    def test_malformed_utf8_and_json_are_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "valid UTF-8"):
            probe.decode_message(b"\xff")
        with self.assertRaisesRegex(RuntimeError, "valid JSON"):
            probe.decode_message(b"{")
        with self.assertRaisesRegex(RuntimeError, "valid JSON"):
            probe.decode_message(b'{"value":NaN}')

if __name__ == "__main__":
    unittest.main()
