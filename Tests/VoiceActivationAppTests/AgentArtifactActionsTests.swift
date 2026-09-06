// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import VoiceActivationCore
@testable import VoiceActivationApp

@MainActor
private final class ArtifactWorkspaceSpy: AgentArtifactWorkspaceOpening {
    private(set) var opened: [URL] = []
    private(set) var revealed: [URL] = []

    func open(_ url: URL) async -> Bool {
        opened.append(url)
        return true
    }

    func reveal(_ url: URL) -> Bool {
        revealed.append(url)
        return true
    }
}

private actor ControlledArtifactMaterializer: AgentArtifactMaterializing {
    private var continuation: CheckedContinuation<URL?, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false
    private(set) var discardedRuns: [UUID] = []

    func materialize(
        runID _: UUID,
        artifact _: AgentArtifactPresentation
    ) async -> URL? {
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func discard(runID: UUID) async {
        discardedRuns.append(runID)
    }

    func discardAll() async {}

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func complete(with url: URL?) {
        continuation?.resume(returning: url)
        continuation = nil
    }
}

private actor ControlledArtifactFileChecker: AgentArtifactFileChecking {
    private var continuation: CheckedContinuation<URL?, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false

    func existingRegularFile(_ url: URL) async -> URL? {
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func complete(with url: URL?) {
        continuation?.resume(returning: url)
        continuation = nil
    }
}

@MainActor
private final class ArtifactLifecycleDisplaySpy: AgentRunPanelDisplaying {
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

struct AgentArtifactActionsTests {
    @Test func materialize_WhenExplicitlyOpened_WritesBoundedPrivateFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentArtifactTemporaryFileStore(rootURL: root)
        let runID = UUID()
        let artifact = embedded(name: "../../escape?/report?.txt", text: "private result")

        #expect(!FileManager.default.fileExists(atPath: root.path))
        let url = try #require(await store.materialize(runID: runID, artifact: artifact))

        let runDirectory = root.appendingPathComponent(runID.uuidString, isDirectory: true)
        #expect(url.standardizedFileURL.path.hasPrefix(runDirectory.path + "/"))
        #expect(url.lastPathComponent == "report_.txt")
        #expect(try Data(contentsOf: url) == Data("private result".utf8))
        #expect(try posixPermissions(at: runDirectory) == 0o700)
        #expect(try posixPermissions(at: url) == 0o600)

        await store.discard(runID: runID)
        #expect(!FileManager.default.fileExists(atPath: runDirectory.path))
    }

    @Test func materialize_WhenStoreIsClosed_DoesNotRecreateDeletedRoot() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentArtifactTemporaryFileStore(rootURL: root)

        await store.discardAll()
        let url = await store.materialize(
            runID: UUID(),
            artifact: embedded(name: "late.txt", text: "private"))

        #expect(url == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor @Test
    func lifecycle_WhenRunsCloseReplaceDeleteAndShutdown_CleansAtCorrectBoundaries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentArtifactTemporaryFileStore(rootURL: root)
        let workspace = ArtifactWorkspaceSpy()
        let opener = SystemAgentArtifactOpener(store: store, workspace: workspace)
        let display = ArtifactLifecycleDisplaySpy()
        let presenter = AgentRunPanelPresenter(display: display, artifactOpener: opener)
        let firstRunID = UUID()
        let firstArtifact = embedded(name: "first.txt", text: "first")
        presenter.begin(snapshot(runID: firstRunID, artifacts: [firstArtifact]), from: nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))

        display.onAction?(.openArtifact(runID: firstRunID, artifactID: firstArtifact.id))
        await eventually { workspace.opened.count == 1 }
        let firstDirectory = root.appendingPathComponent(firstRunID.uuidString, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))
        presenter.update(snapshot(
            runID: firstRunID,
            phase: .completed(.endTurn),
            artifacts: [firstArtifact]))
        display.onAction?(.close(runID: firstRunID))
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))

        let secondRunID = UUID()
        let secondArtifact = embedded(name: "second.txt", text: "second")
        presenter.begin(snapshot(runID: secondRunID, artifacts: [secondArtifact]), from: nil)
        await eventually { !FileManager.default.fileExists(atPath: firstDirectory.path) }
        display.onAction?(.openArtifact(runID: secondRunID, artifactID: secondArtifact.id))
        await eventually { workspace.opened.count == 2 }
        let secondDirectory = root.appendingPathComponent(secondRunID.uuidString, isDirectory: true)
        presenter.update(snapshot(
            runID: secondRunID,
            phase: .completed(.endTurn),
            artifacts: [secondArtifact]))
        display.onAction?(.delete(runID: secondRunID))
        await eventually { !FileManager.default.fileExists(atPath: secondDirectory.path) }

        let thirdRunID = UUID()
        let thirdArtifact = embedded(name: "third.txt", text: "third")
        presenter.begin(snapshot(runID: thirdRunID, artifacts: [thirdArtifact]), from: nil)
        display.onAction?(.openArtifact(runID: thirdRunID, artifactID: thirdArtifact.id))
        await eventually { workspace.opened.count == 3 }
        await presenter.shutdown()
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor @Test
    func open_WhenRetiredMaterializationCompletesLate_DoesNotInvokeWorkspace() async {
        let materializer = ControlledArtifactMaterializer()
        let workspace = ArtifactWorkspaceSpy()
        let opener = SystemAgentArtifactOpener(store: materializer, workspace: workspace)
        let oldRunID = UUID()
        let artifact = embedded(name: "old.txt", text: "old")
        opener.begin(runID: oldRunID)
        opener.open(runID: oldRunID, artifact: artifact)
        await materializer.waitUntilRequested()

        opener.begin(runID: UUID())
        await materializer.complete(with: URL(fileURLWithPath: "/tmp/old.txt"))
        for _ in 0..<20 { await Task.yield() }

        #expect(workspace.opened.isEmpty)
    }

    @MainActor @Test
    func open_WhenRetiredFileCheckCompletesLate_DoesNotInvokeWorkspace() async {
        let fileChecker = ControlledArtifactFileChecker()
        let workspace = ArtifactWorkspaceSpy()
        let opener = SystemAgentArtifactOpener(
            fileChecker: fileChecker,
            workspace: workspace)
        let oldRunID = UUID()
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let artifact = linked(uri: fileURL.absoluteString)
        opener.begin(runID: oldRunID)
        opener.open(runID: oldRunID, artifact: artifact)
        await fileChecker.waitUntilRequested()

        opener.begin(runID: UUID())
        await fileChecker.complete(with: fileURL)
        for _ in 0..<20 { await Task.yield() }

        #expect(workspace.opened.isEmpty)
    }

    private func embedded(name: String, text: String) -> AgentArtifactPresentation {
        AgentArtifactPresentation(
            id: UUID(),
            artifact: AgentArtifact(
                uri: "memory:///\(name)",
                name: name,
                title: nil,
                descriptiveText: nil,
                mimeType: "text/plain",
                declaredSize: UInt64(text.utf8.count),
                payload: .embeddedText(text)))
    }

    private func linked(uri: String) -> AgentArtifactPresentation {
        AgentArtifactPresentation(
            id: UUID(),
            artifact: AgentArtifact(
                uri: uri,
                name: "report.pdf",
                title: nil,
                descriptiveText: nil,
                mimeType: "application/pdf",
                declaredSize: nil,
                payload: .linked))
    }

    @MainActor
    private func snapshot(
        runID: UUID,
        phase: AgentRunPhase = .running,
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

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @MainActor
    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition did not become true")
    }
}
