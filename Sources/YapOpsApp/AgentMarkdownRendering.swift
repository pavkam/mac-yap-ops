// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import MarkdownUI
import SwiftUI

enum AgentMarkdownRenderStyle: Equatable, Sendable {
    case response
    case detail

    var bodyFontSize: CGFloat {
        switch self {
        case .response: 13
        case .detail: 11
        }
    }

    func headingSize(level: Int) -> CGFloat {
        switch (self, level) {
        case (.response, 1): 18
        case (.response, 2): 16
        case (.response, 3): 15
        case (.response, _): 13
        case (.detail, 1): 14
        case (.detail, 2): 13
        case (.detail, _): 11
        }
    }

    var foregroundColor: Color {
        switch self {
        case .response: .primary
        case .detail: .secondary
        }
    }
}

enum AgentMarkdownLinkPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

struct AgentMarkdownBlockImageProvider: ImageProvider {
    let loader: any AgentMarkdownImageLoading

    init(loader: any AgentMarkdownImageLoading = AgentMarkdownImageLoader.shared) {
        self.loader = loader
    }

    func makeImage(url: URL?) -> some View {
        AgentMarkdownImageView(url: url, loader: loader)
    }
}

struct AgentMarkdownInlineImageProvider: InlineImageProvider {
    let loader: any AgentMarkdownImageLoading

    init(loader: any AgentMarkdownImageLoading = AgentMarkdownImageLoader.shared) {
        self.loader = loader
    }

    func image(with url: URL, label: String) async throws -> Image {
        let image = try await loader.image(from: url)
        return Image(image.cgImage, scale: 1, label: Text(label))
    }
}

@MainActor
enum AgentMarkdownRendering {
    static func theme(accent: Color, style: AgentMarkdownRenderStyle) -> Theme {
        Theme()
            .text {
                FontSize(style.bodyFontSize)
                ForegroundColor(style.foregroundColor)
                BackgroundColor(nil)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.88))
                BackgroundColor(.primary.opacity(0.10))
            }
            .strong {
                FontWeight(.semibold)
            }
            .link {
                ForegroundColor(accent)
                UnderlineStyle(.single)
            }
            .heading1 { heading($0, level: 1, style: style) }
            .heading2 { heading($0, level: 2, style: style) }
            .heading3 { heading($0, level: 3, style: style) }
            .heading4 { heading($0, level: 4, style: style) }
            .heading5 { heading($0, level: 5, style: style) }
            .heading6 { heading($0, level: 6, style: style) }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 0, bottom: 8)
            }
            .blockquote { configuration in
                HStack(alignment: .top, spacing: 8) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(.secondary)
                        }
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 0, bottom: 8)
            }
            .codeBlock { configuration in
                VStack(alignment: .leading, spacing: 5) {
                    if let language = configuration.language, !language.isEmpty {
                        Text(language.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.7)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        configuration.label
                            .fixedSize(horizontal: true, vertical: true)
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(style == .response ? 11 : 10)
                                ForegroundColor(style.foregroundColor)
                            }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                .markdownMargin(top: 0, bottom: 8)
            }
            .list { configuration in
                configuration.label
                    .markdownMargin(top: 0, bottom: 8)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.15))
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: .secondary.opacity(0.24)))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(.clear, .white.opacity(0.035)))
                    .markdownMargin(top: 0, bottom: 8)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                        FontSize(.em(0.9))
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
            }
            .thematicBreak {
                Divider()
                    .opacity(0.55)
                    .markdownMargin(top: 6, bottom: 10)
            }
    }

    private static func heading(
        _ configuration: BlockConfiguration,
        level: Int,
        style: AgentMarkdownRenderStyle
    ) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .markdownTextStyle {
                FontSize(style.headingSize(level: level))
                FontWeight(level <= 2 ? .bold : .semibold)
                ForegroundColor(style.foregroundColor)
                BackgroundColor(nil)
            }
            .markdownMargin(top: level <= 2 ? 6 : 3, bottom: 6)
    }
}
