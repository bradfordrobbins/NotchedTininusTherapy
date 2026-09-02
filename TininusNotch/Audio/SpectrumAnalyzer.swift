import Accelerate
import AVFoundation
import Foundation

struct SpectrumSnapshot: Equatable, Sendable {
    var sampleRate: Double
    var preBars: [Float]
    var postBars: [Float]

    static let empty = SpectrumSnapshot(sampleRate: 44_100, preBars: [], postBars: [])

    var isEmpty: Bool { preBars.isEmpty && postBars.isEmpty }
}

/// Real FFT → log-frequency magnitude bars for the debug spectrum view.
final class SpectrumAnalyzer: @unchecked Sendable {
    static let displayMinHz: Double = 40
    static let displayMaxHz: Double = 16_000
    static let barCount = 96

    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]

    init(fftSize: Int = 4_096) {
        self.fftSize = fftSize
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func snapshot(pre: AVAudioPCMBuffer, post: AVAudioPCMBuffer) -> SpectrumSnapshot {
        let rate = post.format.sampleRate
        return makeSnapshot(
            preDB: decibels(from: pre),
            postDB: decibels(from: post),
            sampleRate: rate
        )
    }

    func snapshot(preSamples: [Float], postSamples: [Float], sampleRate: Double) -> SpectrumSnapshot {
        makeSnapshot(
            preDB: decibels(samples: preSamples),
            postDB: decibels(samples: postSamples),
            sampleRate: sampleRate
        )
    }

    func decibels(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }

        var mono = [Float](repeating: 0, count: frames)
        if buffer.format.channelCount > 1 {
            var half: Float = 0.5
            vDSP_vasm(channels[0], 1, channels[1], 1, &half, &mono, 1, vDSP_Length(frames))
        } else {
            mono.withUnsafeMutableBufferPointer { dest in
                dest.baseAddress!.update(from: channels[0], count: frames)
            }
        }
        return decibels(samples: mono)
    }

    func decibels(samples: [Float]) -> [Float] {
        var timeDomain = [Float](repeating: 0, count: fftSize)
        let copyCount = min(samples.count, fftSize)
        if copyCount > 0 {
            timeDomain.withUnsafeMutableBufferPointer { dest in
                samples.withUnsafeBufferPointer { src in
                    dest.baseAddress!.update(from: src.baseAddress!, count: copyCount)
                }
            }
        }
        vDSP_vmul(timeDomain, 1, window, 1, &timeDomain, 1, vDSP_Length(fftSize))

        realp.withUnsafeMutableBufferPointer { real in
            imagp.withUnsafeMutableBufferPointer { imag in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                timeDomain.withUnsafeMutableBytes { raw in
                    let complex = raw.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complex.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var roots = [Float](repeating: 0, count: fftSize / 2)
        var count = Int32(fftSize / 2)
        vvsqrtf(&roots, magnitudes, &count)
        var scale = 2.0 / Float(fftSize)
        vDSP_vsmul(roots, 1, &scale, &roots, 1, vDSP_Length(fftSize / 2))

        var decibels = [Float](repeating: -120, count: fftSize / 2)
        var zeroRef: Float = 1
        vDSP_vdbcon(roots, 1, &zeroRef, &decibels, 1, vDSP_Length(fftSize / 2), 0)
        return decibels
    }

    func makeSnapshot(preDB: [Float], postDB: [Float], sampleRate: Double) -> SpectrumSnapshot {
        let preLog = logBars(decibels: preDB, sampleRate: sampleRate)
        let postLog = logBars(decibels: postDB, sampleRate: sampleRate)
        let peak = max(preLog.max() ?? -80, postLog.max() ?? -80, -40)
        let floor = peak - 70
        return SpectrumSnapshot(
            sampleRate: sampleRate,
            preBars: normalize(preLog, peak: peak, floor: floor),
            postBars: normalize(postLog, peak: peak, floor: floor)
        )
    }

    static func barIndex(for frequency: Double, sampleRate: Double = 48_000) -> Int {
        let maxHz = min(displayMaxHz, sampleRate / 2.0)
        let t = (log(max(frequency, displayMinHz)) - log(displayMinHz)) / (log(maxHz) - log(displayMinHz))
        return min(barCount - 1, max(0, Int(t * Double(barCount))))
    }

    static func notchBand(center: Double, width: NotchWidth) -> (low: Double, high: Double) {
        let half = pow(2.0, width.octaves / 2.0)
        return (center / half, center * half)
    }

    private func logBars(decibels: [Float], sampleRate: Double) -> [Float] {
        let minHz = Self.displayMinHz
        let maxHz = min(Self.displayMaxHz, sampleRate / 2.0)
        let minLog = log(minHz)
        let maxLog = log(maxHz)
        guard !decibels.isEmpty else {
            return [Float](repeating: -120, count: Self.barCount)
        }
        let binHz = sampleRate / Double(fftSize)
        var bars = [Float](repeating: -120, count: Self.barCount)

        for bar in 0..<Self.barCount {
            let startHz = exp(minLog + (maxLog - minLog) * Double(bar) / Double(Self.barCount))
            let endHz = exp(minLog + (maxLog - minLog) * Double(bar + 1) / Double(Self.barCount))
            let startBin = max(1, Int(startHz / binHz))
            let endBin = min(decibels.count - 1, max(startBin + 1, Int(ceil(endHz / binHz))))
            var sum: Float = 0
            var count: Float = 0
            for bin in startBin..<endBin {
                sum += decibels[bin]
                count += 1
            }
            let db = count > 0 ? sum / count : -120
            bars[bar] = db
        }
        return bars
    }

    private func normalize(_ decibels: [Float], peak: Float, floor: Float) -> [Float] {
        let span = max(peak - floor, 1)
        return decibels.map { value in
            min(max((value - floor) / span, 0), 1)
        }
    }
}
