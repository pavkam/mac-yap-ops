// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

final class PendingAgentInputAdmission: @unchecked Sendable {
    // The lock lets detached runner startup validate the MainActor-owned lease
    // without hopping back to an actor that synchronous speech startup may occupy.
    private let lock = NSLock()
    private let inputID: UUID
    private var runID: UUID?
    private var generation: Int?

    init(inputID: UUID) {
        self.inputID = inputID
    }

    func activate(runID: UUID, generation: Int) {
        lock.lock()
        self.runID = runID
        self.generation = generation
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        runID = nil
        generation = nil
        lock.unlock()
    }

    func matches(inputID: UUID, runID: UUID, generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.inputID == inputID
            && self.runID == runID
            && self.generation == generation
    }
}

struct PendingAgentInput: Sendable {
    let id: UUID
    let text: String
    let contextCapture: Task<MacContextSnapshot?, Never>?
    let admission: PendingAgentInputAdmission

    func activateAdmission(runID: UUID, generation: Int) {
        admission.activate(runID: runID, generation: generation)
    }

    func invalidateAdmission() {
        admission.invalidate()
    }

    func isAdmitted(runID: UUID, generation: Int) -> Bool {
        admission.matches(inputID: id, runID: runID, generation: generation)
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
            admission: PendingAgentInputAdmission(inputID: id))
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
