// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AVFoundation
import YapOpsCore

protocol SpeechVoiceProcessingConfiguring: AnyObject {
    var speechOutputChannelCount: AVAudioChannelCount { get }

    func setVoiceProcessingEnabled(_ enabled: Bool) throws
}

extension AVAudioInputNode: SpeechVoiceProcessingConfiguring {
    var speechOutputChannelCount: AVAudioChannelCount {
        outputFormat(forBus: 0).channelCount
    }
}

enum SpeechVoiceProcessingPolicy {
    static func configure(
        _ input: any SpeechVoiceProcessingConfiguring,
        mode: SpeechSessionMode)
    {
        guard mode == .conversation else { return }
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            return
        }
        guard input.speechOutputChannelCount != 1 else { return }
        try? input.setVoiceProcessingEnabled(false)
    }
}
