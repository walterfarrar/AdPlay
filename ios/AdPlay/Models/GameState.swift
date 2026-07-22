import Foundation

struct GameState: Codable, Equatable {
    var progress: Double
    var unitsPerSat: Int
    var satsBalance: Int
    var tapsRemaining: Int
    var adsRemainingToday: Int
    var satsEarnedToday: Int
    var dailySatsEarnCap: Int
    var autoFillActive: Bool
    var autoFillUntil: String?
    var fillRate: Double
    var speedBoostActive: Bool
    var speedBoostUntil: String?
    var tapStrengthActive: Bool?
    var tapStrengthUntil: String?
    var tapPower: Int?
    var adCooldownSecondsLeft: Int
    var lastBoostType: String?
    var minWithdrawSats: Int
    var resetHourUtc: Int

    var progressFraction: Double {
        guard unitsPerSat > 0 else { return 0 }
        return min(1, max(0, progress / Double(unitsPerSat)))
    }

    var effectiveTapPower: Int { tapPower ?? 1 }

    static let empty = GameState(
        progress: 0,
        unitsPerSat: 1000,
        satsBalance: 0,
        tapsRemaining: 0,
        adsRemainingToday: 0,
        satsEarnedToday: 0,
        dailySatsEarnCap: 400,
        autoFillActive: false,
        autoFillUntil: nil,
        fillRate: 0,
        speedBoostActive: false,
        speedBoostUntil: nil,
        tapStrengthActive: false,
        tapStrengthUntil: nil,
        tapPower: 1,
        adCooldownSecondsLeft: 0,
        lastBoostType: nil,
        minWithdrawSats: 100,
        resetHourUtc: 0
    )
}

struct Tunables: Codable, Equatable {
    var unitsPerSat: Int
    var tapUnits: Int
    var dailyTapCap: Int
    var durationBoostSeconds: Int
    var speedBoostAmount: Double
    var speedBoostSeconds: Int
    var tapStrengthBoostAmount: Int?
    var tapStrengthBoostSeconds: Int?
    var adCooldownSeconds: Int
    var dailyAdCap: Int
    var dailySatsEarnCap: Int
    var minWithdrawSats: Int
    var resetHourUtc: Int
    var adProvider: String
    var debugReset: Bool?
}

enum BoostType: String, Codable {
    case duration
    case speed
    case tapStrength = "tap_strength"
}

struct Withdrawal: Codable, Identifiable, Equatable {
    let id: String
    let amountSats: Int?
    let amount_sats: Int?
    let bolt11: String?
    let status: String
    let admin_note: String?
    let created_at: String?

    var sats: Int { amountSats ?? amount_sats ?? 0 }
}
