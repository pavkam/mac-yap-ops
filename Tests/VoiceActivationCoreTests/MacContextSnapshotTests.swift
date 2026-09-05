// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

struct MacContextSnapshotTests {
    @Test func normalized_WhenSelectionAndResourcesExceedBounds_TruncatesDeterministically() throws {
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(
                processIdentifier: 42,
                applicationName: String(repeating: "é", count: 300),
                bundleIdentifier: "com.example.Editor"),
            windowTitle: String(repeating: "w", count: 700),
            documentURL: "https://example.test/document",
            selectedText: String(repeating: "x", count: 20_000),
            resources: (0..<12).map {
                .init(uri: "file:///tmp/file-\($0).txt", name: "file-\($0).txt")
            })

        #expect(snapshot.applicationName == String(repeating: "é", count: 128))
        #expect(snapshot.windowTitle?.utf8.count == 512)
        #expect(snapshot.selectedText?.utf8.count == 12 * 1_024)
        #expect(snapshot.resources.count == 8)
        #expect(snapshot.truncatedFields == [
            "application.name", "windowTitle", "selectedText", "resources",
        ])
    }

    @Test func normalized_WhenURLSchemeIsUnsafe_OmitsIt() {
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Browser", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: "javascript:alert(1)",
            selectedText: nil,
            resources: [.init(uri: "data:text/plain,secret", name: "secret")])

        #expect(snapshot.documentURL == nil)
        #expect(snapshot.resources.isEmpty)
    }

    @Test func normalized_WhenHTTPURLHasNoHost_OmitsIt() {
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Browser", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: "http:/not-an-authority",
            selectedText: nil,
            resources: [])

        #expect(snapshot.documentURL == nil)
    }

    @Test func normalized_WhenResourceURIsRepeat_RetainsFirstResourceInAccessibilityOrder() {
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Finder", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: nil,
            selectedText: nil,
            resources: [
                .init(uri: "file:///tmp/first.txt", name: "First"),
                .init(uri: "file:///tmp/first.txt", name: "Duplicate"),
                .init(uri: "https://example.test/second", name: "Second"),
            ])

        #expect(snapshot.resources == [
            .init(uri: "file:///tmp/first.txt", name: "First"),
            .init(uri: "https://example.test/second", name: "Second"),
        ])
    }

    @Test func normalized_WhenResourceURIsDifferOnlyByWebSchemeAndHostCase_DeduplicatesThem() {
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Browser", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: nil,
            selectedText: nil,
            resources: [
                .init(uri: "HTTPS://EXAMPLE.test/notes", name: "First"),
                .init(uri: "https://example.test/notes", name: "Duplicate"),
            ])

        #expect(snapshot.resources == [
            .init(uri: "https://example.test/notes", name: "First"),
        ])
    }
}
