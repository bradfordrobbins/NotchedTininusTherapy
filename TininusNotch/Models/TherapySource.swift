import Foundation

enum TherapySource: String, CaseIterable, Identifiable, Codable, Sendable {
    case music
    case whiteNoise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .music: "Music"
        case .whiteNoise: "White Noise"
        }
    }
}
