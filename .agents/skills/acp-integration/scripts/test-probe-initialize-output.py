#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

"""Privacy-shape tests for initialize-probe output."""

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("probe-initialize.py")
SPEC = importlib.util.spec_from_file_location("probe_initialize", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class ProbeInitializeOutputTests(unittest.TestCase):
    def test_summary_reports_only_bounded_restoration_shapes(self) -> None:
        cases = [
            ({}, {"loadSession": "absent", "resume": "absent"}),
            ({"loadSession": None},
             {"loadSession": "absent", "resume": "absent"}),
            ({"loadSession": True},
             {"loadSession": True, "resume": "absent"}),
            ({"loadSession": False},
             {"loadSession": False, "resume": "absent"}),
            ({"loadSession": "secret"},
             {"loadSession": "invalid-shape", "resume": "absent"}),
            ({"sessionCapabilities": None},
             {"loadSession": "absent", "resume": "null"}),
            ({"sessionCapabilities": {}},
             {"loadSession": "absent", "resume": "absent"}),
            ({"sessionCapabilities": {"resume": None}},
             {"loadSession": "absent", "resume": "null"}),
            ({"sessionCapabilities": {"resume": {"secret": "ignored"}}},
             {"loadSession": "absent", "resume": "object"}),
            ({"sessionCapabilities": {"resume": "secret"}},
             {"loadSession": "absent", "resume": "invalid-shape"}),
            ({"sessionCapabilities": "secret"},
             {"loadSession": "absent", "resume": "invalid-shape"}),
        ]
        for capabilities, expected in cases:
            result = {
                "protocolVersion": 1,
                "agentCapabilities": capabilities,
                "agentInfo": {"name": "secret"},
                "authMethods": [{"name": "secret"}],
                "sessionId": "secret",
            }
            self.assertEqual(
                probe.summarize(result),
                {"protocolVersion": 1, **expected},
            )

    def test_summary_bounds_invalid_protocol_selection(self) -> None:
        self.assertEqual(
            probe.summarize({"protocolVersion": "secret"}),
            {"protocolVersion": "invalid-shape", "loadSession": "absent",
             "resume": "absent"},
        )


if __name__ == "__main__":
    unittest.main()
