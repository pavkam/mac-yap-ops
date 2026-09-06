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

    @Test func normalized_WhenFileURLIsRelative_OmitsIt() {
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Finder", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: "file:relative.txt",
            selectedText: nil,
            resources: [])

        #expect(snapshot.documentURL == nil)
    }

    @Test(arguments: [256, 257])
    func normalized_WhenBundleIdentifierIsAtOrOverBound_RetainsOnlyTheBoundedPrefix(
        byteCount: Int)
    {
        let bundleIdentifier = String(repeating: "b", count: byteCount)
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(
                processIdentifier: 42,
                applicationName: "Editor",
                bundleIdentifier: bundleIdentifier),
            windowTitle: nil,
            documentURL: nil,
            selectedText: nil,
            resources: [])

        let expected = byteCount == 256 ? bundleIdentifier : String(repeating: "b", count: 256)
        #expect(snapshot.bundleIdentifier == expected)
        #expect(snapshot.truncatedFields == (byteCount == 256 ? [] : ["application.bundleIdentifier"]))
    }

    @Test(arguments: [2_048, 2_049])
    func normalized_WhenDocumentURIIsAtOrOverBound_RetainsOnlyAnAllowedBoundedURI(
        byteCount: Int)
    {
        let prefix = "https://example.test/"
        let uri = prefix + String(repeating: "u", count: byteCount - prefix.utf8.count)
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Browser", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: uri,
            selectedText: nil,
            resources: [])

        #expect(snapshot.documentURL == (byteCount == 2_048 ? uri : nil))
        #expect(snapshot.truncatedFields == (byteCount == 2_048 ? [] : ["documentURL"]))
    }

    @Test(arguments: [256, 257])
    func normalized_WhenResourceNameIsAtOrOverBound_RetainsOnlyTheBoundedPrefix(
        byteCount: Int)
    {
        let name = String(repeating: "n", count: byteCount)
        let snapshot = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(processIdentifier: 42, applicationName: "Finder", bundleIdentifier: nil),
            windowTitle: nil,
            documentURL: nil,
            selectedText: nil,
            resources: [.init(uri: "file:///tmp/notes.txt", name: name)])

        let expected = byteCount == 256 ? name : String(repeating: "n", count: 256)
        #expect(snapshot.resources == [.init(uri: "file:///tmp/notes.txt", name: expected)])
        #expect(snapshot.truncatedFields == (byteCount == 256 ? [] : ["resources"]))
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

    @Test(arguments: [
        CaptureStateWireCase(state: .complete, wireValue: "complete"),
        CaptureStateWireCase(
            state: .accessibilityNotAuthorized,
            wireValue: "accessibility_not_authorized"),
        CaptureStateWireCase(state: .targetUnavailable, wireValue: "target_unavailable"),
        CaptureStateWireCase(state: .timedOut, wireValue: "timed_out"),
        CaptureStateWireCase(state: .accessibilityFailed, wireValue: "accessibility_failed"),
    ])
    func coding_WhenCaptureStateIsEncoded_UsesTheSpecifiedWireValue(
        fixture: CaptureStateWireCase) throws
    {
        let encoded = try JSONEncoder().encode(fixture.state)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"\(fixture.wireValue)\"")
        #expect(try JSONDecoder().decode(MacContextCaptureState.self, from: encoded) == fixture.state)
    }
}

struct CaptureStateWireCase: Sendable {
    let state: MacContextCaptureState
    let wireValue: String
}
