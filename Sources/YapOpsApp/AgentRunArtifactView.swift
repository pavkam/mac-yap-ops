// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI
import YapOpsCore

struct AgentRunArtifactShelf: View {
    let snapshot: AgentRunSnapshot
    @Bindable var model: AgentRunPanelModel

    var body: some View {
        if !snapshot.artifacts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Results", systemImage: "square.grid.2x2")
                    .font(.headline)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 12)],
                    alignment: .leading,
                    spacing: 12)
                {
                    ForEach(snapshot.artifacts) { result in
                        AgentRunArtifactCard(
                            result: result,
                            preview: model.previewState(for: result.id),
                            accent: snapshot.accent.swiftUIColor,
                            onOpen: {
                                model.onAction?(.openArtifact(
                                    runID: snapshot.runID,
                                    artifactID: result.id))
                            },
                            onReveal: {
                                model.onAction?(.revealArtifact(
                                    runID: snapshot.runID,
                                    artifactID: result.id))
                            })
                    }
                }
            }
        }
    }
}

private struct AgentRunArtifactCard: View {
    let result: AgentArtifactPresentation
    let preview: AgentArtifactPreviewState?
    let accent: Color
    let onOpen: () -> Void
    let onReveal: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewView

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    if displayTitle != result.artifact.name {
                        Text(result.artifact.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let description = result.artifact.descriptiveText,
                       !description.isEmpty
                    {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if AgentArtifactActionPolicy.canOpen(result) {
                    Button("Open", systemImage: "arrow.up.forward.app", action: onOpen)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(accent)
                        .help("Open \(displayTitle)")
                        .accessibilityHint("Opens this result in its default application")
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: Design.Radius.artifact))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.artifact)
                .stroke(
                    contrast == .increased
                        ? Color.primary.opacity(0.55)
                        : Color(nsColor: .separatorColor),
                    lineWidth: contrast == .increased ? 1.5 : 0.5)
                .accessibilityHidden(true)
        }
        .contextMenu {
            if AgentArtifactActionPolicy.canReveal(result) {
                Button("Reveal in Finder", systemImage: "folder") {
                    onReveal()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Result: \(displayTitle)")
        .accessibilityValue(metadata)
    }

    @ViewBuilder
    private var previewView: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            switch preview {
            case let .available(preview):
                Image(decorative: preview.image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
            case .unavailable, nil:
                Image(systemName: fallbackSymbol)
                    .font(Design.Text.artifactFallback)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.thumbnail))
        .accessibilityHidden(true)
    }

    private var displayTitle: String {
        let title = result.artifact.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? result.artifact.name
    }

    private var metadata: String {
        [kindLabel, formattedSize].compactMap { $0 }.joined(separator: " · ")
    }

    private var kindLabel: String {
        let mimeType = result.artifact.mimeType?.lowercased() ?? ""
        if mimeType == "application/pdf" { return "PDF document" }
        if mimeType.hasPrefix("image/") { return "Image" }
        if mimeType.hasPrefix("text/") { return "Text document" }
        switch result.artifact.payload {
        case .image: return "Image"
        case .embeddedText: return "Text document"
        case .embeddedBlob, .linked: return "File"
        }
    }

    private var fallbackSymbol: String {
        switch kindLabel {
        case "PDF document": "doc.richtext"
        case "Image": "photo"
        case "Text document": "doc.text"
        default: "doc"
        }
    }

    private var formattedSize: String? {
        let count = result.artifact.declaredSize ?? UInt64(result.embeddedByteCount)
        guard count > 0, count <= UInt64(Int64.max) else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
