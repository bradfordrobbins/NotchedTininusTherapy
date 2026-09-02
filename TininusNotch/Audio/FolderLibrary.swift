import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum FolderLibrary {
    static let audioTypes: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"]

    static func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
        return url
    }

    static func scan(folder: URL) async -> [Track] {
        let urls = collectAudioURLs(in: folder)
        var tracks: [Track] = []
        for url in urls {
            if let track = await loadTrack(url: url) {
                tracks.append(track)
            }
        }
        return tracks
    }

    nonisolated private static func collectAudioURLs(in folder: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard audioTypes.contains(ext), ext != "m4p" else { continue }
            urls.append(fileURL)
        }
        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return urls
    }

    private static func loadTrack(url: URL) async -> Track? {
        let asset = AVURLAsset(url: url)
        do {
            if try await asset.load(.hasProtectedContent) {
                return nil
            }
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { return nil }

            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            let metadata = try await asset.load(.commonMetadata)

            var title = url.deletingPathExtension().lastPathComponent
            var artist = "Unknown Artist"
            var artwork: Data?

            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        title = value
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        artist = value
                    }
                case .commonKeyArtwork:
                    artwork = try? await item.load(.dataValue)
                default:
                    break
                }
            }

            return Track(
                url: url,
                title: title,
                artist: artist,
                duration: seconds.isFinite ? seconds : 0,
                artwork: artwork
            )
        } catch {
            return Track(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                artist: "Unknown Artist",
                duration: 0,
                artwork: nil
            )
        }
    }
}
