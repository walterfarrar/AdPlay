import Foundation
import WidgetKit

enum PlaySnapshot {
    static let suiteName = "group.com.adplay.app"
    static let key = "adplay.playSnapshot"

    struct Payload: Codable, Hashable {
        var satsBalance: Int
        var progress: Double
        var unitsPerSat: Int
        var autoFillUntil: Date?
        var comboMultiplier: Double
        var stageTitle: String
        var updatedAt: Date
    }

    static func write(_ payload: Payload) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> Payload? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
