import Foundation
import GameKit

enum GameCenterIds {
    static let firstSat = "com.adplay.app.ach.first_sat"
    static let firstAuto = "com.adplay.app.ach.first_auto"
    static let firstRedeem = "com.adplay.app.ach.first_redeem"
    static let lifetime50 = "com.adplay.app.ach.lifetime_50"
    static let lifetime500 = "com.adplay.app.ach.lifetime_500"
    static let streakBoard = "com.adplay.app.lb.streak"
    static let wheelsBoard = "com.adplay.app.lb.wheels"

    static func achievementId(gameId: String) -> String? {
        switch gameId {
        case "first_sat": return firstSat
        case "first_auto": return firstAuto
        case "first_redeem": return firstRedeem
        case "lifetime_50": return lifetime50
        case "lifetime_500": return lifetime500
        default: return nil
        }
    }
}

@MainActor
enum GameCenterService {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { _, _ in }
    }

    static func report(progress: PlayerProgress) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        var gkAchievements: [GKAchievement] = []
        for a in progress.displayedAchievements where a.unlocked {
            guard let id = GameCenterIds.achievementId(gameId: a.id) else { continue }
            let item = GKAchievement(identifier: id)
            item.percentComplete = 100
            item.showsCompletionBanner = true
            gkAchievements.append(item)
        }
        if !gkAchievements.isEmpty {
            GKAchievement.report(gkAchievements, withCompletionHandler: { _ in })
        }
        GKLeaderboard.submitScore(
            progress.bestLoginStreak,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [GameCenterIds.streakBoard],
            completionHandler: { _ in }
        )
        GKLeaderboard.submitScore(
            progress.lifetimeSats,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [GameCenterIds.wheelsBoard],
            completionHandler: { _ in }
        )
    }
}
