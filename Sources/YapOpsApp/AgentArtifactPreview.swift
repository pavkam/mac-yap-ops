// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing

struct AgentArtifactPreview: @unchecked Sendable {
    let image: CGImage
}

enum AgentArtifactPreviewStatus: Equatable {
    case loading
    case available
    case unavailable
}

enum AgentArtifactPreviewState {
    case loading
    case available(AgentArtifactPreview)
    case unavailable

    var status: AgentArtifactPreviewStatus {
        switch self {
        case .loading: .loading
        case .available: .available
        case .unavailable: .unavailable
        }
    }
}

protocol AgentArtifactPreviewLoading: Sendable {
    func loadPreview(
        for artifact: AgentArtifactPresentation,
        size: CGSize,
        scale: CGFloat) async -> AgentArtifactPreview?
}

enum AgentArtifactPreviewSource: Equatable, Sendable {
    case embeddedImage(Data)
    case localFile(URL)
}

struct SystemAgentArtifactPreviewLoader: AgentArtifactPreviewLoading {
    private static let imageQueue = DispatchQueue(
        label: "org.ciobanu.YapOps.artifact-preview",
        qos: .userInitiated)
    private let fileChecker: any AgentArtifactFileChecking

    init(fileChecker: any AgentArtifactFileChecking = SystemAgentArtifactFileChecker()) {
        self.fileChecker = fileChecker
    }

    func previewSource(
        for artifact: AgentArtifactPresentation
    ) async -> AgentArtifactPreviewSource? {
        switch artifact.artifact.payload {
        case let .image(data, _):
            .embeddedImage(data)
        case .linked:
            await localFileSource(uri: artifact.artifact.uri)
        case .embeddedText, .embeddedBlob:
            nil
        }
    }

    func loadPreview(
        for artifact: AgentArtifactPresentation,
        size: CGSize,
        scale: CGFloat) async -> AgentArtifactPreview?
    {
        switch await previewSource(for: artifact) {
        case let .embeddedImage(data):
            return await embeddedImagePreview(data: data, size: size, scale: scale)
        case let .localFile(url):
            return await quickLookPreview(url: url, size: size, scale: scale)
        case nil:
            return nil
        }
    }

    private func localFileSource(uri: String?) async -> AgentArtifactPreviewSource? {
        guard let uri,
              let url = URL(string: uri),
              let localURL = await fileChecker.existingRegularFile(url)
        else {
            return nil
        }
        return .localFile(localURL)
    }

    private func embeddedImagePreview(
        data: Data,
        size: CGSize,
        scale: CGFloat) async -> AgentArtifactPreview?
    {
        await withCheckedContinuation { continuation in
            Self.imageQueue.async {
                let preview = autoreleasepool { () -> AgentArtifactPreview? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                        return nil
                    }
                    let maximumDimension = max(size.width, size.height) * max(scale, 1)
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                    ]
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                        .map(AgentArtifactPreview.init(image:))
                }
                continuation.resume(returning: preview)
            }
        }
    }

    private func quickLookPreview(
        url: URL,
        size: CGSize,
        scale: CGFloat) async -> AgentArtifactPreview?
    {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: [.thumbnail, .icon])
        request.iconMode = false
        let operation = AgentQuickLookPreviewOperation(request: request)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                operation.generate { representation in
                    continuation.resume(returning: representation.map {
                        AgentArtifactPreview(image: $0.cgImage)
                    })
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class AgentQuickLookPreviewOperation: @unchecked Sendable {
    private let generator = QLThumbnailGenerator.shared
    private let request: QLThumbnailGenerator.Request

    init(request: QLThumbnailGenerator.Request) {
        self.request = request
    }

    func generate(completion: @escaping @Sendable (QLThumbnailRepresentation?) -> Void) {
        generator.generateBestRepresentation(for: request) { representation, _ in
            completion(representation)
        }
    }

    func cancel() {
        generator.cancel(request)
    }
}
