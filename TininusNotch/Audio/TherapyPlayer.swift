import Foundation

@MainActor
@Observable
final class TherapyPlayer {
    var tracks: [Track] = []
    var currentIndex: Int?
    var isPlaying = false
    var isLoading = false
    var currentTime: TimeInterval = 0
    var folderName: String?
    var errorMessage: String?
    var hasRestoredFolder = false
    var spectrum = SpectrumSnapshot.empty

    private let engine = TherapyAudioEngine()
    private var progressTask: Task<Void, Never>?
    private var folderAccessURL: URL?
    private let settings: AppSettings
    private let listeningLog: ListeningLog
    private var lastListenTick: Date?
    private var lastEngineTime: TimeInterval = 0
    private var progressGeneration = 0

    init(settings: AppSettings, listeningLog: ListeningLog) {
        self.settings = settings
        self.listeningLog = listeningLog
        engine.onTrackEnded = { [weak self] in
            Task { @MainActor in
                self?.advanceAfterTrackEnd()
            }
        }
        engine.onSpectrum = { [weak self] snapshot in
            self?.spectrum = snapshot
        }
    }

    private var isWhiteNoiseSession = false

    var isNoiseMode: Bool {
        settings.therapySource == .whiteNoise
    }

    var nowPlaying: Track? {
        guard !isNoiseMode, let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    var duration: TimeInterval {
        isNoiseMode ? 0 : (nowPlaying?.duration ?? 0)
    }

    func restoreFolderIfNeeded() async {
        guard !hasRestoredFolder else { return }
        hasRestoredFolder = true
        guard let bookmark = settings.folderBookmark else { return }
        do {
            let url = try FolderLibrary.resolveBookmark(bookmark)
            try await openFolder(url, persistBookmark: false)
        } catch {
            errorMessage = "Could not reopen the saved music folder. Please select it again."
        }
    }

    func openFolder(_ url: URL, persistBookmark: Bool = true) async throws {
        stop()
        releaseFolderAccess()

        let didAccess = url.startAccessingSecurityScopedResource()
        if didAccess {
            folderAccessURL = url
        }

        if persistBookmark {
            settings.folderBookmark = try FolderLibrary.makeBookmark(for: url)
        }

        isLoading = true
        errorMessage = nil
        folderName = url.lastPathComponent
        defer { isLoading = false }

        let scanned = await FolderLibrary.scan(folder: url)
        tracks = scanned
        currentIndex = nil
        currentTime = 0

        if scanned.isEmpty {
            errorMessage = "No playable (non-DRM) audio files were found in this folder."
        }
    }

    func play(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let track = tracks[index]
        do {
            try engine.play(
                url: track.url,
                frequency: settings.tinnitusFrequency,
                width: settings.notchWidth
            )
            engine.setVolume(settings.musicVolume)
            isWhiteNoiseSession = false
            currentIndex = index
            isPlaying = true
            currentTime = 0
            lastListenTick = .now
            lastEngineTime = 0
            errorMessage = nil
            startProgressUpdates()
        } catch {
            errorMessage = "Could not play “\(track.title)”."
            isPlaying = false
        }
    }

    func playWhiteNoise() {
        do {
            try engine.playWhiteNoise(
                frequency: settings.tinnitusFrequency,
                width: settings.notchWidth
            )
            engine.setVolume(settings.musicVolume)
            isWhiteNoiseSession = true
            isPlaying = true
            currentTime = 0
            lastListenTick = .now
            lastEngineTime = 0
            errorMessage = nil
            startProgressUpdates()
        } catch {
            errorMessage = "Could not start white noise."
            isPlaying = false
            isWhiteNoiseSession = false
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isNoiseMode {
            if isWhiteNoiseSession {
                resume()
            } else {
                playWhiteNoise()
            }
        } else if currentIndex != nil {
            resume()
        } else if !tracks.isEmpty {
            play(at: 0)
        }
    }

    func applyTherapySource() {
        let wasPlaying = isPlaying
        let resumeIndex = currentIndex
        stop()
        if isNoiseMode {
            if wasPlaying {
                playWhiteNoise()
            }
        } else if wasPlaying, let index = resumeIndex ?? (tracks.isEmpty ? nil : 0) {
            play(at: index)
        }
    }

    func pause() {
        recordListening(until: .now)
        lastListenTick = nil
        engine.pause()
        isPlaying = false
        listeningLog.flush()
    }

    func resume() {
        lastListenTick = .now
        lastEngineTime = engine.currentTime()
        engine.resume()
        isPlaying = true
        startProgressUpdates()
    }

    func next() {
        guard !tracks.isEmpty else { return }
        let nextIndex = ((currentIndex ?? -1) + 1) % tracks.count
        play(at: nextIndex)
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if currentTime > 3, currentIndex != nil {
            play(at: currentIndex!)
            return
        }
        let previousIndex: Int
        if let currentIndex {
            previousIndex = currentIndex == 0 ? tracks.count - 1 : currentIndex - 1
        } else {
            previousIndex = 0
        }
        play(at: previousIndex)
    }

    func stop() {
        recordListening(until: .now)
        lastListenTick = nil
        progressTask?.cancel()
        progressTask = nil
        engine.stop()
        isPlaying = false
        isWhiteNoiseSession = false
        currentTime = 0
        listeningLog.flush()
    }

    func flushListening() {
        recordListening(until: .now)
        lastListenTick = isPlaying ? .now : nil
        listeningLog.flush()
    }

    func applyFilterSettings() {
        engine.updateFilter(frequency: settings.tinnitusFrequency, width: settings.notchWidth)
    }

    func applyVolume() {
        engine.setVolume(settings.musicVolume)
    }

    func shutdown() {
        stop()
        engine.shutdown()
        releaseFolderAccess()
    }

    private func advanceAfterTrackEnd() {
        guard !isNoiseMode else { return }
        isPlaying = false
        next()
    }

    private func startProgressUpdates() {
        progressGeneration += 1
        let generation = progressGeneration
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, generation == self.progressGeneration else { return }
                if self.isPlaying {
                    self.recordListening(until: .now)
                    self.currentTime = self.engine.currentTime()
                } else {
                    self.lastListenTick = nil
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private func recordListening(until now: Date) {
        guard isPlaying else {
            lastListenTick = nil
            return
        }

        let engineTime = engine.currentTime()
        let playheadMoved: Bool
        if engineTime == 0, lastEngineTime == 0 {
            playheadMoved = engine.isOutputting
        } else {
            playheadMoved = engineTime > lastEngineTime + 0.02 || engineTime < lastEngineTime - 0.25
        }
        lastEngineTime = engineTime

        // Count only while audio is actually advancing. A stalled "playing"
        // session used to keep adding wall-clock time to the calendar.
        guard engine.isOutputting, playheadMoved else {
            lastListenTick = now
            return
        }

        guard let lastListenTick else {
            self.lastListenTick = now
            return
        }
        listeningLog.add(seconds: now.timeIntervalSince(lastListenTick), on: now)
        self.lastListenTick = now
    }

    private func releaseFolderAccess() {
        folderAccessURL?.stopAccessingSecurityScopedResource()
        folderAccessURL = nil
    }
}
