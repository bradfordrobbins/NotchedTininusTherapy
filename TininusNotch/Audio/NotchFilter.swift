import Accelerate
import AVFoundation
import Foundation

/// Butterworth band-stop implemented as cascaded `vDSP_deq22` biquads.
///
/// A single 2nd-order notch is only deep at the exact center; its −3 dB
/// “width” is a shallow V. Order 8 (4 sections) keeps the same edge
/// frequencies but makes the stopband a real hole, which is what notched
/// music therapy needs.
final class NotchFilter: @unchecked Sendable {
    /// Analog low-pass prototype order. Digital band-stop order is `2 * prototypeOrder`.
    static let prototypeOrder = 4

    private var sections: [BiquadSection] = []
    private var scratchA: [Float] = []
    private var scratchB: [Float] = []
    private let lock = NSLock()

    func update(frequency: Double, width: NotchWidth, sampleRate: Double) {
        let designed = Self.sectionCoefficients(
            frequency: frequency,
            width: width,
            sampleRate: sampleRate
        )
        lock.lock()
        defer { lock.unlock() }
        if sections.count != designed.count {
            sections = designed.map { BiquadSection(coefficients: $0) }
        } else {
            for index in designed.indices {
                sections[index].coefficients = designed[index]
            }
        }
    }

    func resetDelays() {
        lock.lock()
        defer { lock.unlock() }
        for index in sections.indices {
            sections[index].resetDelays()
        }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        process(channel: channels[0], frames: frames, channelIndex: 0)
        if buffer.format.channelCount > 1 {
            process(channel: channels[1], frames: frames, channelIndex: 1)
        }
    }

    func process(channel: UnsafeMutablePointer<Float>, frames: Int, channelIndex: Int) {
        guard frames > 0, channelIndex < 2 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !sections.isEmpty else { return }

        let needed = frames + 2
        if scratchA.count < needed {
            scratchA = [Float](repeating: 0, count: needed)
            scratchB = [Float](repeating: 0, count: needed)
        }

        scratchA.withUnsafeMutableBufferPointer { dest in
            dest.baseAddress!.advanced(by: 2).update(from: channel, count: frames)
        }

        for sectionIndex in sections.indices {
            let input = sectionIndex % 2 == 0 ? scratchA : scratchB
            var output = sectionIndex % 2 == 0 ? scratchB : scratchA
            sections[sectionIndex].apply(
                input: input,
                output: &output,
                frames: frames,
                channelIndex: channelIndex
            )
            if sectionIndex % 2 == 0 {
                scratchB = output
            } else {
                scratchA = output
            }
        }

        let result = sections.count % 2 == 0 ? scratchA : scratchB
        result.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!.advanced(by: 2), count: frames)
        }
    }

    /// Q = f0 / BW, BW = f0 * (2^(w/2) - 2^(-w/2)).
    static func qualityFactor(octaves: Double) -> Double {
        let half = octaves / 2.0
        return 1.0 / (pow(2.0, half) - pow(2.0, -half))
    }

    static func coefficients(frequency: Double, width: NotchWidth, sampleRate: Double) -> [Float] {
        sectionCoefficients(frequency: frequency, width: width, sampleRate: sampleRate)[0]
    }

    static func sectionCoefficients(frequency: Double, width: NotchWidth, sampleRate: Double) -> [[Float]] {
        let nyquist = sampleRate / 2.0
        let f0 = min(max(frequency, 20), nyquist * 0.92)
        let half = pow(2.0, width.octaves / 2.0)
        let fLow = max(f0 / half, 10)
        let fHigh = min(f0 * half, nyquist * 0.96)
        let omega0 = 2.0 * Double.pi * f0 / sampleRate
        let analogLow = tan(Double.pi * fLow / sampleRate)
        let analogHigh = tan(Double.pi * fHigh / sampleRate)
        let analogW0 = sqrt(analogLow * analogHigh)
        let analogBW = analogHigh - analogLow

        var analogPoles: [Complex] = []
        for pole in butterworthLowpassPoles(order: prototypeOrder) {
            analogPoles.append(contentsOf: lowpassToBandstop(pole: pole, w0: analogW0, bandwidth: analogBW))
        }

        return pairConjugates(analogPoles).map { pole, conjugate in
            digitalNotchSection(pole: bilinear(pole), conjugate: bilinear(conjugate), omega0: omega0)
        }
    }

    static func cascadeMagnitude(sections: [[Float]], frequency: Double, sampleRate: Double) -> Double {
        sections.reduce(1.0) { partial, coeffs in
            partial * biquadMagnitude(coefficients: coeffs, frequency: frequency, sampleRate: sampleRate)
        }
    }

    private static func butterworthLowpassPoles(order: Int) -> [Complex] {
        (0..<order).map { index in
            let angle = Double.pi * Double(2 * index + 1) / Double(2 * order)
            return Complex(re: -sin(angle), im: cos(angle))
        }
    }

    private static func lowpassToBandstop(pole: Complex, w0: Double, bandwidth: Double) -> [Complex] {
        let scaled = pole * bandwidth
        let discriminant = (scaled * scaled) - Complex(re: 4 * w0 * w0, im: 0)
        let root = discriminant.squareRoot
        return [(scaled + root) / 2, (scaled - root) / 2]
    }

    private static func bilinear(_ analog: Complex) -> Complex {
        let one = Complex(re: 1, im: 0)
        return (one + analog) / (one - analog)
    }

    private static func pairConjugates(_ poles: [Complex]) -> [(Complex, Complex)] {
        var remaining = poles
        var pairs: [(Complex, Complex)] = []
        while remaining.count >= 2 {
            let pole = remaining.removeFirst()
            var bestIndex = 0
            var bestScore = Double.greatestFiniteMagnitude
            for (index, candidate) in remaining.enumerated() {
                let score = abs(candidate.re - pole.re) + abs(candidate.im + pole.im)
                if score < bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }
            pairs.append((pole, remaining.remove(at: bestIndex)))
        }
        return pairs
    }

    private static func digitalNotchSection(pole: Complex, conjugate: Complex, omega0: Double) -> [Float] {
        let digitalPole = pole.im >= 0 ? pole : conjugate
        var b0 = 1.0
        var b1 = -2.0 * cos(omega0)
        var b2 = 1.0
        let a1 = -2.0 * digitalPole.re
        let a2 = digitalPole.re * digitalPole.re + digitalPole.im * digitalPole.im
        let dcNum = b0 + b1 + b2
        let dcDen = 1 + a1 + a2
        if abs(dcNum) > 1e-12 {
            let scale = dcDen / dcNum
            b0 *= scale
            b1 *= scale
            b2 *= scale
        }
        return [Float(b0), Float(b1), Float(b2), Float(a1), Float(a2)]
    }

    static func biquadMagnitude(coefficients: [Float], frequency: Double, sampleRate: Double) -> Double {
        let b0 = Double(coefficients[0])
        let b1 = Double(coefficients[1])
        let b2 = Double(coefficients[2])
        let a1 = Double(coefficients[3])
        let a2 = Double(coefficients[4])
        let w = 2.0 * Double.pi * frequency / sampleRate
        let z1r = cos(-w)
        let z1i = sin(-w)
        let z2r = cos(-2 * w)
        let z2i = sin(-2 * w)
        let numR = b0 + b1 * z1r + b2 * z2r
        let numI = b1 * z1i + b2 * z2i
        let denR = 1 + a1 * z1r + a2 * z2r
        let denI = a1 * z1i + a2 * z2i
        return hypot(numR, numI) / hypot(denR, denI)
    }
}

private struct BiquadSection {
    var coefficients: [Float]
    var inputHistory = [[Float]](repeating: [0, 0], count: 2)
    var outputHistory = [[Float]](repeating: [0, 0], count: 2)

    mutating func resetDelays() {
        inputHistory = [[0, 0], [0, 0]]
        outputHistory = [[0, 0], [0, 0]]
    }

    mutating func apply(input: [Float], output: inout [Float], frames: Int, channelIndex: Int) {
        output[0] = outputHistory[channelIndex][0]
        output[1] = outputHistory[channelIndex][1]
        var localInput = input
        localInput[0] = inputHistory[channelIndex][0]
        localInput[1] = inputHistory[channelIndex][1]

        localInput.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                coefficients.withUnsafeBufferPointer { coeffs in
                    vDSP_deq22(
                        inBuf.baseAddress!,
                        1,
                        coeffs.baseAddress!,
                        outBuf.baseAddress!,
                        1,
                        vDSP_Length(frames)
                    )
                }
            }
        }

        inputHistory[channelIndex][0] = localInput[frames]
        inputHistory[channelIndex][1] = localInput[frames + 1]
        outputHistory[channelIndex][0] = output[frames]
        outputHistory[channelIndex][1] = output[frames + 1]
    }
}

private struct Complex {
    var re: Double
    var im: Double

    static func + (lhs: Complex, rhs: Complex) -> Complex {
        Complex(re: lhs.re + rhs.re, im: lhs.im + rhs.im)
    }

    static func - (lhs: Complex, rhs: Complex) -> Complex {
        Complex(re: lhs.re - rhs.re, im: lhs.im - rhs.im)
    }

    static func * (lhs: Complex, rhs: Complex) -> Complex {
        Complex(re: lhs.re * rhs.re - lhs.im * rhs.im, im: lhs.re * rhs.im + lhs.im * rhs.re)
    }

    static func * (lhs: Complex, rhs: Double) -> Complex {
        Complex(re: lhs.re * rhs, im: lhs.im * rhs)
    }

    static func / (lhs: Complex, rhs: Complex) -> Complex {
        let denom = rhs.re * rhs.re + rhs.im * rhs.im
        return Complex(
            re: (lhs.re * rhs.re + lhs.im * rhs.im) / denom,
            im: (lhs.im * rhs.re - lhs.re * rhs.im) / denom
        )
    }

    static func / (lhs: Complex, rhs: Double) -> Complex {
        Complex(re: lhs.re / rhs, im: lhs.im / rhs)
    }

    var squareRoot: Complex {
        let magnitude = hypot(re, im)
        if magnitude == 0 { return Complex(re: 0, im: 0) }
        return Complex(
            re: sqrt((magnitude + re) / 2),
            im: copysign(sqrt((magnitude - re) / 2), im)
        )
    }
}
