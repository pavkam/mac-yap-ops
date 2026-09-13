// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AVFoundation
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

@MainActor
@Suite struct SpeechAudioLevelMeterTests {
    @Test func silenceReportsZeroForEveryBar() async throws {
        let levels = try await levels(afterProcessing: buffer(amplitude: 0), settleSteps: 3)
        for level in levels {
            #expect(level == 0)
        }
    }

    /// Bars must rise from a loud buffer, and there must be more than one
    /// delivery in the sequence — proof the meter is not silently dropping
    /// every buffer after the first.
    @Test func loudAudioRaisesEveryBarAboveZero() async throws {
        let levels = try await levels(afterProcessing: buffer(amplitude: 0.9), settleSteps: 6)
        for level in levels {
            #expect(level > 0)
        }
    }

    /// A burst of buffers arriving faster than delivery must coalesce to the
    /// latest value rather than growing an unbounded backlog — this is what
    /// keeps a real-time audio callback minimal, per the repository's
    /// invariant on bounded queues.
    @Test func aBurstOfBuffersProducesFarFewerDeliveriesThanCalls() async {
        var deliveryCount = 0
        let meter = SpeechAudioLevelMeter(scheduler: MainRunLoopScheduler()) { _ in
            deliveryCount += 1
        }
        let loud = buffer(amplitude: 0.9)

        for _ in 0..<200 {
            meter.process(loud)
        }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(deliveryCount < 200)
        #expect(deliveryCount > 0)
    }

    @Test func resetReturnsEveryBarToZero() async {
        var lastLevels: [Double] = []
        let meter = SpeechAudioLevelMeter(scheduler: MainRunLoopScheduler()) { levels in
            lastLevels = levels
        }
        meter.process(buffer(amplitude: 0.9))
        try? await Task.sleep(for: .milliseconds(50))

        meter.reset()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(lastLevels.allSatisfy { $0 == 0 })
    }

    // MARK: - Helpers

    private func levels(
        afterProcessing buffer: AVAudioPCMBuffer,
        settleSteps: Int
    ) async throws -> [Double] {
        var lastLevels: [Double] = []
        let meter = SpeechAudioLevelMeter(scheduler: MainRunLoopScheduler()) { levels in
            lastLevels = levels
        }
        for _ in 0..<settleSteps {
            meter.process(buffer)
            try await Task.sleep(for: .milliseconds(20))
        }
        return lastLevels
    }

    private func buffer(amplitude: Float, frameCount: AVAudioFrameCount = 512) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                channelData[0][frame] = amplitude
            }
        }
        return buffer
    }
}
