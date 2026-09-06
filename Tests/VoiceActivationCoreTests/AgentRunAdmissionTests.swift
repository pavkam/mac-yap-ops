// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

@Suite struct AgentRunAdmissionTests {
    @Test func invalidate_WhenAdmissionIsPending_PreventsClaim() {
        let admission = AgentRunAdmission()

        #expect(admission.invalidate())
        #expect(!admission.claim())
    }

    @Test func invalidate_WhenClaimAlreadyWon_PreservesClaimedOutcome() {
        let admission = AgentRunAdmission()

        #expect(admission.claim())
        #expect(!admission.invalidate())
    }

    @Test func claim_WhenCalledTwice_RejectsSecondClaim() {
        let admission = AgentRunAdmission()

        #expect(admission.claim())
        #expect(!admission.claim())
    }

    @Test func runner_WhenAdmissionWasInvalidated_CreatesNoTransport() async throws {
        let factory = RunnerTransportFactory(transports: [])
        let runner = ACPAgentRunner(transportFactory: factory)
        let admission = AgentRunAdmission()
        let configuration = try AgentHarnessConfiguration(
            preset: .codex,
            displayName: "Configured Agent",
            executablePath: "/usr/bin/agent",
            arguments: ["acp"],
            workingDirectory: "/tmp/project",
            permissionPolicy: .ask)
        admission.invalidate()

        await #expect(throws: CancellationError.self) {
            try await runner.run(
                admission: admission,
                profileID: UUID(),
                configuration: configuration,
                prompt: AgentPrompt(request: "First", context: nil),
                onEvent: { _ in })
        }
        #expect(await factory.createdConfigurations().isEmpty)
    }
}
