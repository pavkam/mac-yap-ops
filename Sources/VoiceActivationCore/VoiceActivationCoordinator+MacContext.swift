// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

struct PendingAgentInput: Sendable {
    let id: UUID
    let text: String
    let contextCapture: Task<MacContextSnapshot?, Never>?
    let admission: AgentRunAdmission

    func bindAdmission(runID: UUID, executionGeneration: Int) -> Bool {
        admission.bind(
            inputID: id,
            runID: runID,
            executionGeneration: executionGeneration)
    }

    func invalidateAdmission() {
        admission.invalidate()
    }

    func cancelContextCapture() {
        contextCapture?.cancel()
    }
}

extension VoiceActivationCoordinator {
    func makePendingAgentInput(text: String) -> PendingAgentInput {
        let id = UUID()
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
            id: id,
            text: text,
            contextCapture: contextCapture,
            admission: AgentRunAdmission(inputID: id))
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
        let input = activeAgentInput
        activeAgentInput = nil
        input?.invalidateAdmission()
        input?.cancelContextCapture()
    }

    func cancelPendingAgentInputs() {
        let inputs = pendingAgentPrompts
        pendingAgentPrompts.removeAll()
        for input in inputs {
            input.cancelContextCapture()
        }
    }

    func cancelAllAgentInputs() {
        let activeInput = activeAgentInput
        let pendingInputs = pendingAgentPrompts
        activeAgentInput = nil
        pendingAgentPrompts.removeAll()
        activeInput?.invalidateAdmission()
        activeInput?.cancelContextCapture()
        for input in pendingInputs {
            input.cancelContextCapture()
        }
    }
}
