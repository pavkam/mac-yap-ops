// swift-tools-version: 6.2

// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "YapOps",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YapOpsCore", targets: ["YapOpsCore"]),
        .executable(name: "YapOps", targets: ["YapOpsApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing", revision: "swift-6.2.2-RELEASE"),
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui",
            exact: "2.4.1"),
    ],
    targets: [
        .target(name: "YapOpsCore"),
        .executableTarget(
            name: "YapOpsApp",
            dependencies: [
                "YapOpsCore",
                .product(
                    name: "MarkdownUI",
                    package: "swift-markdown-ui"),
            ],
            exclude: [
                "Resources/AgentThinking.wav",
                "Resources/CaptureEnd.wav",
                "Resources/CaptureStart.wav",
                "Resources/Info.plist",
                "Resources/ToolComplete.wav",
                "Resources/ToolFailed.wav",
                "Resources/ToolStart.wav",
                "Resources/YapOps.icns",
            ]),
        .testTarget(
            name: "YapOpsCoreTests",
            dependencies: [
                "YapOpsCore",
                .product(name: "Testing", package: "swift-testing"),
            ]),
        .testTarget(
            name: "YapOpsAppTests",
            dependencies: [
                "YapOpsApp",
                .product(
                    name: "MarkdownUI",
                    package: "swift-markdown-ui"),
                .product(name: "Testing", package: "swift-testing"),
            ]),
    ])
