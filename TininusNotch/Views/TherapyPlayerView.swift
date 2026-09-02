import SwiftUI
import UniformTypeIdentifiers

struct TherapyPlayerView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var player: TherapyPlayer
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sourceSection
                    if !player.isNoiseMode {
                        folderSection
                    }
                    nowPlayingCard
                    transport
                    filterSection
                    SpectrumView(
                        snapshot: player.spectrum,
                        centerFrequency: settings.tinnitusFrequency,
                        width: settings.notchWidth
                    )
                    volumeSection
                    if !player.isNoiseMode {
                        playlist
                    }
                    disclaimer
                }
                .padding(24)
            }
            .navigationTitle("Therapy")
            .toolbar {
                if !player.isNoiseMode {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Choose Folder") {
                            isImporting = true
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPick(result)
            }
            .task {
                await player.restoreFolderIfNeeded()
            }
            .onChange(of: settings.tinnitusFrequency) { _, _ in
                player.applyFilterSettings()
            }
            .onChange(of: settings.notchWidth) { _, _ in
                player.applyFilterSettings()
            }
            .onChange(of: settings.musicVolume) { _, _ in
                player.applyVolume()
            }
            .onChange(of: settings.therapySource) { _, _ in
                player.applyTherapySource()
            }
        }
    }

    private var sourceSection: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.headline)
            Picker("Source", selection: $settings.therapySource) {
                ForEach(TherapySource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            if player.isNoiseMode {
                Text("Continuous stereo white noise, notch-filtered at your tinnitus frequency.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = player.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !settings.hasSavedFrequency {
                Text("No saved tinnitus frequency yet. The player will notch around \(FrequencyFormat.hertz(settings.tinnitusFrequency)) until you save one.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let folderName = player.folderName {
                Label(folderName, systemImage: "folder.fill")
                    .font(.headline)
            } else {
                Text("Choose a folder of your own music files. DRM-protected tracks are skipped; everything else is notch-filtered in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if player.isLoading {
                ProgressView("Scanning folder…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 14) {
            artwork
            if player.isNoiseMode {
                Text("White Noise")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Notched around \(FrequencyFormat.hertz(settings.tinnitusFrequency))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(player.isPlaying ? timeString(player.currentTime) : "Ready")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let track = player.nowPlaying {
                Text(track.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                HStack {
                    Text(timeString(player.currentTime))
                    Spacer()
                    Text(timeString(player.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Text("Nothing playing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(player.tracks.isEmpty ? "Select a folder to begin" : "Choose a track")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 168
        if let data = player.nowPlaying?.artwork, let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                Image(systemName: player.isNoiseMode ? "waveform" : "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: size, height: size)
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            if !player.isNoiseMode {
                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(player.tracks.isEmpty)
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .disabled(!player.isNoiseMode && player.tracks.isEmpty)

            if !player.isNoiseMode {
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(player.tracks.isEmpty)
            }
        }
        .buttonStyle(.plain)
    }

    private var filterSection: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 12) {
            Text("Notch filter")
                .font(.headline)
            Text("Center: \(FrequencyFormat.hertz(settings.tinnitusFrequency))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Width", selection: $settings.notchWidth) {
                ForEach(NotchWidth.allCases) { width in
                    Text(width.displayName).tag(width)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var volumeSection: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 8) {
            Text("Volume")
                .font(.headline)
            Slider(value: $settings.musicVolume, in: 0...1)
        }
    }

    private var playlist: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !player.tracks.isEmpty {
                Text("\(player.tracks.count) tracks")
                    .font(.headline)
                ForEach(Array(player.tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.play(at: index)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.body.weight(index == player.currentIndex ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(timeString(track.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if index < player.tracks.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("This is a self-help listening tool, not medical advice. Use your own non-DRM files. Stop if listening is uncomfortable.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            Task {
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    try await player.openFolder(url)
                } catch {
                    player.errorMessage = "Could not open that folder."
                }
            }
        case .failure:
            break
        }
    }
}

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
