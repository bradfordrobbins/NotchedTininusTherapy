import AVFoundation
import Foundation

final class ToneState: @unchecked Sendable {
    var frequency: Double = FrequencyRange.defaultFrequency
    var amplitude: Float = 0.03
    var phase: Double = 0
    var isRunning = false
}

@MainActor
final class SineToneEngine {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let state = ToneState()
    private var configurationObserver: NSObjectProtocol?

    var isRunning: Bool { engine?.isRunning ?? false }

    func setFrequency(_ hz: Double) {
        state.frequency = FrequencyRange.clamp(hz)
    }

    /// Slider 0...1 mapped through a square curve, capped so the tone stays conservative.
    func setVolume(_ slider: Float) {
        let clamped = min(max(slider, 0), 1)
        state.amplitude = clamped * clamped * 0.22
    }

    func start() throws {
        if engine?.isRunning == true { return }
        try OutputAudioSession.activate()
        let engine = try makeEngineIfNeeded()
        installSourceIfNeeded(on: engine)
        guard sourceNode != nil else {
            throw AudioGraphError.couldNotBuildToneGraph
        }
        state.phase = 0
        state.isRunning = true
        engine.prepare()
        try engine.start()
        observeConfigurationChanges(on: engine)
    }

    func stop() {
        state.isRunning = false
        engine?.stop()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    private func makeEngineIfNeeded() throws -> AVAudioEngine {
        if let engine {
            return engine
        }
        let engine = AVAudioEngine()
        // Accessing the mixer wires it to the default output before start().
        _ = engine.mainMixerNode
        self.engine = engine
        return engine
    }

    private func installSourceIfNeeded(on engine: AVAudioEngine) {
        if sourceNode != nil { return }

        let hardwareRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return
        }

        let node = makeSineSourceNode(state: state, sampleRate: sampleRate, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    private func observeConfigurationChanges(on engine: AVAudioEngine) {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
    }

    private func handleConfigurationChange() {
        guard state.isRunning, let engine else { return }
        engine.stop()
        try? engine.start()
    }
}

enum AudioGraphError: LocalizedError {
    case noOutputDevice
    case couldNotBuildToneGraph

    var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            return "No audio output device is available."
        case .couldNotBuildToneGraph:
            return "Could not set up the tone generator."
        }
    }
}

private func makeSineSourceNode(state: ToneState, sampleRate: Double, format: AVAudioFormat) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        func silence() {
            for buffer in abl {
                guard let data = buffer.mData else { continue }
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        guard state.isRunning else {
            silence()
            return noErr
        }

        let frequency = state.frequency
        let amplitude = state.amplitude
        var phase = state.phase
        let twoPi = 2.0 * Double.pi
        let phaseIncrement = twoPi * frequency / sampleRate
        let frames = Int(frameCount)

        for frame in 0..<frames {
            let sample = Float(sin(phase)) * amplitude
            phase += phaseIncrement
            if phase >= twoPi {
                phase -= twoPi
            }
            for buffer in abl {
                if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    data[frame] = sample
                }
            }
        }
        state.phase = phase
        return noErr
    }
}
