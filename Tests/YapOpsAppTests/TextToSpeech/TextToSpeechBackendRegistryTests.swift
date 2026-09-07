// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

private actor TextToSpeechBackendSpy: TextToSpeechBackend {
    let descriptor: TextToSpeechBackendDescriptor
    private let catalog: [TextToSpeechVoice]
    private let preparation: PreparedTextToSpeech
    private(set) var credentials: [String?] = []
    private(set) var requests: [TextToSpeechPreparationRequest] = []

    init(
        id: TextToSpeechBackendID,
        catalog: [TextToSpeechVoice] = [],
        preparation: PreparedTextToSpeech = .systemVoice(identifier: nil)
    ) {
        descriptor = TextToSpeechBackendDescriptor(
            id: id,
            displayName: id.rawValue,
            requiresCredential: false)
        self.catalog = catalog
        self.preparation = preparation
    }

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice] {
        credentials.append(credential)
        return catalog
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        requests.append(request)
        credentials.append(credential)
        return preparation
    }
}

@Suite
struct TextToSpeechBackendRegistryTests {
    @Test func init_WhenBackendIDsRepeat_RejectsTheAmbiguousRegistry() {
        let first = TextToSpeechBackendSpy(id: .system)
        let second = TextToSpeechBackendSpy(id: .system)

        #expect(throws: TextToSpeechBackendRegistryError.duplicateBackend(.system)) {
            _ = try TextToSpeechBackendRegistry(backends: [first, second])
        }
    }

    @Test func descriptors_AreSortedForStableSettingsPresentation() throws {
        let registry = try TextToSpeechBackendRegistry(backends: [
            TextToSpeechBackendSpy(id: TextToSpeechBackendID(rawValue: "zeta")),
            TextToSpeechBackendSpy(id: TextToSpeechBackendID(rawValue: "alpha")),
        ])

        #expect(registry.descriptors.map(\.id.rawValue) == ["alpha", "zeta"])
    }

    @Test func availableVoices_RoutesToTheSelectedBackendWithoutOwningCredentials()
        async throws
    {
        let voice = TextToSpeechVoice(id: "voice-1", name: "Voice One", localeID: "en-GB")
        let backend = TextToSpeechBackendSpy(id: .elevenLabs, catalog: [voice])
        let registry = try TextToSpeechBackendRegistry(backends: [backend])

        let voices = try await registry.availableVoices(
            backendID: .elevenLabs,
            credential: "global-key")

        #expect(voices == [voice])
        #expect(await backend.credentials == ["global-key"])
    }

    @Test func prepare_RoutesVoiceIdentityAndLocaleToTheSelectedBackend() async throws {
        let backend = TextToSpeechBackendSpy(
            id: .system,
            preparation: .systemVoice(identifier: "com.apple.voice.compact.en-GB.Daniel"))
        let registry = try TextToSpeechBackendRegistry(backends: [backend])
        let request = TextToSpeechPreparationRequest(
            text: "Hello.",
            localeID: "en-GB",
            voiceID: "com.apple.voice.compact.en-GB.Daniel")

        let result = try await registry.prepare(
            request,
            backendID: .system,
            credential: nil)

        #expect(result == .systemVoice(identifier: request.voiceID))
        #expect(await backend.requests == [request])
    }

    @Test func routing_WhenBackendIsUnknown_ReturnsTypedFailure() async throws {
        let registry = try TextToSpeechBackendRegistry(backends: [])
        let missing = TextToSpeechBackendID(rawValue: "future-provider")

        await #expect(throws: TextToSpeechBackendRegistryError.unknownBackend(missing)) {
            _ = try await registry.availableVoices(backendID: missing, credential: nil)
        }
    }
}
