import Foundation

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let frequency = "tinnitusFrequency"
        static let notchWidth = "notchWidth"
        static let toneVolume = "toneVolume"
        static let musicVolume = "musicVolume"
        static let folderBookmark = "folderBookmark"
        static let hasSavedFrequency = "hasSavedFrequency"
        static let therapySource = "therapySource"
    }

    var tinnitusFrequency: Double {
        didSet { UserDefaults.standard.set(tinnitusFrequency, forKey: Keys.frequency) }
    }

    var hasSavedFrequency: Bool {
        didSet { UserDefaults.standard.set(hasSavedFrequency, forKey: Keys.hasSavedFrequency) }
    }

    var notchWidth: NotchWidth {
        didSet { UserDefaults.standard.set(notchWidth.rawValue, forKey: Keys.notchWidth) }
    }

    var toneVolume: Float {
        didSet { UserDefaults.standard.set(toneVolume, forKey: Keys.toneVolume) }
    }

    var musicVolume: Float {
        didSet { UserDefaults.standard.set(musicVolume, forKey: Keys.musicVolume) }
    }

    var folderBookmark: Data? {
        didSet { UserDefaults.standard.set(folderBookmark, forKey: Keys.folderBookmark) }
    }

    var therapySource: TherapySource {
        didSet { UserDefaults.standard.set(therapySource.rawValue, forKey: Keys.therapySource) }
    }

    init() {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: Keys.frequency)
        tinnitusFrequency = stored > 0 ? stored : FrequencyRange.defaultFrequency
        hasSavedFrequency = defaults.bool(forKey: Keys.hasSavedFrequency)
        if let raw = defaults.string(forKey: Keys.notchWidth), let width = NotchWidth(rawValue: raw) {
            notchWidth = width
        } else {
            notchWidth = .halfOctave
        }
        toneVolume = (defaults.object(forKey: Keys.toneVolume) as? Float) ?? 0.35
        musicVolume = (defaults.object(forKey: Keys.musicVolume) as? Float) ?? 0.7
        folderBookmark = defaults.data(forKey: Keys.folderBookmark)
        if let raw = defaults.string(forKey: Keys.therapySource), let source = TherapySource(rawValue: raw) {
            therapySource = source
        } else {
            therapySource = .music
        }
    }

    func saveFrequency(_ hz: Double) {
        tinnitusFrequency = hz
        hasSavedFrequency = true
    }
}

enum FrequencyRange {
    static let minimum: Double = 200
    static let maximum: Double = 16_000
    static let defaultFrequency: Double = 4_000

    static func clamp(_ hz: Double) -> Double {
        min(max(hz, minimum), maximum)
    }
}
