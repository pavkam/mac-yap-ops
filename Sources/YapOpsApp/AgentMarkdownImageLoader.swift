// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO

enum AgentMarkdownImageError: Error, Equatable {
    case invalidImage
    case invalidResponse
    case tooLarge
    case unsupportedURL
}

struct AgentMarkdownImageDownload: Sendable {
    let data: Data
    let responseURL: URL
    let statusCode: Int
    let mimeType: String?
}

struct AgentMarkdownImage: @unchecked Sendable {
    let cgImage: CGImage

    var width: Int { cgImage.width }
    var height: Int { cgImage.height }
}

protocol AgentMarkdownImageLoading: Sendable {
    func image(from url: URL) async throws -> AgentMarkdownImage
}

actor AgentMarkdownImageLoader: AgentMarkdownImageLoading {
    typealias Fetch = @Sendable (URL, Int) async throws -> AgentMarkdownImageDownload

    private static let decodeQueue = DispatchQueue(
        label: "org.ciobanu.YapOps.markdown-image",
        qos: .userInitiated)
    private static let maximumPixelSize = 2_048
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["Accept": "image/*"]
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static let shared = AgentMarkdownImageLoader()

    private let cache: NSCache<NSURL, CGImage>
    private let maximumByteCount: Int
    private let fetch: Fetch
    private var inFlight: [URL: Task<AgentMarkdownImage, Error>] = [:]

    init(
        maximumByteCount: Int = 8 * 1_024 * 1_024,
        fetch: @escaping Fetch = AgentMarkdownImageLoader.fetchFromNetwork)
    {
        let cache = NSCache<NSURL, CGImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 32 * 1_024 * 1_024
        self.cache = cache
        self.maximumByteCount = maximumByteCount
        self.fetch = fetch
    }

    func image(from url: URL) async throws -> AgentMarkdownImage {
        guard Self.allows(url) else {
            throw AgentMarkdownImageError.unsupportedURL
        }
        if let cached = cache.object(forKey: url as NSURL) {
            return AgentMarkdownImage(cgImage: cached)
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let maximumByteCount = self.maximumByteCount
        let fetch = self.fetch
        let task = Task<AgentMarkdownImage, Error> {
            let download = try await fetch(url, maximumByteCount)
            try Self.validate(download, maximumByteCount: maximumByteCount)
            return try await Self.decode(download.data)
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight.removeValue(forKey: url)
            cache.setObject(
                image.cgImage,
                forKey: url as NSURL,
                cost: Self.cost(of: image.cgImage))
            return image
        } catch {
            inFlight.removeValue(forKey: url)
            throw error
        }
    }

    private static func fetchFromNetwork(
        _ url: URL,
        maximumByteCount: Int
    ) async throws -> AgentMarkdownImageDownload {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumByteCount) {
            throw AgentMarkdownImageError.tooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumByteCount))
        }
        for try await byte in bytes {
            guard data.count < maximumByteCount else {
                throw AgentMarkdownImageError.tooLarge
            }
            data.append(byte)
        }

        guard let response = response as? HTTPURLResponse,
              let responseURL = response.url
        else {
            throw AgentMarkdownImageError.invalidResponse
        }
        return AgentMarkdownImageDownload(
            data: data,
            responseURL: responseURL,
            statusCode: response.statusCode,
            mimeType: response.mimeType)
    }

    private static func allows(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
    }

    private static func validate(
        _ download: AgentMarkdownImageDownload,
        maximumByteCount: Int
    ) throws {
        guard allows(download.responseURL),
              200..<300 ~= download.statusCode,
              download.data.count <= maximumByteCount,
              download.mimeType?.lowercased().hasPrefix("image/") == true
        else {
            if download.data.count > maximumByteCount {
                throw AgentMarkdownImageError.tooLarge
            }
            throw AgentMarkdownImageError.invalidResponse
        }
    }

    private static func decode(_ data: Data) async throws -> AgentMarkdownImage {
        try await withCheckedThrowingContinuation { continuation in
            decodeQueue.async {
                let image = autoreleasepool { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                        return nil
                    }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    ]
                    return CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        options as CFDictionary)
                }
                if let image {
                    continuation.resume(returning: AgentMarkdownImage(cgImage: image))
                } else {
                    continuation.resume(throwing: AgentMarkdownImageError.invalidImage)
                }
            }
        }
    }

    private static func cost(of image: CGImage) -> Int {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return overflow ? Int.max : cost
    }
}
