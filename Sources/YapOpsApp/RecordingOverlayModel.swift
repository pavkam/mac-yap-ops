// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Observation
import YapOpsCore

@MainActor
@Observable
final class RecordingOverlayModel {
    var transcript = ""
    var isRecording = false
    var levels: [Double] = .init(repeating: 0, count: SpeechAudioLevelMeter.barCount)
    var accent: WakeProfileAccent = .blue
    @ObservationIgnored var onCancel: (() -> Void)?
}
