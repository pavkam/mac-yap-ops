// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import VoiceActivationApp
@testable import VoiceActivationCore

private actor VoicePreviewBackendSpy: TextToSpeechBackend {
    let descriptor: TextToSpeechBackendDescriptor
    private let preparedSpeech: PreparedTextToSpeech
    private(set) var requests: [TextToSpeechPreparationRequest] = []
    private(set) var credentials: [String?] = []

    init(
        id: TextToSpeechBackendID,
        preparedSpeech: PreparedTextToSpeech
    ) {
        descriptor = TextToSpeechBackendDescriptor(
            id: id,
            displayName: id.rawValue,
            requiresCredential: id == .elevenLabs)
        self.preparedSpeech = preparedSpeech
    }

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice] {
        []
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        requests.append(request)
        credentials.append(credential)
        return preparedSpeech
    }
}

private actor GatedVoicePreviewBackend: TextToSpeechBackend {
    let descriptor = TextToSpeechBackendDescriptor(
        id: .elevenLabs,
        displayName: "ElevenLabs",
        requiresCredential: true)
    private var continuation: CheckedContinuation<PreparedTextToSpeech, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice] {
        []
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        let waiters = waiters
        self.waiters = []
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        continuation?.resume(returning: .audio(Data([1, 2, 3])))
        continuation = nil
    }
}

@MainActor
private final class VoicePreviewAudioPlayerSpy: AgentAudioDataPlaying {
    private(set) var playedData: [Data] = []
    private(set) var stopCount = 0
    var acceptsAudio = true

    func play(
        _ data: Data,
        completion: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        playedData.append(data)
        if acceptsAudio {
            completion(true)
        }
        return acceptsAudio
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class VoicePreviewSystemPlayerSpy: AgentSystemSpeechPlaying {
    struct Request: Equatable {
        let text: String
        let localeID: String
        let voiceID: String?
    }

    private(set) var requests: [Request] = []
    private(set) var stopCount = 0

    func play(
        text: String,
        localeID: String,
        voiceID: String?,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        requests.append(Request(text: text, localeID: localeID, voiceID: voiceID))
        completion()
        return true
    }

    func stop() {
        stopCount += 1
    }
}

struct TextToSpeechVoicePreviewPlayerTests {
    @MainActor @Test
    func play_WhenCloudVoiceIsSelected_PreparesItThroughTheCommonBackendRegistry()
        async throws
    {
        let audio = Data([1, 2, 3])
        let backend = VoicePreviewBackendSpy(
            id: .elevenLabs,
            preparedSpeech: .audio(audio))
        let registry = try TextToSpeechBackendRegistry(backends: [backend])
        let audioPlayer = VoicePreviewAudioPlayerSpy()
        let preview = TextToSpeechVoicePreviewPlayer(
            backendRegistry: registry,
            audioPlayer: audioPlayer,
            systemSpeechPlayer: VoicePreviewSystemPlayerSpy())

        try await preview.play(
            TextToSpeechVoicePreviewRequest(
                selection: TextToSpeechVoiceSelection(
                    backendID: .elevenLabs,
                    voiceID: "profile-voice"),
                credential: "global-key",
                localeID: "en-GB"))

        let request = try #require(await backend.requests.first)
        #expect(request.voiceID == "profile-voice")
        #expect(request.localeID == "en-GB")
        #expect(request.text.contains("Voice Activation"))
        #expect(await backend.credentials == ["global-key"])
        #expect(audioPlayer.playedData == [audio])
    }

    @MainActor @Test
    func play_WhenSystemVoiceIsSelected_UsesTheSamePreparedPreviewPath() async throws {
        let voiceID = "com.apple.voice.compact.en-GB.Daniel"
        let backend = VoicePreviewBackendSpy(
            id: .system,
            preparedSpeech: .systemVoice(identifier: voiceID))
        let registry = try TextToSpeechBackendRegistry(backends: [backend])
        let systemPlayer = VoicePreviewSystemPlayerSpy()
        let preview = TextToSpeechVoicePreviewPlayer(
            backendRegistry: registry,
            audioPlayer: VoicePreviewAudioPlayerSpy(),
            systemSpeechPlayer: systemPlayer)

        try await preview.play(
            TextToSpeechVoicePreviewRequest(
                selection: TextToSpeechVoiceSelection(
                    backendID: .system,
                    voiceID: voiceID),
                credential: nil,
                localeID: "en-GB"))

        #expect(systemPlayer.requests.count == 1)
        #expect(systemPlayer.requests.first?.localeID == "en-GB")
        #expect(systemPlayer.requests.first?.voiceID == voiceID)
    }

    @MainActor @Test func play_WhenPreparedAudioCannotStart_ReturnsPlaybackFailure() async throws {
        let backend = VoicePreviewBackendSpy(
            id: .elevenLabs,
            preparedSpeech: .audio(Data([1, 2, 3])))
        let registry = try TextToSpeechBackendRegistry(backends: [backend])
        let audioPlayer = VoicePreviewAudioPlayerSpy()
        audioPlayer.acceptsAudio = false
        let preview = TextToSpeechVoicePreviewPlayer(
            backendRegistry: registry,
            audioPlayer: audioPlayer,
            systemSpeechPlayer: VoicePreviewSystemPlayerSpy())

        await #expect(throws: TextToSpeechVoicePreviewError.playbackFailed) {
            try await preview.play(
                TextToSpeechVoicePreviewRequest(
                    selection: TextToSpeechVoiceSelection(
                        backendID: .elevenLabs,
                        voiceID: "profile-voice"),
                    credential: "global-key",
                    localeID: "en-GB"))
        }
    }

    @MainActor @Test func stop_WhenPreparationIsPending_PreventsStalePlayback() async throws {
        let backend = GatedVoicePreviewBackend()
        let registry = try TextToSpeechBackendRegistry(backends: [backend])
        let audioPlayer = VoicePreviewAudioPlayerSpy()
        let preview = TextToSpeechVoicePreviewPlayer(
            backendRegistry: registry,
            audioPlayer: audioPlayer,
            systemSpeechPlayer: VoicePreviewSystemPlayerSpy())
        let task = Task {
            try await preview.play(
                TextToSpeechVoicePreviewRequest(
                    selection: TextToSpeechVoiceSelection(
                        backendID: .elevenLabs,
                        voiceID: "profile-voice"),
                    credential: "global-key",
                    localeID: "en-GB"))
        }
        await backend.waitUntilRequested()

        preview.stop()
        await backend.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(audioPlayer.playedData.isEmpty)
    }
}
