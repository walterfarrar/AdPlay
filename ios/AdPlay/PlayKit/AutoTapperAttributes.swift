import Foundation
import ActivityKit

struct AutoTapperAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progressFraction: Double
        var satsBalance: Int
        var comboMultiplier: Double
        var autoEndsAt: Date?
        var stageTitle: String
    }

    var playerTitle: String
}
