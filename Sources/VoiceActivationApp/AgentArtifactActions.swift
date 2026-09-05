// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import VoiceActivationCore

@MainActor
protocol AgentArtifactOpening: AnyObject {
    func begin(runID: UUID)
    func open(runID: UUID, artifact: AgentArtifactPresentation)
    func reveal(runID: UUID, artifact: AgentArtifactPresentation)
    func discard(runID: UUID)
    func shutdown()
}

protocol AgentArtifactMaterializing: Sendable {
    func materialize(
        runID: UUID,
        artifact: AgentArtifactPresentation) async -> URL?
    func discard(runID: UUID) async
    func discardAll() async
}

@MainActor
protocol AgentArtifactWorkspaceOpening: AnyObject {
    func open(_ url: URL) async -> Bool
    func reveal(_ url: URL) -> Bool
}

enum AgentArtifactActionPolicy {
    static func canOpen(_ artifact: AgentArtifactPresentation) -> Bool {
        switch artifact.artifact.payload {
        case .linked:
            guard let url = linkedURL(artifact) else { return false }
            return ["file", "http", "https"].contains(url.scheme?.lowercased())
        case .image, .embeddedText, .embeddedBlob:
            return true
        }
    }

    static func canReveal(_ artifact: AgentArtifactPresentation) -> Bool {
        guard case .linked = artifact.artifact.payload,
              let url = linkedURL(artifact)
        else {
            return false
        }
        return url.isFileURL
    }

    static func linkedURL(_ artifact: AgentArtifactPresentation) -> URL? {
        artifact.artifact.uri.flatMap(URL.init(string:))
    }
}

@MainActor
final class SystemAgentArtifactOpener: AgentArtifactOpening {
    private let store: any AgentArtifactMaterializing
    private let workspace: any AgentArtifactWorkspaceOpening
    private let diagnostics: any VoiceActivationDiagnosticRecording
    private var activeRunID: UUID?
    private var generation: UInt64 = 0

    init(
        store: any AgentArtifactMaterializing = AgentArtifactTemporaryFileStore(),
        workspace: any AgentArtifactWorkspaceOpening = SystemAgentArtifactWorkspace(),
        diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared)
    {
        self.store = store
        self.workspace = workspace
        self.diagnostics = diagnostics
    }

    func begin(runID: UUID) {
        generation &+= 1
        activeRunID = runID
    }

    func open(runID: UUID, artifact: AgentArtifactPresentation) {
        guard activeRunID == runID, AgentArtifactActionPolicy.canOpen(artifact) else {
            record(action: "open", runID: runID, artifact: artifact, result: false)
            return
        }
        let operationGeneration = generation

        switch artifact.artifact.payload {
        case .linked:
            guard let url = AgentArtifactActionPolicy.linkedURL(artifact),
                  linkedURLCanOpen(url)
            else {
                record(action: "open", runID: runID, artifact: artifact, result: false)
                return
            }
            Task { [weak self] in
                guard let self,
                      self.activeRunID == runID,
                      self.generation == operationGeneration
                else { return }
                let result = await self.workspace.open(url)
                self.record(action: "open", runID: runID, artifact: artifact, result: result)
            }
        case .image, .embeddedText, .embeddedBlob:
            Task { [weak self] in
                guard let self,
                      self.activeRunID == runID,
                      self.generation == operationGeneration
                else { return }
                guard let url = await self.store.materialize(
                    runID: runID,
                    artifact: artifact)
                else {
                    self.record(action: "open", runID: runID, artifact: artifact, result: false)
                    return
                }
                guard self.activeRunID == runID,
                      self.generation == operationGeneration
                else {
                    await self.store.discard(runID: runID)
                    return
                }
                let result = await self.workspace.open(url)
                self.record(action: "open", runID: runID, artifact: artifact, result: result)
            }
        }
    }

    func reveal(runID: UUID, artifact: AgentArtifactPresentation) {
        guard activeRunID == runID,
              AgentArtifactActionPolicy.canReveal(artifact),
              let url = AgentArtifactActionPolicy.linkedURL(artifact),
              FileManager.default.fileExists(atPath: url.path)
        else {
            record(action: "reveal", runID: runID, artifact: artifact, result: false)
            return
        }
        let result = workspace.reveal(url)
        record(action: "reveal", runID: runID, artifact: artifact, result: result)
    }

    func discard(runID: UUID) {
        if activeRunID == runID {
            generation &+= 1
            activeRunID = nil
        }
        Task { [store] in
            await store.discard(runID: runID)
        }
    }

    func shutdown() {
        generation &+= 1
        activeRunID = nil
        Task { [store] in
            await store.discardAll()
        }
    }

    private func linkedURLCanOpen(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func record(
        action: String,
        runID: UUID,
        artifact: AgentArtifactPresentation,
        result: Bool)
    {
        let scheme = AgentArtifactActionPolicy.linkedURL(artifact)?.scheme?.lowercased()
            ?? "materialized"
        diagnostics.record(
            category: .ui,
            event: "agent_artifact.\(action)",
            level: result ? .info : .warning,
            fields: [
                "run_id": runID.uuidString,
                "scheme": scheme,
                "has_mime_type": String(artifact.artifact.mimeType != nil),
                "result": String(result),
            ])
    }
}

@MainActor
final class SystemAgentArtifactWorkspace: AgentArtifactWorkspaceOpening {
    func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(
                url,
                configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    continuation.resume(returning: error == nil)
                }
        }
    }

    func reveal(_ url: URL) -> Bool {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }
}

final class AgentArtifactTemporaryFileStore: AgentArtifactMaterializing, @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "org.ciobanu.VoiceActivation.artifact-files",
        qos: .userInitiated)
    private let rootURL: URL

    init(rootURL: URL = AgentArtifactTemporaryFileStore.defaultRootURL()) {
        self.rootURL = rootURL
    }

    func materialize(
        runID: UUID,
        artifact: AgentArtifactPresentation) async -> URL?
    {
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                continuation.resume(returning: Self.write(
                    rootURL: rootURL,
                    runID: runID,
                    artifact: artifact))
            }
        }
    }

    func discard(runID: UUID) async {
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                let runURL = rootURL.appendingPathComponent(
                    runID.uuidString,
                    isDirectory: true)
                try? FileManager.default.removeItem(at: runURL)
                continuation.resume()
            }
        }
    }

    func discardAll() async {
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                try? FileManager.default.removeItem(at: rootURL)
                continuation.resume()
            }
        }
    }

    private static func defaultRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceActivationArtifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func write(
        rootURL: URL,
        runID: UUID,
        artifact: AgentArtifactPresentation) -> URL?
    {
        let data: Data
        switch artifact.artifact.payload {
        case let .image(value, _), let .embeddedBlob(value):
            data = value
        case let .embeddedText(value):
            data = Data(value.utf8)
        case .linked:
            return nil
        }

        let manager = FileManager.default
        let runURL = rootURL.appendingPathComponent(runID.uuidString, isDirectory: true)
        let artifactURL = runURL.appendingPathComponent(
            artifact.id.uuidString,
            isDirectory: true)
        let fileURL = artifactURL.appendingPathComponent(
            sanitizedBasename(artifact.artifact.name),
            isDirectory: false)
        do {
            try manager.createDirectory(
                at: artifactURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runURL.path)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: artifactURL.path)
            try data.write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func sanitizedBasename(_ name: String) -> String {
        let basename = URL(fileURLWithPath: name).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        var result = ""
        var byteCount = 0
        for scalar in basename.unicodeScalars {
            let replacement = allowed.contains(scalar) ? String(scalar) : "_"
            guard byteCount + replacement.utf8.count <= 180 else { break }
            result += replacement
            byteCount += replacement.utf8.count
        }
        return result.isEmpty || result == "." || result == ".." ? "Artifact" : result
    }
}
