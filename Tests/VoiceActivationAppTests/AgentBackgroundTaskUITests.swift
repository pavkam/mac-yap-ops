// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

struct AgentBackgroundTaskUITests {
    @MainActor @Test
    func minimizeDuringBackground_DoesNotCancelOrActivate() {
        let display = BackgroundTaskPanelDisplaySpy()
        let presenter = AgentRunPanelPresenter(display: display)
        let snapshot = backgroundSnapshot()
        var cancelled = false
        presenter.onCancel = { _ in cancelled = true }
        presenter.begin(snapshot, from: nil)

        display.onAction?(.minimize(runID: snapshot.runID))

        #expect(display.minimized == [snapshot.runID])
        #expect(!cancelled)
    }

    @MainActor @Test
    func closeDelete_AreRejectedWhileBackgroundTaskIsActive() {
        let display = BackgroundTaskPanelDisplaySpy()
        let presenter = AgentRunPanelPresenter(display: display)
        let snapshot = backgroundSnapshot()
        var closed = false
        var deleted = false
        presenter.onClose = { _ in closed = true }
        presenter.onDelete = { _ in deleted = true }
        presenter.begin(snapshot, from: nil)

        display.onAction?(.close(runID: snapshot.runID))
        display.onAction?(.delete(runID: snapshot.runID))

        #expect(!closed)
        #expect(!deleted)
        #expect(display.hidden.isEmpty)
        #expect(display.discarded.isEmpty)
    }

    @Test
    func taskRow_CombinesExactNameAndStateForAccessibility() {
        let task = AgentBackgroundTaskPresentation(
            id: AgentBackgroundTaskID(rawValue: "watch"),
            name: "Watch release build",
            description: "Waiting for CI",
            canStop: true)

        #expect(task.accessibilityLabel == "Watch release build, Working in background")
        #expect(task.offersStopAction)
    }

    @MainActor
    private func backgroundSnapshot() -> AgentRunSnapshot {
        AgentRunSnapshot(
            runID: UUID(),
            profileID: UUID(),
            profileName: "Codex",
            profileIcon: .defaultValue,
            accent: .purple,
            prompt: "Watch the build",
            providerName: "Agent",
            phase: .completed(.endTurn),
            voiceInput: "",
            output: "",
            timeline: [],
            diagnostics: "",
            plan: [],
            tools: [],
            permissions: [],
            notices: [],
            elapsedSeconds: 0,
            evictedToolCount: 0,
            ignoredToolUpdateCount: 0,
            backgroundTasks: [
                AgentBackgroundTaskPresentation(
                    id: AgentBackgroundTaskID(rawValue: "watch"),
                    name: "Watch build",
                    description: "Waiting for CI",
                    canStop: true)
            ])
    }
}

@MainActor
private final class BackgroundTaskPanelDisplaySpy: AgentRunPanelDisplaying {
    var onAction: ((AgentRunPanelAction) -> Void)?
    var hidden: [UUID] = []
    var discarded: [UUID] = []
    var minimized: [UUID] = []

    func begin(_ snapshot: AgentRunSnapshot, from handoff: RecordingOverlayHandoff?) {}
    func update(_ snapshot: AgentRunSnapshot) {}
    func show(runID: UUID) {}
    func hide(runID: UUID) { hidden.append(runID) }
    func discard(runID: UUID) { discarded.append(runID) }
    func shutdown() {}
    func minimize(runID: UUID) { minimized.append(runID) }
    func restore(runID: UUID) {}
}
