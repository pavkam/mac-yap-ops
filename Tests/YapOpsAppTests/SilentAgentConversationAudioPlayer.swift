// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

@testable import YapOpsApp
@testable import YapOpsCore

@MainActor
final class SilentAgentConversationAudioPlayer: AgentConversationAudioPlaying {
    var onSpeechOutputActiveChange: ((Bool) -> Void)?

    func beginConversation(
        profile: WakeProfile,
        readsInheritedReplies: Bool
    ) -> Bool {
        switch profile.speechPreference {
        case .inherit: readsInheritedReplies
        case .disabled: false
        case .voice: true
        }
    }

    func endConversation() {}
    func setWorking(_ working: Bool) {}
    func playActivitySound(_ sound: AgentActivitySound) {}
    func speak(
        _ text: String,
        localeID: String,
        inputFormat: AgentSpeechInputFormat,
        admissionPolicy: AgentSpeechAdmissionPolicy
    ) {}
    func speakVerbatim(_ texts: [String], localeID: String) -> Bool { true }
    func stopSpeaking() {}
    func stopAll() {}
}
