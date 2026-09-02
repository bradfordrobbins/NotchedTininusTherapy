import Foundation

enum NotchWidth: String, CaseIterable, Identifiable, Codable, Sendable {
    case halfOctave
    case oneOctave

    var id: String { rawValue }

    var octaves: Double {
        switch self {
        case .halfOctave: 0.5
        case .oneOctave: 1.0
        }
    }

    var displayName: String {
        switch self {
        case .halfOctave: "½ Octave"
        case .oneOctave: "1 Octave"
        }
    }
}
