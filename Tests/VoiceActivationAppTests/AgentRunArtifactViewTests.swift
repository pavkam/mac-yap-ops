// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI
import Testing
import VoiceActivationCore
@testable import VoiceActivationApp

struct AgentRunArtifactViewTests {
    @MainActor @Test
    func results_WhenRendered_RemainVisibleWithMacOSAccessibilityAppearances() throws {
        let model = AgentRunPanelModel()
        model.begin(snapshotWithImageAndPDF())

        let normal = ImageRenderer(content: AgentRunPanelView(model: model))
        normal.proposedSize = ProposedViewSize(width: 680, height: 560)
        let opaque = ImageRenderer(
            content: AgentRunPanelView(model: model)
                .environment(\._accessibilityReduceTransparency, true))
        opaque.proposedSize = ProposedViewSize(width: 680, height: 560)
        let highContrast = ImageRenderer(
            content: AgentRunPanelView(model: model)
                .environment(\._colorSchemeContrast, .increased))
        highContrast.proposedSize = ProposedViewSize(width: 680, height: 560)

        #expect(normal.cgImage != nil)
        #expect(opaque.cgImage != nil)
        #expect(highContrast.cgImage != nil)
    }

    @MainActor
    private func snapshotWithImageAndPDF() -> AgentRunSnapshot {
        let imageData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let artifacts = [
            AgentArtifactPresentation(
                id: UUID(),
                artifact: AgentArtifact(
                    uri: nil,
                    name: "preview.png",
                    title: "Generated preview",
                    descriptiveText: "A generated image",
                    mimeType: "image/png",
                    declaredSize: UInt64(imageData.count),
                    payload: .image(data: imageData, mimeType: "image/png"))),
            AgentArtifactPresentation(
                id: UUID(),
                artifact: AgentArtifact(
                    uri: "https://example.com/report.pdf",
                    name: "report.pdf",
                    title: "Final report",
                    descriptiveText: nil,
                    mimeType: "application/pdf",
                    declaredSize: 42_000,
                    payload: .linked)),
        ]
        return AgentRunSnapshot(
            runID: UUID(),
            profileID: UUID(),
            accent: .blue,
            prompt: "Create a preview and report",
            providerName: "Codex",
            phase: .completed(.endTurn),
            voiceInput: "",
            output: "Your files are ready.",
            timeline: [],
            diagnostics: "",
            plan: [],
            tools: [],
            permissions: [],
            notices: [],
            elapsedSeconds: 3,
            evictedToolCount: 0,
            ignoredToolUpdateCount: 0,
            artifacts: artifacts)
    }
}
