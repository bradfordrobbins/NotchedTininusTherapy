import XCTest
@testable import TininusNotch

@MainActor
final class ListeningLogTests: XCTestCase {
    func testMinutesAccumulateAndPersistByDay() {
        let suite = "com.tininusnotch.listening-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let log = ListeningLog(defaults: defaults)
        log.add(seconds: 90)
        log.flush()
        XCTAssertEqual(log.minutes(on: .now), 1)

        let reloaded = ListeningLog(defaults: defaults)
        XCTAssertEqual(reloaded.minutes(on: .now), 1)
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
final class SineToneEngineTests: XCTestCase {
    func testPlayToneDoesNotCrashOnAudioThread() throws {
        let engine = SineToneEngine()
        engine.setFrequency(1_000)
        engine.setVolume(0.1)
        try engine.start()
        let expectation = expectation(description: "tone runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            engine.stop()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }
}

final class NotchFilterTests: XCTestCase {
    func testQualityFactorForOctaveWidths() {
        let full = NotchFilter.qualityFactor(octaves: 1)
        let half = NotchFilter.qualityFactor(octaves: 0.5)
        XCTAssertEqual(full, 1.0 / (sqrt(2.0) - 1.0 / sqrt(2.0)), accuracy: 0.0001)
        XCTAssertEqual(half, 1.0 / (pow(2.0, 0.25) - pow(2.0, -0.25)), accuracy: 0.0001)
        XCTAssertGreaterThan(half, full)
    }

    func testCoefficientsNormalizedAndNotchAtCenter() {
        let sampleRate = 48_000.0
        let frequency = 4_000.0
        let sections = NotchFilter.sectionCoefficients(
            frequency: frequency,
            width: .halfOctave,
            sampleRate: sampleRate
        )
        XCTAssertEqual(sections.count, NotchFilter.prototypeOrder)
        XCTAssertEqual(sections[0].count, 5)

        let magnitude = NotchFilter.cascadeMagnitude(
            sections: sections,
            frequency: frequency,
            sampleRate: sampleRate
        )
        XCTAssertLessThan(magnitude, 0.02, "Gain at the notch center should be near zero")

        let dc = NotchFilter.cascadeMagnitude(sections: sections, frequency: 20, sampleRate: sampleRate)
        XCTAssertEqual(dc, 1.0, accuracy: 0.05)
    }

    func testStopbandIsDeepInsideOctaveWidth() {
        let sampleRate = 48_000.0
        let frequency = 4_000.0
        let sections = NotchFilter.sectionCoefficients(
            frequency: frequency,
            width: .oneOctave,
            sampleRate: sampleRate
        )
        let interior = frequency * pow(2.0, 0.2)
        let magnitude = NotchFilter.cascadeMagnitude(
            sections: sections,
            frequency: interior,
            sampleRate: sampleRate
        )
        XCTAssertLessThan(magnitude, 0.2, "Interior of the octave should be strongly attenuated")
    }

    func testProcessAttenuatesSineAtNotchFrequency() {
        let sampleRate = 48_000.0
        let frequency = 4_000.0
        let filter = NotchFilter()
        filter.update(frequency: frequency, width: .oneOctave, sampleRate: sampleRate)

        let frames = 4_096
        var samples = (0..<frames).map { Float(sin(2.0 * Double.pi * frequency / sampleRate * Double($0))) }
        samples.withUnsafeMutableBufferPointer { buffer in
            filter.process(channel: buffer.baseAddress!, frames: frames, channelIndex: 0)
        }

        let settled = samples[(frames / 2)...]
        let peak = settled.map { abs($0) }.max() ?? 1
        XCTAssertLessThan(peak, 0.08)
    }

    func testProcessPreservesSineAwayFromNotch() {
        let sampleRate = 48_000.0
        let filter = NotchFilter()
        filter.update(frequency: 8_000, width: .halfOctave, sampleRate: sampleRate)

        let frames = 4_096
        let tone = 220.0
        var samples = (0..<frames).map { Float(sin(2.0 * Double.pi * tone / sampleRate * Double($0))) }
        samples.withUnsafeMutableBufferPointer { buffer in
            filter.process(channel: buffer.baseAddress!, frames: frames, channelIndex: 0)
        }

        let settled = Array(samples[(frames / 2)...])
        let peak = settled.map { abs($0) }.max() ?? 0
        XCTAssertEqual(peak, 1.0, accuracy: 0.08)
    }

    func testProcessHistoryAcrossChunks() {
        let sampleRate = 48_000.0
        let frequency = 4_000.0
        let filter = NotchFilter()
        filter.update(frequency: frequency, width: .oneOctave, sampleRate: sampleRate)

        let chunk = 512
        var peak: Float = 0
        for chunkIndex in 0..<8 {
            var samples = (0..<chunk).map { frame in
                Float(sin(2.0 * Double.pi * frequency / sampleRate * Double(chunkIndex * chunk + frame)))
            }
            samples.withUnsafeMutableBufferPointer { buffer in
                filter.process(channel: buffer.baseAddress!, frames: chunk, channelIndex: 0)
            }
            if chunkIndex >= 2 {
                peak = max(peak, samples.map { abs($0) }.max() ?? 0)
            }
        }
        XCTAssertLessThan(peak, 0.08)
    }

    func testSpectrumShowsNotchDip() {
        let sampleRate = 48_000.0
        let frequency = 4_000.0
        let frames = 2_048
        let preSamples = (0..<frames).map { Float(sin(2.0 * Double.pi * frequency / sampleRate * Double($0))) }
        var postSamples = preSamples
        let filter = NotchFilter()
        filter.update(frequency: frequency, width: .oneOctave, sampleRate: sampleRate)
        postSamples.withUnsafeMutableBufferPointer { buffer in
            filter.process(channel: buffer.baseAddress!, frames: frames, channelIndex: 0)
        }

        let snapshot = SpectrumAnalyzer().snapshot(
            preSamples: preSamples,
            postSamples: postSamples,
            sampleRate: sampleRate
        )
        let index = SpectrumAnalyzer.barIndex(for: frequency, sampleRate: sampleRate)
        XCTAssertGreaterThan(snapshot.preBars[index], 0.35)
        XCTAssertLessThan(snapshot.postBars[index], snapshot.preBars[index] * 0.35)
    }
}
