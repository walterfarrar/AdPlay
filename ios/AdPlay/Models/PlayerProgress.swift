import Foundation

struct AdBankBreakdown: Codable, Equatable {
    var base: Int
    var dailyBonus: Int
    var streakBonus: Int
    var achievementBonus: Int
    var iapBonus: Int
    var max: Int
}

struct DailyGoal: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var current: Int
    var target: Int
    var completed: Bool
    var rewardAds: Int
}

struct Achievement: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var unlocked: Bool
    var grantsSlot: Bool
}

struct PlayerProgress: Codable, Equatable {
    var adBank: AdBankBreakdown
    var loginStreak: Int
    var bestLoginStreak: Int
    var dailyGoals: [DailyGoal]
    var achievements: [Achievement]
    var iapAdsPurchased: Int
    var iapBonusAdsMax: Int

    static let empty = PlayerProgress(
        adBank: AdBankBreakdown(
            base: 5, dailyBonus: 0, streakBonus: 0,
            achievementBonus: 0, iapBonus: 0, max: 5
        ),
        loginStreak: 0,
        bestLoginStreak: 0,
        dailyGoals: [],
        achievements: [],
        iapAdsPurchased: 0,
        iapBonusAdsMax: 5
    )

    var displayedDailyGoals: [DailyGoal] {
        ProgressCatalog.goals(merging: dailyGoals)
    }

    var displayedAchievements: [Achievement] {
        ProgressCatalog.achievements(merging: achievements)
    }

    func takingServer(_ server: PlayerProgress?) -> PlayerProgress {
        guard let server, !server.dailyGoals.isEmpty || !server.achievements.isEmpty else {
            return self
        }
        return server
    }

    func syncedWith(state: GameState, tunables: Tunables?, adsWatched: Int) -> PlayerProgress {
        let cap = max(tunables?.dailyTapCap ?? 500, 1)
        let tapsUsed = max(0, cap - state.tapsRemaining)
        let auto = (state.autoFillActive || state.lastBoostType == "activate") ? 1 : 0
        let next = displayedDailyGoals.map { goal -> DailyGoal in
            let derived: Int
            switch goal.id {
            case "taps", "taps_stretch": derived = tapsUsed
            case "sats": derived = max(0, state.satsEarnedToday)
            case "auto": derived = auto
            case "ads": derived = adsWatched
            default: derived = goal.current
            }
            let current = max(goal.current, derived)
            return DailyGoal(
                id: goal.id,
                title: goal.title,
                current: current,
                target: goal.target,
                completed: current >= goal.target,
                rewardAds: goal.rewardAds
            )
        }
        let daily = min(5, next.filter(\.completed).count)
        var copy = self
        copy.dailyGoals = next
        copy.adBank.dailyBonus = max(copy.adBank.dailyBonus, daily)
        copy.adBank.max = copy.adBank.base + copy.adBank.dailyBonus + copy.adBank.streakBonus
            + copy.adBank.achievementBonus + copy.adBank.iapBonus
        return copy
    }
}

enum ProgressCatalog {
    static let dailyGoals: [DailyGoal] = [
        DailyGoal(id: "taps", title: "Use taps", current: 0, target: 50, completed: false, rewardAds: 1),
        DailyGoal(id: "ads", title: "Watch boost ads", current: 0, target: 3, completed: false, rewardAds: 1),
        DailyGoal(id: "sats", title: "Earn sats", current: 0, target: 1, completed: false, rewardAds: 1),
        DailyGoal(id: "auto", title: "Start Auto Tapper", current: 0, target: 1, completed: false, rewardAds: 1),
        DailyGoal(id: "taps_stretch", title: "Keep tapping", current: 0, target: 200, completed: false, rewardAds: 1),
    ]

    static let goalHowTo: [String: String] = [
        "taps": "Tap the wheel 50 times today.",
        "ads": "Watch 3 boost ads today (Activate, Longer, Faster, Stronger, or Skip Time).",
        "sats": "Fill the wheel and earn 1 sat today.",
        "auto": "Watch Activate to start Auto Tapper today.",
        "taps_stretch": "Tap the wheel 200 times today.",
    ]

    static let achievements: [Achievement] = [
        Achievement(id: "first_sat", title: "First sat", detail: "Fill the wheel until it credits 1 sat.", unlocked: false, grantsSlot: true),
        Achievement(id: "first_auto", title: "Auto Tapper", detail: "Watch Activate to start Auto Tapper for the first time.", unlocked: false, grantsSlot: true),
        Achievement(id: "first_redeem", title: "First payout", detail: "Submit a Lightning redeem and wait until it is marked paid.", unlocked: false, grantsSlot: true),
        Achievement(id: "streak_7", title: "Week streak", detail: "Open AdPlay 7 days in a row (UTC).", unlocked: false, grantsSlot: true),
        Achievement(id: "streak_30", title: "Month streak", detail: "Open AdPlay 30 days in a row (UTC).", unlocked: false, grantsSlot: true),
        Achievement(id: "lifetime_10", title: "10 sats", detail: "Earn 10 sats over your lifetime. Badge only — no extra hold.", unlocked: false, grantsSlot: false),
        Achievement(id: "lifetime_100", title: "100 sats", detail: "Earn 100 sats over your lifetime. Badge only — no extra hold.", unlocked: false, grantsSlot: false),
    ]

    static func goals(merging live: [DailyGoal]) -> [DailyGoal] {
        let byId = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        var seen = Set<String>()
        var out: [DailyGoal] = []
        for template in dailyGoals {
            seen.insert(template.id)
            if let live = byId[template.id] {
                out.append(DailyGoal(
                    id: live.id,
                    title: live.title.isEmpty ? template.title : live.title,
                    current: live.current,
                    target: live.target > 0 ? live.target : template.target,
                    completed: live.completed,
                    rewardAds: live.rewardAds
                ))
            } else {
                out.append(template)
            }
        }
        for extra in live where !seen.contains(extra.id) {
            out.append(extra)
        }
        return out
    }

    static func achievements(merging live: [Achievement]) -> [Achievement] {
        let byId = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        var seen = Set<String>()
        var out: [Achievement] = []
        for template in achievements {
            seen.insert(template.id)
            if let live = byId[template.id] {
                out.append(Achievement(
                    id: live.id,
                    title: live.title.isEmpty ? template.title : live.title,
                    detail: live.detail.isEmpty ? template.detail : live.detail,
                    unlocked: live.unlocked,
                    grantsSlot: live.grantsSlot
                ))
            } else {
                out.append(template)
            }
        }
        for extra in live where !seen.contains(extra.id) {
            out.append(extra)
        }
        return out
    }

    static func howTo(for goal: DailyGoal) -> String {
        if let copy = goalHowTo[goal.id] { return copy }
        return "Reach \(goal.target) to complete this goal."
    }
}
