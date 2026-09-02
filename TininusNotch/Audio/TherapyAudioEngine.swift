@preconcurrency import AVFoundation
import Foundation

@MainActor
@Observable
final class TherapyAudioEngine {
    private var engine: AVAudioEngine?
    private let player = AVAudioPlayerNode()
    private let filter = NotchFilter()
    private var didAttachPlayer = false
    private var configurationObserver: NSObjectProtocol?

    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var dspFormat: AVAudioFormat?
    private var playID = UUID()
    private var outstandingBuffers = 0
    private var reachedEOF = false
    private var isStopped = true
    private var isPlaying = false
    private var isGeneratingNoise = false
    private var sampleRate: Double = 44_100

    private let chunkFrames: AVAudioFrameCount = 4_096
    private let maxOutstanding = 5

    var onTrackEnded: (@Sendable () -> Void)?
    var onSpectrum: ((SpectrumSnapshot) -> Void)?
    var spectrum = SpectrumSnapshot.empty

    private let spectrumAnalyzer = SpectrumAnalyzer()

    var isRunning: Bool { engine?.isRunning ?? false }
    var hasActiveSession: Bool { !isStopped }

    func prepare() throws {
        try OutputAudioSession.activate()
        let engine = makeEngineIfNeeded()
        if !didAttachPlayer {
            engine.attach(player)
            didAttachPlayer = true
        }
        observeConfigurationChanges(on: engine)
    }

    func setVolume(_ slider: Float) {
        engine?.mainMixerNode.outputVolume = min(max(slider, 0), 1)
    }

    func updateFilter(frequency: Double, width: NotchWidth) {
        let rate = dspFormat?.sampleRate ?? sampleRate
        filter.update(frequency: frequency, width: width, sampleRate: rate > 0 ? rate : 44_100)
    }

    func play(url: URL, frequency: Double, width: NotchWidth) throws {
        try prepare()
        beginNewPlaySession()

        let engine = makeEngineIfNeeded()
        let file = try AVAudioFile(forReading: url)
        let dspFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: 2,
            interleaved: false
        )!
        self.file = file
        self.dspFormat = dspFormat
        sampleRate = dspFormat.sampleRate
        converter = AVAudioConverter(from: file.processingFormat, to: dspFormat)

        filter.update(frequency: frequency, width: width, sampleRate: dspFormat.sampleRate)
        filter.resetDelays()

        if !didAttachPlayer {
            engine.attach(player)
            didAttachPlayer = true
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: dspFormat)

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }

        isStopped = false
        isPlaying = true
        fillSchedule()
        player.play()
    }

    func playWhiteNoise(frequency: Double, width: NotchWidth) throws {
        try prepare()
        beginNewPlaySession()

        let engine = makeEngineIfNeeded()
        let hardwareRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48_000
        let dspFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: 2,
            interleaved: false
        )!
        self.dspFormat = dspFormat
        sampleRate = rate
        isGeneratingNoise = true

        filter.update(frequency: frequency, width: width, sampleRate: rate)
        filter.resetDelays()

        if !didAttachPlayer {
            engine.attach(player)
            didAttachPlayer = true
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: dspFormat)

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }

        isStopped = false
        isPlaying = true
        fillSchedule()
        player.play()
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func resume() {
        guard !isStopped, let engine else { return }
        isPlaying = true
        if !engine.isRunning {
            try? engine.start()
        }
        fillSchedule()
        player.play()
    }

    func stop() {
        beginNewPlaySession()
    }

    func shutdown() {
        stop()
        engine?.stop()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    func currentTime() -> TimeInterval {
        guard
            let nodeTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: nodeTime)
        else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    private func makeEngineIfNeeded() -> AVAudioEngine {
        if let engine {
            return engine
        }
        let engine = AVAudioEngine()
        _ = engine.mainMixerNode
        self.engine = engine
        return engine
    }

    private func beginNewPlaySession() {
        playID = UUID()
        isStopped = true
        isPlaying = false
        reachedEOF = false
        outstandingBuffers = 0
        player.stop()
        file = nil
        converter = nil
        dspFormat = nil
        isGeneratingNoise = false
        spectrum = .empty
        onSpectrum?(.empty)
    }

    private func fillSchedule() {
        while outstandingBuffers < maxOutstanding, !reachedEOF, !isStopped {
            if !scheduleNextBuffer() {
                break
            }
        }
    }

    private func scheduleNextBuffer() -> Bool {
        if isGeneratingNoise {
            return scheduleNoiseBuffer()
        }
        guard let file, let dspFormat, let converter else { return false }

        let remaining = file.length - file.framePosition
        if remaining <= 0 {
            reachedEOF = true
            return false
        }

        let framesToRead = min(AVAudioFrameCount(remaining), chunkFrames)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: framesToRead
        ) else {
            return false
        }

        do {
            try file.read(into: sourceBuffer, frameCount: framesToRead)
        } catch {
            reachedEOF = true
            return false
        }
        guard sourceBuffer.frameLength > 0 else {
            reachedEOF = true
            return false
        }

        let ratio = dspFormat.sampleRate / file.processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount((Double(sourceBuffer.frameLength) * max(ratio, 1) + 64).rounded(.up))
        guard let playBuffer = AVAudioPCMBuffer(pcmFormat: dspFormat, frameCapacity: outCapacity) else {
            return false
        }

        var conversionError: NSError?
        let input = ConverterInput(buffer: sourceBuffer)
        let status = converter.convert(to: playBuffer, error: &conversionError) { _, outStatus in
            input.next(outStatus)
        }
        if status == .error || playBuffer.frameLength == 0 {
            reachedEOF = true
            return false
        }

        let preDB = spectrumAnalyzer.decibels(from: playBuffer)
        filter.process(playBuffer)
        let postDB = spectrumAnalyzer.decibels(from: playBuffer)
        spectrum = spectrumAnalyzer.makeSnapshot(
            preDB: preDB,
            postDB: postDB,
            sampleRate: dspFormat.sampleRate
        )
        onSpectrum?(spectrum)

        let currentPlayID = playID
        let isLast = file.framePosition >= file.length
        if isLast {
            reachedEOF = true
        }

        outstandingBuffers += 1
        player.scheduleBuffer(playBuffer) { [weak self] in
            Task { @MainActor in
                self?.bufferFinished(playID: currentPlayID, wasLast: isLast)
            }
        }
        return true
    }

    private func scheduleNoiseBuffer() -> Bool {
        guard let dspFormat else { return false }
        guard let playBuffer = AVAudioPCMBuffer(pcmFormat: dspFormat, frameCapacity: chunkFrames) else {
            return false
        }
        playBuffer.frameLength = chunkFrames
        fillWhiteNoise(playBuffer, amplitude: 0.14)

        let preDB = spectrumAnalyzer.decibels(from: playBuffer)
        filter.process(playBuffer)
        let postDB = spectrumAnalyzer.decibels(from: playBuffer)
        spectrum = spectrumAnalyzer.makeSnapshot(
            preDB: preDB,
            postDB: postDB,
            sampleRate: dspFormat.sampleRate
        )
        onSpectrum?(spectrum)

        let currentPlayID = playID
        outstandingBuffers += 1
        player.scheduleBuffer(playBuffer) { [weak self] in
            Task { @MainActor in
                self?.bufferFinished(playID: currentPlayID, wasLast: false)
            }
        }
        return true
    }

    private func fillWhiteNoise(_ buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frames {
                channels[channel][frame] = Float.random(in: -1...1) * amplitude
            }
        }
    }

    private func bufferFinished(playID: UUID, wasLast: Bool) {
        guard playID == self.playID else { return }
        outstandingBuffers = max(0, outstandingBuffers - 1)
        if wasLast, outstandingBuffers == 0 {
            isPlaying = false
            onTrackEnded?()
            return
        }
        if isPlaying, !isStopped {
            fillSchedule()
        }
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
        guard isPlaying, let engine else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }
}

/// `AVAudioConverter.convert` invokes this synchronously, but the callback is `@Sendable`.
private final class ConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var didSupply = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if didSupply {
            outStatus.pointee = .noDataNow
            return nil
        }
        didSupply = true
        outStatus.pointee = .haveData
        return buffer
    }
}
