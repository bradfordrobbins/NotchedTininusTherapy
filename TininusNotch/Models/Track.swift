import Foundation

struct Track: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    var title: String
    var artist: String
    var duration: TimeInterval
    var artwork: Data?
}

enum FrequencyFormat {
    static func hertz(_ value: Double) -> String {
        let rounded = value.rounded()
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return "\(formatter.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))") Hz"
    }
}
