// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VoiceActivationApp
@testable import VoiceActivationCore

struct AgentRunPanelInteractionTests {
    private static let childEnvironmentKey =
        "VOICE_ACTIVATION_AGENT_PANEL_INTERACTION_TEST_CHILD"
    private static let testFilter =
        "deleteButton_WhenClicked_EmitsDeleteAction"

    @MainActor @Test
    func deleteButton_WhenClicked_EmitsDeleteAction() async throws {
        guard ProcessInfo.processInfo.environment[Self.childEnvironmentKey] == "1" else {
            try IsolatedAppKitTestProcess.run(
                environmentKey: Self.childEnvironmentKey,
                testFilter: Self.testFilter)
            return
        }

        let runID = UUID()
        let model = AgentRunPanelModel()
        var actions: [AgentRunPanelAction] = []
        model.onAction = { actions.append($0) }
        model.begin(terminalSnapshot(runID: runID))

        let size = AgentRunPanelLayout.preferredExpandedSize
        let panel = AgentRunPanel(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: AgentRunPanelView(model: model))
        panel.orderFront(nil)
        defer {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))

        let point = NSPoint(x: size.width - 248, y: 24)
        let down = try #require(mouseEvent(.leftMouseDown, at: point, in: panel))
        let up = try #require(mouseEvent(.leftMouseUp, at: point, in: panel))
        panel.sendEvent(down)
        panel.sendEvent(up)

        #expect(actions == [.delete(runID: runID)])
    }

    @MainActor
    private func mouseEvent(
        _ type: NSEvent.EventType,
        at point: NSPoint,
        in panel: NSPanel
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: type == .leftMouseDown ? 0 : 0.01,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: type == .leftMouseDown ? 1 : 2,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0)
    }

    @MainActor
    private func terminalSnapshot(runID: UUID) -> AgentRunSnapshot {
        AgentRunSnapshot(
            runID: runID,
            profileID: UUID(),
            accent: .purple,
            prompt: "Do the work",
            providerName: "Codex",
            phase: .completed(.endTurn),
            voiceInput: "",
            output: "Finished",
            timeline: [],
            diagnostics: "",
            plan: [],
            tools: [],
            permissions: [],
            notices: [],
            elapsedSeconds: 1,
            evictedToolCount: 0,
            ignoredToolUpdateCount: 0)
    }
}
