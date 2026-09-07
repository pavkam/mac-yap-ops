// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import YapOpsCore
@testable import YapOpsApp

@MainActor
private final class ArtifactActionDisplaySpy: AgentRunPanelDisplaying {
    var onAction: ((AgentRunPanelAction) -> Void)?
    func begin(_: AgentRunSnapshot, from _: RecordingOverlayHandoff?) {}
    func update(_: AgentRunSnapshot) {}
    func show(runID _: UUID) {}
    func hide(runID _: UUID) {}
    func discard(runID _: UUID) {}
    func shutdown() {}
    func minimize(runID _: UUID) {}
    func restore(runID _: UUID) {}
}

@MainActor
private final class ArtifactOpenerSpy: AgentArtifactOpening {
    private(set) var began: [UUID] = []
    private(set) var opened: [(UUID, UUID)] = []
    private(set) var revealed: [(UUID, UUID)] = []
    private(set) var discarded: [UUID] = []
    private(set) var shutdownCount = 0

    func begin(runID: UUID) { began.append(runID) }
    func open(runID: UUID, artifact: AgentArtifactPresentation) {
        opened.append((runID, artifact.id))
    }
    func reveal(runID: UUID, artifact: AgentArtifactPresentation) {
        revealed.append((runID, artifact.id))
    }
    func discard(runID: UUID) { discarded.append(runID) }
    func shutdown() async { shutdownCount += 1 }
}

struct AgentRunPanelArtifactActionTests {
    @MainActor @Test func actions_WhenInvoked_ForwardOnlyCurrentSafeResults() {
        let display = ArtifactActionDisplaySpy()
        let opener = ArtifactOpenerSpy()
        let presenter = AgentRunPanelPresenter(display: display, artifactOpener: opener)
        let runID = UUID()
        let local = artifact(uri: "file:///tmp/report.pdf", payload: .linked)
        let remote = artifact(uri: "https://example.com/report.pdf", payload: .linked)
        let forbidden = artifact(uri: "ftp://example.com/report.pdf", payload: .linked)
        let remoteFile = artifact(
            uri: "file://example.invalid/tmp/report.pdf",
            payload: .linked)
        let embedded = artifact(
            uri: "memory:///preview.png",
            payload: .image(data: Data([0, 1]), mimeType: "image/png"))
        presenter.begin(snapshot(
            runID: runID,
            artifacts: [local, remote, forbidden, remoteFile, embedded]), from: nil)

        display.onAction?(.openArtifact(runID: runID, artifactID: local.id))
        display.onAction?(.openArtifact(runID: runID, artifactID: local.id))
        display.onAction?(.openArtifact(runID: runID, artifactID: remote.id))
        display.onAction?(.openArtifact(runID: runID, artifactID: embedded.id))
        display.onAction?(.openArtifact(runID: runID, artifactID: forbidden.id))
        display.onAction?(.openArtifact(runID: runID, artifactID: remoteFile.id))
        display.onAction?(.openArtifact(runID: runID, artifactID: UUID()))
        display.onAction?(.openArtifact(runID: UUID(), artifactID: local.id))
        display.onAction?(.revealArtifact(runID: runID, artifactID: local.id))
        display.onAction?(.revealArtifact(runID: runID, artifactID: remote.id))
        display.onAction?(.revealArtifact(runID: runID, artifactID: embedded.id))
        display.onAction?(.revealArtifact(runID: runID, artifactID: remoteFile.id))

        #expect(opener.opened.map(\.1) == [local.id, local.id, remote.id, embedded.id])
        #expect(opener.revealed.map(\.1) == [local.id])
    }

    @MainActor @Test func lifecycle_WhenRunChanges_CleansWithoutTreatingCloseAsDelete() async {
        let display = ArtifactActionDisplaySpy()
        let opener = ArtifactOpenerSpy()
        let presenter = AgentRunPanelPresenter(display: display, artifactOpener: opener)
        let firstRunID = UUID()
        let secondRunID = UUID()
        presenter.begin(snapshot(runID: firstRunID), from: nil)

        presenter.begin(snapshot(runID: secondRunID), from: nil)
        presenter.update(snapshot(runID: secondRunID, phase: .completed(.endTurn)))
        display.onAction?(.close(runID: secondRunID))
        display.onAction?(.delete(runID: secondRunID))
        await presenter.shutdown()

        #expect(opener.began == [firstRunID, secondRunID])
        #expect(opener.discarded == [firstRunID, secondRunID])
        #expect(opener.shutdownCount == 1)
    }

    @MainActor
    private func artifact(
        uri: String?,
        payload: AgentArtifactPayload
    ) -> AgentArtifactPresentation {
        AgentArtifactPresentation(
            id: UUID(),
            artifact: AgentArtifact(
                uri: uri,
                name: "report.pdf",
                title: nil,
                descriptiveText: nil,
                mimeType: "application/pdf",
                declaredSize: nil,
                payload: payload))
    }

    @MainActor
    private func snapshot(
        runID: UUID,
        phase: AgentRunPhase = .running,
        artifacts: [AgentArtifactPresentation] = []
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            runID: runID,
            profileID: UUID(),
            profileName: "Computer",
            profileIcon: .defaultValue,
            accent: .purple,
            prompt: "Render",
            providerName: "Codex",
            phase: phase,
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
}
