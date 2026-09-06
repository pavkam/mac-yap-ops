// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

struct AgentContinuityPromptContextTests {
    @Test func initialization_WhenRestorationStateExists_AllowsEveryStateAndFlag() {
        let states: [AgentContinuityPromptSessionState] = [
            .loaded,
            .resumedWithoutHistory,
            .freshAfterUnavailableBookmark,
            .freshBecauseRestorationUnsupported,
        ]

        for state in states {
            for interrupted in [false, true] {
                let context = AgentContinuityPromptContext(
                    sessionState: state,
                    previousTurnInterrupted: interrupted)
                #expect(context.sessionState == state)
                #expect(context.previousTurnInterrupted == interrupted)
            }
        }
    }

    @Test func previousTurnInterruptedInNormalSession_EncodesHonestNullState() throws {
        let context = AgentContinuityPromptContext
            .previousTurnInterruptedInNormalSession()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        #expect(context.sessionState == nil)
        #expect(context.previousTurnInterrupted)
        let encoded = try encoder.encode(context)
        #expect(String(decoding: encoded, as: UTF8.self) == """
        {"previousTurnInterrupted":true,"schema":"voice-activation.agent-continuity.v1","sessionState":null}
        """)
        #expect(try JSONDecoder().decode(
            AgentContinuityPromptContext.self,
            from: encoded) == context)
    }

    @Test(arguments: [
        """
        {"previousTurnInterrupted":false,"schema":"voice-activation.agent-continuity.v1","sessionState":null}
        """,
        """
        {"previousTurnInterrupted":false,"schema":"voice-activation.agent-continuity.v1"}
        """,
    ])
    func decoding_WhenNormalSessionWasNotInterrupted_RejectsDishonestNull(
        json: String
    ) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                AgentContinuityPromptContext.self,
                from: Data(json.utf8))
        }
    }
}
