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

    private static var lastReloadKey: String?

    static func write(_ payload: Payload) {
        let reloadKey = [
            "\(payload.satsBalance)",
            String(format: "%.1f", payload.progress),
            "\(payload.unitsPerSat)",
            String(format: "%.3f", payload.comboMultiplier),
            payload.stageTitle,
            payload.autoFillUntil.map { String(Int($0.timeIntervalSince1970)) } ?? "",
        ].joined(separator: "|")
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: key)
        }
        guard lastReloadKey != reloadKey else { return }
        lastReloadKey = reloadKey
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> Payload? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
