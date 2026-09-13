// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

@preconcurrency import AVFoundation
import YapOpsCore

/// Turns the recognition tap's raw PCM buffers into a bounded stream of
/// levels for `VoiceBars`.
///
/// The source pulses a mic glyph, which proves the app *thinks* it is
/// recording; bars prove audio is *arriving*. That answers the question the
/// whole product hinges on: did it hear me?
///
/// Every real-time audio callback in this application does minimal work, and
/// this one is on the same tap as recognition itself, so it cannot afford to
/// be the thing that makes that tap slow. RMS over a buffer is one pass with
/// no allocation; everything past that — smoothing, bucketing into bars,
/// touching `@MainActor` state — happens off the audio thread through
/// `MainRunLoopScheduler`, which is also what keeps updates live inside
/// AppKit's modal and event-tracking run-loop modes while a menu or panel is
/// active.
///
/// Delivery is coalesced, not queued: a buffer arriving while the previous
/// level is still in flight to the main actor replaces it rather than
/// stacking up, so a burst of callbacks cannot grow unbounded backlog on a
/// meter that only ever wants the latest value.
final class SpeechAudioLevelMeter: @unchecked Sendable {
    /// Levels for `VoiceBars`, one per bar, each in `0...1`.
    static let barCount = 5

    private let scheduler: MainRunLoopScheduler
    private let onLevels: @MainActor (_ levels: [Double]) -> Void

    private let lock = NSLock()
    private var isDeliveryScheduled = false
    private var latestBuffer: AVAudioPCMBuffer?

    /// Exponential smoothing so bars settle rather than flicker per buffer.
    /// Held only on the main actor, alongside `onLevels`.
    @MainActor private var smoothedLevels = [Double](repeating: 0, count: SpeechAudioLevelMeter.barCount)

    init(
        scheduler: MainRunLoopScheduler = .shared,
        onLevels: @escaping @MainActor (_ levels: [Double]) -> Void
    ) {
        self.scheduler = scheduler
        self.onLevels = onLevels
    }

    /// Call from the recognition tap. Real-time-safe: no allocation beyond the
    /// RMS pass, no locking except the coalescing flag.
    func process(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.rootMeanSquare(of: buffer)

        let shouldSchedule = lock.withLock {
            latestBuffer = buffer
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        scheduler.schedule { [weak self] in
            self?.deliverLatest(rms: rms)
        }
    }

    /// Resets to silence, e.g. between captures so a stale bar does not linger.
    func reset() {
        scheduler.schedule { [weak self] in
            guard let self else { return }
            smoothedLevels = .init(repeating: 0, count: Self.barCount)
            onLevels(smoothedLevels)
        }
    }

    @MainActor
    private func deliverLatest(rms: Float) {
        lock.withLock {
            latestBuffer = nil
            isDeliveryScheduled = false
        }

        let target = Self.bars(forRMS: rms)
        for index in smoothedLevels.indices {
            let previous = smoothedLevels[index]
            let next = target[index]
            // Rise fast so bars feel responsive; fall slower so a level reads
            // as sustained rather than flickering to zero between syllables.
            smoothedLevels[index] = next > previous
                ? previous + (next - previous) * 0.6
                : previous + (next - previous) * 0.25
        }
        onLevels(smoothedLevels)
    }

    private static func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        let channel = channelData[0]
        var sumOfSquares: Float = 0
        for frame in 0..<frameCount {
            let sample = channel[frame]
            sumOfSquares += sample * sample
        }
        return (sumOfSquares / Float(frameCount)).squareRoot()
    }

    /// Spreads one RMS value across the bar circumference with a slight
    /// per-bar variance, so bars read as a level meter rather than one number
    /// repeated five times.
    private static func bars(forRMS rms: Float) -> [Double] {
        // -50 dBFS floor to 0 dBFS ceiling, matched to a quiet room through a
        // normal speaking voice on a built-in mic.
        let floor: Float = 0.003
        let normalized = rms <= floor ? 0 : min(1, (rms - floor) / (0.3 - floor))
        let level = Double(normalized)

        let variance: [Double] = [0.85, 1.0, 1.12, 1.0, 0.85]
        return variance.map { min(1, level * $0) }
    }
}
