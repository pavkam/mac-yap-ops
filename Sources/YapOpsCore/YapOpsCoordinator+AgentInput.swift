// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension YapOpsCoordinator {
    func submitAgentFollowUp(_ prompt: String) {
        guard case .agent = executingAction, let runID = activeAgentRunID else {
            diagnostics.record(
                category: .agent,
                event: "coordinator.follow_up_ignored",
                fields: ["reason": "no_active_conversation"])
            return
        }
        guard prompt.utf8.count <= ACPClientConnection.maximumPromptBytes else {
            diagnostics.record(
                category: .agent,
                event: "coordinator.follow_up_rejected",
                level: .warning,
                fields: [
                    "run_id": runID.uuidString,
                    "reason": "prompt_too_large",
                    "byte_count": String(prompt.utf8.count),
                ])
            onAgentRunEvent?(
                .notice(
                    runID: runID,
                    message: "That follow-up is too long. Shorten it and try again."))
            return
        }
        guard pendingAgentPrompts.count < Self.maximumPendingAgentPrompts else {
            diagnostics.record(
                category: .agent,
                event: "coordinator.follow_up_rejected",
                level: .warning,
                fields: [
                    "run_id": runID.uuidString,
                    "reason": "queue_full",
                    "pending_count": String(pendingAgentPrompts.count),
                ])
            onAgentRunEvent?(
                .notice(
                    runID: runID,
                    message: "Follow-up queue is full. Wait for the agent before speaking again."))
            return
        }

        let input = makePendingAgentInput(text: prompt)
        pendingAgentPrompts.append(input)
        diagnostics.record(
            category: .agent,
            event: "coordinator.follow_up_queued",
            fields: [
                "run_id": runID.uuidString,
                "character_count": String(prompt.count),
                "pending_count": String(pendingAgentPrompts.count),
                "turn_active": String(executionTask != nil),
            ])
        onAgentRunEvent?(
            .followUpSubmitted(
                runID: runID,
                inputID: input.id,
                prompt: prompt,
                disposition: .routing))

        if executionTask == nil {
            startNextAgentPrompt()
        } else {
            routeNextAgentInput()
        }
    }

    func routeNextAgentInput() {
        guard
            agentCancellationTask == nil,
            executionTask != nil,
            agentInputRoutingTask == nil,
            steeringBlockedGeneration != executionGeneration,
            let input = pendingAgentPrompts.first,
            case .agent = executingAction,
            let profileID = activeProfile?.id,
            let runID = activeAgentRunID
        else { return }

        let token = UUID()
        let generation = executionGeneration
        let agentRunner = agentRunner
        let scheduler = MainRunLoopScheduler.shared
        agentInputRoutingToken = token
        agentInputRoutingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let context = await input.contextCapture?.value
            guard !Task.isCancelled else { return }
            let prompt = AgentPrompt(request: input.text, context: context)
            do {
                let result = try await agentRunner.offerMidTurnInput(
                    profileID: profileID,
                    prompt: prompt)
                guard !Task.isCancelled else { return }
                await scheduler.perform { [weak self] in
                    self?.finishAgentInputRouting(
                        result,
                        token: token,
                        runID: runID,
                        generation: generation,
                        profileID: profileID,
                        inputID: input.id,
                        contextSummary: .init(context: context))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await scheduler.perform { [weak self] in
                    self?.failAgentInputRouting(
                        token: token,
                        runID: runID,
                        generation: generation,
                        profileID: profileID,
                        inputID: input.id)
                }
            }
        }
    }

    func invalidateAgentInputRouting() {
        agentInputRoutingToken = nil
        agentInputRoutingTask?.cancel()
        agentInputRoutingTask = nil
        steeringBlockedGeneration = nil
    }

    private func finishAgentInputRouting(
        _ result: AgentMidTurnInputResult,
        token: UUID,
        runID: UUID,
        generation: Int,
        profileID: UUID,
        inputID: UUID,
        contextSummary: AgentInputContextSummary
    ) {
        guard ownsAgentInputRouting(
            token: token,
            runID: runID,
            generation: generation,
            profileID: profileID,
            inputID: inputID)
        else { return }

        agentInputRoutingTask = nil
        agentInputRoutingToken = nil
        switch result {
        case .injected:
            pendingAgentPrompts.removeFirst()
            onAgentRunEvent?(
                .followUpDispositionChanged(
                    runID: runID,
                    inputID: inputID,
                    disposition: .injected))
            if executionTask == nil {
                startNextAgentPrompt()
            } else {
                routeNextAgentInput()
            }
        case .promptRequired:
            steeringBlockedGeneration = generation
            onAgentRunEvent?(
                .followUpDispositionChanged(
                    runID: runID,
                    inputID: inputID,
                    disposition: .queued))
            if executionTask == nil {
                steeringBlockedGeneration = nil
                startNextAgentPrompt()
            }
        }
        guard activeAgentRunID == runID else { return }
        onAgentRunEvent?(.inputContextCaptured(
            runID: runID, inputID: inputID, summary: contextSummary))
    }

    private func failAgentInputRouting(
        token: UUID,
        runID: UUID,
        generation: Int,
        profileID: UUID,
        inputID: UUID
    ) {
        guard ownsAgentInputRouting(
            token: token,
            runID: runID,
            generation: generation,
            profileID: profileID,
            inputID: inputID)
        else { return }

        agentInputRoutingTask = nil
        agentInputRoutingToken = nil
        steeringBlockedGeneration = generation
        pendingAgentPrompts.removeFirst()
        onAgentRunEvent?(
            .followUpDispositionChanged(
                runID: runID,
                inputID: inputID,
                disposition: .failed))
        onAgentRunEvent?(
            .notice(
                runID: runID,
                message: "Delivery failed — say it again."))
        if executionTask == nil {
            steeringBlockedGeneration = nil
            startNextAgentPrompt()
        }
    }

    private func ownsAgentInputRouting(
        token: UUID,
        runID: UUID,
        generation: Int,
        profileID: UUID,
        inputID: UUID
    ) -> Bool {
        agentInputRoutingToken == token
            && activeAgentRunID == runID
            && executionGeneration == generation
            && activeProfile?.id == profileID
            && pendingAgentPrompts.first?.id == inputID
    }
}
