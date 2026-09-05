// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

struct PendingAgentInput: Sendable {
    let id: UUID
    let text: String
    let contextCapture: Task<MacContextSnapshot?, Never>?

    func cancelContextCapture() {
        contextCapture?.cancel()
    }
}

extension VoiceActivationCoordinator {
    func makePendingAgentInput(text: String) -> PendingAgentInput {
        let contextCapture: Task<MacContextSnapshot?, Never>?
        if let target = macContextCapturer.currentTarget() {
            let capturer = macContextCapturer
            contextCapture = Task { @MainActor in
                guard !Task.isCancelled else { return nil }
                let snapshot = await capturer.capture(target)
                guard !Task.isCancelled else { return nil }
                return snapshot
            }
        } else {
            contextCapture = nil
        }
        return PendingAgentInput(
            id: UUID(),
            text: text,
            contextCapture: contextCapture)
    }

    func resolveAgentPrompt(
        input: PendingAgentInput,
        runID: UUID,
        generation: Int
    ) async -> AgentPrompt? {
        let context = await input.contextCapture?.value
        guard
            !Task.isCancelled,
            executionGeneration == generation,
            activeAgentRunID == runID,
            activeAgentInput?.id == input.id
        else { return nil }
        return AgentPrompt(request: input.text, context: context)
    }

    func cancelActiveAgentInput() {
        activeAgentInput?.cancelContextCapture()
        activeAgentInput = nil
    }

    func cancelPendingAgentInputs() {
        for input in pendingAgentPrompts {
            input.cancelContextCapture()
        }
        pendingAgentPrompts.removeAll()
    }

    func cancelAllAgentInputs() {
        cancelActiveAgentInput()
        cancelPendingAgentInputs()
    }
}
