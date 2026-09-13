// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AVFoundation
import Foundation
import Speech
import YapOpsCore

/// Reports live input levels alongside a `SpeechSessionProtocol` session.
///
/// A separate protocol rather than a new `SpeechSessionProtocol` requirement:
/// `VoiceBars` is cosmetic, and adding it to the recognition contract would
/// force every fake session in the test suite to grow a levels callback it
/// does not use. A caller that wants levels casts to this protocol; one that
/// does not, ignores it entirely.
@MainActor
protocol SpeechAudioLevelReporting: AnyObject {
    var onLevels: (([Double]) -> Void)? { get set }
}

@MainActor
final class AppleSpeechSession: SpeechSessionProtocol, SpeechAudioLevelReporting {
    enum SessionError: Error, LocalizedError {
        case recognizerUnavailable(String)
        case noAudioInput

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable(let locale):
                "Speech recognition is unavailable for \(locale)."
            case .noAudioInput:
                "No usable microphone input is available."
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let configurationMonitor = AudioEngineConfigurationMonitor()
    private let diagnostics: any YapOpsDiagnosticRecording
    private var hasInputTap = false
    private lazy var levelMeter = SpeechAudioLevelMeter { [weak self] levels in
        self?.onLevels?(levels)
    }

    /// Live input levels for `VoiceBars`, delivered on the main actor at a
    /// throttled rate. `nil` outside `SpeechAudioLevelReporting`'s reach — most
    /// callers only need `SpeechSessionProtocol`.
    var onLevels: (([Double]) -> Void)?
    private var generation = 0

    init(
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) {
        self.diagnostics = diagnostics
    }

    func start(
        mode: SpeechSessionMode,
        localeID: String,
        contextualStrings: [String],
        onUpdate: @escaping (SpeechUpdate) -> Void,
        onInterruption: @escaping () -> Void
    ) throws {
        stop()
        let startedAtUptime = DispatchTime.now().uptimeNanoseconds
        generation &+= 1
        let activeGeneration = generation
        diagnostics.record(
            category: .speechRecognition,
            event: "recognition.start_requested",
            fields: [
                "generation": String(activeGeneration),
                "mode": mode.recognitionDiagnosticName,
                "locale": localeID,
                "contextual_phrase_count": String(contextualStrings.count),
            ])
        let locale = Locale(identifier: localeID)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            diagnostics.record(
                category: .speechRecognition,
                event: "recognition.start_failed",
                level: .error,
                fields: [
                    "generation": String(activeGeneration),
                    "mode": mode.recognitionDiagnosticName,
                    "reason": "recognizer_unavailable",
                ])
            throw SessionError.recognizerUnavailable(localeID)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        try SpeechRequestPolicy.configure(
            request,
            mode: mode,
            supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition,
            contextualStrings: contextualStrings)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        SpeechVoiceProcessingPolicy.configure(input, mode: mode)
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            diagnostics.record(
                category: .speechRecognition,
                event: "recognition.start_failed",
                level: .error,
                fields: [
                    "generation": String(activeGeneration),
                    "mode": mode.recognitionDiagnosticName,
                    "reason": "no_audio_input",
                    "channel_count": String(format.channelCount),
                    "sample_rate": String(format.sampleRate),
                ])
            throw SessionError.noAudioInput
        }

        let bufferSink = SpeechAudioBufferSink(request: request)
        let levelMeter = self.levelMeter
        input.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: format,
            block: Self.makeTap(bufferSink: bufferSink, levelMeter: levelMeter))
        hasInputTap = true
        recognitionRequest = request
        audioEngine = engine
        configurationMonitor.start(observing: engine) { [weak self] in
            guard let self, self.generation == activeGeneration else { return }
            self.diagnostics.record(
                category: .speechRecognition,
                event: "recognition.audio_configuration_changed",
                level: .warning,
                fields: [
                    "generation": String(activeGeneration),
                    "mode": mode.recognitionDiagnosticName,
                ])
            onInterruption()
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let receivedAtUptime = DispatchTime.now().uptimeNanoseconds
            let transcript = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription
            self?.diagnostics.record(
                category: .speechRecognition,
                event: "recognition.update_received",
                level: error == nil ? .debug : .error,
                fields: [
                    "generation": String(activeGeneration),
                    "mode": mode.recognitionDiagnosticName,
                    "character_count": String(transcript.count),
                    "is_final": String(isFinal),
                    "has_error": String(error != nil),
                    "error_type": error.map { String(describing: type(of: $0)) } ?? "",
                ])
            MainRunLoopScheduler.shared.schedule { [weak self] in
                guard let self, self.generation == activeGeneration else { return }
                let deliveredAtUptime = DispatchTime.now().uptimeNanoseconds
                self.diagnostics.record(
                    category: .speechRecognition,
                    event: "recognition.update_delivering",
                    level: .debug,
                    fields: [
                        "generation": String(activeGeneration),
                        "mode": mode.recognitionDiagnosticName,
                        "task_priority": String(Task.currentPriority.rawValue),
                        "main_delivery_ms": String(
                            Self.milliseconds(
                                from: receivedAtUptime,
                                to: deliveredAtUptime)),
                        "run_loop_mode": RunLoop.current.currentMode?.rawValue ?? "none",
                    ])
                onUpdate(
                    SpeechUpdate(
                        transcript: transcript,
                        isFinal: isFinal,
                        errorDescription: errorDescription))
            }
        }

        do {
            engine.prepare()
            try engine.start()
            diagnostics.record(
                category: .speechRecognition,
                event: "recognition.started",
                fields: [
                    "generation": String(activeGeneration),
                    "mode": mode.recognitionDiagnosticName,
                    "channel_count": String(format.channelCount),
                    "sample_rate": String(format.sampleRate),
                    "on_device_supported": String(recognizer.supportsOnDeviceRecognition),
                    "duration_ms": String(
                        Self.milliseconds(
                            from: startedAtUptime,
                            to: DispatchTime.now().uptimeNanoseconds)),
                    "task_priority": String(Task.currentPriority.rawValue),
                ])
        } catch {
            diagnostics.record(
                category: .speechRecognition,
                event: "recognition.start_failed",
                level: .error,
                fields: [
                    "generation": String(activeGeneration),
                    "mode": mode.recognitionDiagnosticName,
                    "reason": "audio_engine_start",
                    "error_type": String(describing: type(of: error)),
                ])
            stop()
            throw error
        }
    }

    /// Builds the recognition tap block outside `AppleSpeechSession`'s actor
    /// isolation.
    ///
    /// A closure literal written directly inside an instance method of a
    /// `@MainActor` class is isolated to that actor by lexical context alone —
    /// regardless of what it captures. `AVAudioEngine` invokes an audio tap
    /// from its own real-time thread, never the main actor, so a closure
    /// written inline here would carry a runtime isolation check that always
    /// fails: an immediate, unrecoverable trap on the first buffer, not a
    /// warning. `nonisolated` breaks that inference; `SpeechAudioBufferSink`
    /// and `SpeechAudioLevelMeter` are themselves plain, non-actor types, so
    /// the closure they end up in has no isolation to check.
    nonisolated static func makeTap(
        bufferSink: SpeechAudioBufferSink,
        levelMeter: SpeechAudioLevelMeter
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            bufferSink.append(buffer)
            levelMeter.process(buffer)
        }
    }

    func stop() {
        let previousGeneration = generation
        let hadAudioEngine = audioEngine != nil
        let hadRecognitionTask = recognitionTask != nil
        generation &+= 1
        configurationMonitor.stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if hasInputTap, let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        hasInputTap = false
        audioEngine?.stop()
        audioEngine = nil
        levelMeter.reset()
        diagnostics.record(
            category: .speechRecognition,
            event: "recognition.stopped",
            fields: [
                "previous_generation": String(previousGeneration),
                "generation": String(generation),
                "had_audio_engine": String(hadAudioEngine),
                "had_recognition_task": String(hadRecognitionTask),
            ])
    }

    nonisolated private static func milliseconds(from start: UInt64, to end: UInt64) -> UInt64 {
        guard end >= start else { return 0 }
        return (end - start) / 1_000_000
    }
}

extension SpeechSessionMode {
    fileprivate var recognitionDiagnosticName: String {
        switch self {
        case .passiveWake: "passive_wake"
        case .commandCapture: "command_capture"
        case .conversation: "conversation"
        case .pushToTalk: "push_to_talk"
        }
    }
}
