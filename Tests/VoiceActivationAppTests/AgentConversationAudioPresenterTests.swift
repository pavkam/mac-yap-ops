// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

@MainActor
final class AgentConversationAudioSpy: AgentConversationAudioPlaying {
    enum Event: Equatable {
        case activity(AgentActivitySound)
        case speech(String)
    }

    var onSpeakingChange: ((Bool) -> Void)?
    var onSpeak: (() -> Void)?
    var beginsWithSpeechEnabled: Bool?
    private(set) var begunProfiles: [WakeProfile] = []
    private(set) var endConversationCount = 0
    private(set) var workingStates: [Bool] = []
    private(set) var activitySounds: [AgentActivitySound] = []
    private(set) var spoken: [(text: String, localeID: String)] = []
    private(set) var spokenFormats: [AgentSpeechInputFormat] = []
    private(set) var spokenPolicies: [AgentSpeechAdmissionPolicy] = []
    private(set) var verbatimBatches: [[String]] = []
    var acceptsVerbatimBatches = true
    private(set) var events: [Event] = []
    private(set) var stopSpeakingCount = 0
    private(set) var stopAllCount = 0

    func beginConversation(
        profile: WakeProfile,
        readsInheritedReplies: Bool
    ) -> Bool {
        begunProfiles.append(profile)
        if let beginsWithSpeechEnabled { return beginsWithSpeechEnabled }
        return switch profile.speechPreference {
        case .inherit: readsInheritedReplies
        case .disabled: false
        case .voice: true
        }
    }

    func endConversation() {
        endConversationCount += 1
    }

    func setWorking(_ working: Bool) {
        workingStates.append(working)
    }

    func playActivitySound(_ sound: AgentActivitySound) {
        activitySounds.append(sound)
        events.append(.activity(sound))
    }

    func speak(
        _ text: String,
        localeID: String,
        inputFormat: AgentSpeechInputFormat,
        admissionPolicy: AgentSpeechAdmissionPolicy
    ) {
        spoken.append((text, localeID))
        spokenFormats.append(inputFormat)
        spokenPolicies.append(admissionPolicy)
        events.append(.speech(text))
        onSpeak?()
    }

    @discardableResult
    func speakVerbatim(_ texts: [String], localeID: String) -> Bool {
        verbatimBatches.append(texts)
        guard acceptsVerbatimBatches else { return false }
        for text in texts {
            speak(
                text,
                localeID: localeID,
                inputFormat: .agentAuthoredPlainText,
                admissionPolicy: .agentAuthoredVerbatim)
        }
        return true
    }

    func stopSpeaking() {
        stopSpeakingCount += 1
    }

    func stopAll() {
        stopAllCount += 1
    }
}

@MainActor
final class AgentSpeechQueueSpy: AgentSpeechQueueing {
    var onStateChange: ((AgentSpeechQueueState) -> Void)?
    private(set) var requests: [AgentSpeechRequest] = []
    private(set) var stopCount = 0

    @discardableResult
    func enqueue(_ request: AgentSpeechRequest) -> Bool {
        requests.append(request)
        return true
    }

    @discardableResult
    func enqueueVerbatimBatch(_ requests: [AgentSpeechRequest]) -> Bool {
        self.requests.append(contentsOf: requests)
        return true
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ state: AgentSpeechQueueState) {
        onStateChange?(state)
    }
}

@MainActor
final class AgentActivitySoundLoopSpy: AgentActivitySoundLooping {
    private(set) var workingStates: [Bool] = []
    private(set) var suppressionStates: [Bool] = []
    private(set) var sounds: [AgentActivitySound] = []
    private(set) var stopCount = 0
    var onSuppression: ((Bool) -> Void)?

    func setWorking(_ working: Bool) {
        workingStates.append(working)
    }

    func setSpeechSuppressed(_ suppressed: Bool) {
        suppressionStates.append(suppressed)
        onSuppression?(suppressed)
    }

    func play(_ sound: AgentActivitySound) {
        sounds.append(sound)
    }

    func stop() {
        stopCount += 1
    }
}

@Suite(.timeLimit(.minutes(1)))
struct AgentConversationAudioPresenterTests {
}
