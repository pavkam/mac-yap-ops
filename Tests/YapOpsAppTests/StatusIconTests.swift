// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
import YapOpsCore
@testable import YapOpsApp

struct StatusIconTests {
    @Test(arguments: [
        (ActivationState.disabled, "mic.slash"),
        (ActivationState.listening, "ear"),
        (ActivationState.capturing, "waveform"),
        (ActivationState.executing, "bolt.fill"),
        (ActivationState.failed("no mic"), "exclamationmark.triangle.fill"),
    ])
    func symbol_WhenStateChanges_CommunicatesState(
        state: ActivationState,
        expected: String)
    {
        #expect(StatusIcon.symbol(for: state) == expected)
    }
}
