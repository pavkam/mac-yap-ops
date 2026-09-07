// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import YapOpsCore

@MainActor
protocol AgentArtifactOpening: AnyObject {
    func begin(runID: UUID)
    func open(runID: UUID, artifact: AgentArtifactPresentation)
    func reveal(runID: UUID, artifact: AgentArtifactPresentation)
    func discard(runID: UUID)
    func shutdown() async
}

protocol AgentArtifactMaterializing: Sendable {
    func materialize(
        runID: UUID,
        artifact: AgentArtifactPresentation) async -> URL?
    func discard(runID: UUID) async
    func discardAll() async
}

protocol AgentArtifactFileChecking: Sendable {
    func existingRegularFile(_ url: URL) async -> URL?
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
            if url.isFileURL {
                return localFileURL(url) != nil
            }
            return ["http", "https"].contains(url.scheme?.lowercased())
        case .image, .embeddedText, .embeddedBlob:
            return true
        }
    }

    static func canReveal(_ artifact: AgentArtifactPresentation) -> Bool {
        guard case .linked = artifact.artifact.payload,
              let url = linkedURL(artifact),
              localFileURL(url) != nil
        else {
            return false
        }
        return true
    }

    static func linkedURL(_ artifact: AgentArtifactPresentation) -> URL? {
        artifact.artifact.uri.flatMap(URL.init(string:))
    }

    static func localFileURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let host = url.host?.lowercased()
        guard host == nil || host == "" || host == "localhost" else { return nil }
        return URL(fileURLWithPath: url.path).standardizedFileURL
    }
}

@MainActor
final class SystemAgentArtifactOpener: AgentArtifactOpening {
    private let store: any AgentArtifactMaterializing
    private let fileChecker: any AgentArtifactFileChecking
    private let workspace: any AgentArtifactWorkspaceOpening
    private let diagnostics: any YapOpsDiagnosticRecording
    private var activeRunID: UUID?
    private var generation: UInt64 = 0

    init(
        store: any AgentArtifactMaterializing = AgentArtifactTemporaryFileStore(),
        fileChecker: any AgentArtifactFileChecking = SystemAgentArtifactFileChecker(),
        workspace: any AgentArtifactWorkspaceOpening = SystemAgentArtifactWorkspace(),
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared)
    {
        self.store = store
        self.fileChecker = fileChecker
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
            guard let url = AgentArtifactActionPolicy.linkedURL(artifact) else {
                record(action: "open", runID: runID, artifact: artifact, result: false)
                return
            }
            Task { [weak self] in
                guard let self,
                      self.activeRunID == runID,
                      self.generation == operationGeneration
                else { return }
                let resolvedURL: URL
                if url.isFileURL {
                    guard let localURL = await self.fileChecker.existingRegularFile(url) else {
                        self.record(action: "open", runID: runID, artifact: artifact, result: false)
                        return
                    }
                    resolvedURL = localURL
                } else {
                    resolvedURL = url
                }
                guard self.activeRunID == runID,
                      self.generation == operationGeneration
                else { return }
                let result = await self.workspace.open(resolvedURL)
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
              let url = AgentArtifactActionPolicy.linkedURL(artifact)
        else {
            record(action: "reveal", runID: runID, artifact: artifact, result: false)
            return
        }
        let operationGeneration = generation
        Task { [weak self] in
            guard let self else { return }
            guard let localURL = await self.fileChecker.existingRegularFile(url) else {
                guard self.activeRunID == runID,
                      self.generation == operationGeneration
                else { return }
                self.record(action: "reveal", runID: runID, artifact: artifact, result: false)
                return
            }
            guard self.activeRunID == runID,
                  self.generation == operationGeneration
            else { return }
            let result = self.workspace.reveal(localURL)
            self.record(action: "reveal", runID: runID, artifact: artifact, result: result)
        }
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

    func shutdown() async {
        generation &+= 1
        activeRunID = nil
        await store.discardAll()
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

final class SystemAgentArtifactFileChecker: AgentArtifactFileChecking, @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "org.ciobanu.YapOps.artifact-file-check",
        qos: .userInitiated)

    func existingRegularFile(_ url: URL) async -> URL? {
        guard let localURL = AgentArtifactActionPolicy.localFileURL(url) else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: localURL.path,
                    isDirectory: &isDirectory)
                continuation.resume(returning: exists && !isDirectory.boolValue ? localURL : nil)
            }
        }
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
        label: "org.ciobanu.YapOps.artifact-files",
        qos: .userInitiated)
    private let rootURL: URL
    private var isClosed = false

    init(rootURL: URL = AgentArtifactTemporaryFileStore.defaultRootURL()) {
        self.rootURL = rootURL
    }

    func materialize(
        runID: UUID,
        artifact: AgentArtifactPresentation) async -> URL?
    {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !isClosed else {
                    continuation.resume(returning: nil)
                    return
                }
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
            queue.async { [self] in
                isClosed = true
                try? FileManager.default.removeItem(at: rootURL)
                continuation.resume()
            }
        }
    }

    private static func defaultRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YapOpsArtifacts", isDirectory: true)
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
