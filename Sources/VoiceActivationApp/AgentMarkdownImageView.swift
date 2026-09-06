// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

enum AgentMarkdownImagePresentation {
    case available(AgentMarkdownImage)
    case loading
    case unavailable
}

struct AgentMarkdownImageView: View {
    let url: URL?
    let loader: any AgentMarkdownImageLoading

    @State private var presentation = AgentMarkdownImagePresentation.loading

    var body: some View {
        AgentMarkdownImageContent(presentation: presentation)
            .task(id: url) {
                await load()
            }
    }

    @MainActor
    private func load() async {
        guard let url else {
            presentation = .unavailable
            return
        }
        presentation = .loading
        do {
            let image = try await loader.image(from: url)
            try Task.checkCancellation()
            presentation = .available(image)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            presentation = .unavailable
        }
    }
}

struct AgentMarkdownImageContent: View {
    let presentation: AgentMarkdownImagePresentation

    var body: some View {
        Group {
            switch presentation {
            case let .available(image):
                Image(
                    image.cgImage,
                    scale: 1,
                    label: Text("Agent-provided image"))
                    .resizable()
                    .scaledToFit()
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading agent image")
            case .unavailable:
                Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 420)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
