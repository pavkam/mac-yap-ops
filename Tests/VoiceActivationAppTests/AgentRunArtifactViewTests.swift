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

    @MainActor @Test
    func thinking_WhenToolHasRetainedContent_RendersTheContentInExpandedDetails() throws {
        let withoutContent = renderedThinking(content: [])
        let withContent = renderedThinking(content: ["Generated **report.pdf** successfully."])

        #expect(withContent != withoutContent)
    }

    @MainActor
    private func renderedThinking(content: [String]) -> Data? {
        let model = AgentRunPanelModel()
        let thinkingID = UUID()
        model.begin(snapshotWithToolContent(thinkingID: thinkingID, content: content))
        model.toggleThinkingDetails(thinkingID: thinkingID)
        guard case let .thinking(thinking)? = model.snapshot?.timeline.first else { return nil }
        let panelView = AgentRunPanelView(model: model)
        let renderer = ImageRenderer(content: panelView.thinkingCard(thinking))
        renderer.proposedSize = ProposedViewSize(width: 600, height: nil)
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @MainActor
    private func snapshotWithToolContent(
        thinkingID: UUID,
        content: [String]
    ) -> AgentRunSnapshot {
        let tool = AgentToolPresentation(
            id: "tool-1",
            title: "Create report",
            kind: .other,
            status: .completed,
            content: content,
            isSettled: true)
        return AgentRunSnapshot(
            runID: UUID(),
            profileID: UUID(),
            profileName: "Computer",
            profileIcon: .defaultValue,
            accent: .blue,
            prompt: "Create a report",
            providerName: "Codex",
            phase: .completed(.endTurn),
            voiceInput: "",
            output: "",
            timeline: [.thinking(AgentThinkingPresentation(
                id: thinkingID,
                details: [.tool(tool)],
                isSettled: true))],
            diagnostics: "",
            plan: [],
            tools: [tool],
            permissions: [],
            notices: [],
            elapsedSeconds: 1,
            evictedToolCount: 0,
            ignoredToolUpdateCount: 0)
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
            profileName: "Computer",
            profileIcon: .defaultValue,
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
