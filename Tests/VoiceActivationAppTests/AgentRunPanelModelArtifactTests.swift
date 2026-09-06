// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import Testing
import VoiceActivationCore
@testable import VoiceActivationApp

private actor ControlledAgentArtifactPreviewLoader: AgentArtifactPreviewLoading {
    private var continuations: [UUID: CheckedContinuation<AgentArtifactPreview?, Never>] = [:]
    private var requested: Set<UUID> = []
    private var requestWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func loadPreview(
        for artifact: AgentArtifactPresentation,
        size _: CGSize,
        scale _: CGFloat
    ) async -> AgentArtifactPreview? {
        requested.insert(artifact.id)
        let waiters = requestWaiters.removeValue(forKey: artifact.id) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            continuations[artifact.id] = continuation
        }
    }

    func waitUntilRequested(_ id: UUID) async {
        guard !requested.contains(id) else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[id, default: []].append(continuation)
        }
    }

    func complete(_ id: UUID, with preview: AgentArtifactPreview?) {
        continuations.removeValue(forKey: id)?.resume(returning: preview)
    }

    func requestCount() -> Int {
        requested.count
    }
}

struct AgentRunPanelModelArtifactTests {
    @MainActor @Test
    func preview_WhenPreviousRunCompletesLate_DoesNotPopulateCurrentRun() async throws {
        let oldRun = UUID()
        let newRun = UUID()
        let oldArtifact = result(title: "Old")
        let preview = AgentArtifactPreview(image: try onePixelImage())
        let loader = ControlledAgentArtifactPreviewLoader()
        let model = AgentRunPanelModel(previewLoader: loader)
        model.begin(snapshot(runID: oldRun, artifacts: [oldArtifact]))
        await loader.waitUntilRequested(oldArtifact.id)

        model.begin(snapshot(runID: newRun, artifacts: []))
        await loader.complete(oldArtifact.id, with: preview)
        await Task.yield()

        #expect(model.previewStatus(for: oldArtifact.id) == nil)
    }

    @MainActor @Test
    func preview_WhenArtifactIsStable_LoadsOnceAndPublishesAvailableState() async throws {
        let runID = UUID()
        let artifact = result(title: "Report")
        let preview = AgentArtifactPreview(image: try onePixelImage())
        let loader = ControlledAgentArtifactPreviewLoader()
        let model = AgentRunPanelModel(previewLoader: loader)
        let initial = snapshot(runID: runID, artifacts: [artifact])
        model.begin(initial)
        await loader.waitUntilRequested(artifact.id)

        await loader.complete(artifact.id, with: preview)
        for _ in 0..<20 where model.previewStatus(for: artifact.id) != .available {
            await Task.yield()
        }
        model.update(initial)

        #expect(model.previewStatus(for: artifact.id) == .available)
        #expect(await loader.requestCount() == 1)
    }

    @MainActor @Test
    func preview_WhenArtifactIsRemoved_RejectsItsLateCompletion() async throws {
        let runID = UUID()
        let artifact = result(title: "Report")
        let preview = AgentArtifactPreview(image: try onePixelImage())
        let loader = ControlledAgentArtifactPreviewLoader()
        let model = AgentRunPanelModel(previewLoader: loader)
        model.begin(snapshot(runID: runID, artifacts: [artifact]))
        await loader.waitUntilRequested(artifact.id)

        model.update(snapshot(runID: runID, artifacts: []))
        await loader.complete(artifact.id, with: preview)
        await Task.yield()

        #expect(model.previewStatus(for: artifact.id) == nil)
    }

    @MainActor @Test
    func preview_WhenRunIsDiscarded_RejectsItsLateCompletion() async throws {
        let runID = UUID()
        let artifact = result(title: "Report")
        let preview = AgentArtifactPreview(image: try onePixelImage())
        let loader = ControlledAgentArtifactPreviewLoader()
        let model = AgentRunPanelModel(previewLoader: loader)
        model.begin(snapshot(runID: runID, artifacts: [artifact]))
        await loader.waitUntilRequested(artifact.id)

        model.discard(runID: runID)
        await loader.complete(artifact.id, with: preview)
        await Task.yield()

        #expect(model.snapshot == nil)
        #expect(model.previewStatus(for: artifact.id) == nil)
    }

    @MainActor @Test
    func preview_WhenPanelShutsDown_RejectsItsLateCompletion() async throws {
        let runID = UUID()
        let artifact = result(title: "Report")
        let preview = AgentArtifactPreview(image: try onePixelImage())
        let loader = ControlledAgentArtifactPreviewLoader()
        let model = AgentRunPanelModel(previewLoader: loader)
        model.begin(snapshot(runID: runID, artifacts: [artifact]))
        await loader.waitUntilRequested(artifact.id)

        model.shutdown()
        await loader.complete(artifact.id, with: preview)
        await Task.yield()

        #expect(model.snapshot == nil)
        #expect(model.previewStatus(for: artifact.id) == nil)
    }

    private func snapshot(
        runID: UUID,
        artifacts: [AgentArtifactPresentation]
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            runID: runID,
            profileID: UUID(),
            profileName: "Computer",
            profileIcon: .defaultValue,
            accent: .blue,
            prompt: "Render",
            providerName: "Codex",
            phase: .running,
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
            artifacts: artifacts,
            omittedArtifactCount: 0)
    }

    private func result(title: String) -> AgentArtifactPresentation {
        AgentArtifactPresentation(
            id: UUID(),
            artifact: AgentArtifact(
                uri: "file:///tmp/report.pdf",
                name: "report.pdf",
                title: title,
                descriptiveText: nil,
                mimeType: "application/pdf",
                declaredSize: 1_024,
                payload: .linked))
    }

    private func onePixelImage() throws -> CGImage {
        let bytes = Data([0, 0, 0, 255])
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        return try #require(CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent))
    }
}
