import Foundation

struct GameState: Codable, Equatable {
    var progress: Double
    var unitsPerSat: Int
    var satsBalance: Int
    var tapsRemaining: Int
    var adsRemainingToday: Int
    /** Seconds until the next regenerated ad charge. 0 if full / no regen. */
    var adRegenSecondsLeft: Int?
    /** ISO when the next charge lands. */
    var nextAdChargeAt: String?
    /** -1 means unlimited skip ads this run. */
    var skipAdsRemaining: Int?
    /** Seconds until the next regenerated Skip charge. */
    var skipAdRegenSecondsLeft: Int?
    /** ISO when the next Skip charge lands. */
    var nextSkipAdChargeAt: String?
    var satsEarnedToday: Int
    var dailySatsEarnCap: Int
    var autoFillActive: Bool
    var autoFillUntil: String?
    var fillRate: Double
    var speedBoostActive: Bool
    var speedBoostUntil: String?
    var durationBoostActive: Bool?
    var durationBoostCount: Int?
    var speedBoostCount: Int?
    var tapStrengthBoostCount: Int?
    var tapStrengthActive: Bool?
    var tapStrengthUntil: String?
    var tapPower: Double?
    var comboTaps: Double?
    var comboMeter: Double?
    var comboLevel: Int?
    var comboContrib: Double?
    var comboMeter1: Double?
    var comboLevel1: Int?
    var comboContrib1: Double?
    var comboMeter2: Double?
    var comboLevel2: Int?
    var comboContrib2: Double?
    var lastManualTapAt: String?
    var comboMultiplier: Double?
    var adCooldownSecondsLeft: Int
    var lastBoostType: String?
    var minWithdrawSats: Int
    var resetHourUtc: Int
    var updatedAt: String?

    var progressFraction: Double {
        guard unitsPerSat > 0 else { return 0 }
        return min(1, max(0, progress / Double(unitsPerSat)))
    }

    var effectiveTapPower: Double { tapPower ?? 1 }

    func combo(tunables: ComboTunables = .defaults) -> ComboState {
        ComboState(
            taps: ComboEngine.tapsFromPersisted(
                comboTaps: comboTaps,
                comboLevel: comboLevel ?? 0,
                comboMeter: comboMeter ?? 0,
                tunables: tunables
            ),
            lastTapAt: parseIso8601(lastManualTapAt ?? "")
        )
    }

    var combo: ComboState { combo() }

    var effectiveSkipAdsRemaining: Int { skipAdsRemaining ?? 0 }

    mutating func writeCombo(_ next: ComboState, tunables: ComboTunables = .defaults) {
        let p = ComboEngine.persist(next, tunables: tunables)
        comboTaps = p.taps
        comboMeter = p.meter0
        comboLevel = p.level0
        comboContrib = p.contrib0
        comboMeter1 = p.meter1
        comboLevel1 = p.level1
        comboContrib1 = p.contrib1
        comboMeter2 = p.meter2
        comboLevel2 = p.level2
        comboContrib2 = p.contrib2
        lastManualTapAt = next.lastTapAt.map { iso8601String($0) }
    }

    /// Local preview of one manual tap (matches server `applyManualTapInMemory`).
    func applyingManualTap(tunables: Tunables?, now: Date = Date()) -> GameState {
        var g = self
        guard g.tapsRemaining > 0 else { return g }
        g.tapsRemaining -= 1
        let comboT = ComboTunables.from(tunables)
        let nextCombo = ComboEngine.applyTap(g.combo(tunables: comboT), now: now, tunables: comboT)
        g.writeCombo(nextCombo, tunables: comboT)
        g.comboMultiplier = comboT.multiplier(of: nextCombo)
        let units = max(1, g.unitsPerSat)
        var progress = g.progress + g.effectiveTapPower * comboT.multiplier(of: nextCombo)
        var earned = 0
        let cap = g.dailySatsEarnCap
        while progress >= Double(units) {
            if cap > 0 && g.satsEarnedToday + earned >= cap {
                progress = Double(units) - 0.0001
                break
            }
            progress -= Double(units)
            earned += 1
        }
        g.progress = progress
        g.satsBalance += earned
        g.satsEarnedToday += earned
        return g
    }

    /// Overlay live-tap units (Stronger × combo) plus combo fields from `from`.
    /// Used when a server snapshot omitted combo on progress.
    func takingLiveTapUnits(from: GameState) -> GameState {
        var g = self
        g.progress = from.progress
        g.satsBalance = from.satsBalance
        g.satsEarnedToday = from.satsEarnedToday
        g.comboTaps = from.comboTaps
        g.comboMeter = from.comboMeter
        g.comboLevel = from.comboLevel
        g.comboContrib = from.comboContrib
        g.comboMeter1 = from.comboMeter1
        g.comboLevel1 = from.comboLevel1
        g.comboContrib1 = from.comboContrib1
        g.comboMeter2 = from.comboMeter2
        g.comboLevel2 = from.comboLevel2
        g.comboContrib2 = from.comboContrib2
        g.lastManualTapAt = from.lastManualTapAt
        g.comboMultiplier = from.comboMultiplier
        return g
    }

    var longerBoostActive: Bool { durationBoostActive ?? false }

    var longerBoostCount: Int { durationBoostCount ?? 0 }
    var fasterBoostCount: Int { speedBoostCount ?? 0 }
    var strongerBoostCount: Int { tapStrengthBoostCount ?? 0 }

    static let empty = GameState(
        progress: 0,
        unitsPerSat: 1000,
        satsBalance: 0,
        tapsRemaining: 0,
        adsRemainingToday: 0,
        adRegenSecondsLeft: 0,
        nextAdChargeAt: nil,
        skipAdsRemaining: 0,
        skipAdRegenSecondsLeft: 0,
        nextSkipAdChargeAt: nil,
        satsEarnedToday: 0,
        dailySatsEarnCap: 0,
        autoFillActive: false,
        autoFillUntil: nil,
        fillRate: 0,
        speedBoostActive: false,
        speedBoostUntil: nil,
        durationBoostActive: false,
        durationBoostCount: 0,
        speedBoostCount: 0,
        tapStrengthBoostCount: 0,
        tapStrengthActive: false,
        tapStrengthUntil: nil,
        tapPower: 1,
        comboTaps: 0,
        comboMeter: 0,
        comboLevel: 0,
        comboContrib: 0,
        comboMeter1: 0,
        comboLevel1: 0,
        comboContrib1: 0,
        comboMeter2: 0,
        comboLevel2: 0,
        comboContrib2: 0,
        lastManualTapAt: nil,
        comboMultiplier: 1,
        adCooldownSecondsLeft: 0,
        lastBoostType: nil,
        minWithdrawSats: 100,
        resetHourUtc: 8,
        updatedAt: nil
    )
}

struct Tunables: Codable, Equatable {
    var unitsPerSat: Int
    var tapUnits: Int
    var dailyTapCap: Int
    var durationBoostSeconds: Int
    var speedBoostAmount: Double
    var speedBoostSeconds: Int
    var tapStrengthBoostAmount: Double?
    var tapStrengthBoostSeconds: Int?
    var adCooldownSeconds: Int
    var dailyAdCap: Int?
    var adsPerCycle: Int?
    /** Seconds between +1 ad charge. 0 = no timed regen. */
    var adRegenSeconds: Int?
    var skipTimeSeconds: Int?
    /** 0 = unlimited; -1 = disabled (Skip Time hidden). */
    var skipAdsPerCycle: Int?
    var dailySatsEarnCap: Int
    var minWithdrawSats: Int
    var resetHourUtc: Int
    var adProvider: String
    var debugReset: Bool?
    var comboTapsPerLevel: Int?
    var comboStep: Double?
    var comboMax: Double?
    var comboBase: Double?
    var comboAbsMax: Double?
    var comboRing0Max: Double?
    var comboRing1Max: Double?
    var comboRing2Max: Double?
    var comboIdleGraceSeconds: Double?
    var comboDrainPerSecondActive: Double?
    var comboDrainPerSecondIdle: Double?
    /// Lifetime sats to unlock miner levels 1–10. Invalid values use shipped defaults.
    var minerStageThresholds: [Int]?
}

enum BoostType: String, Codable {
    case activate
    case duration
    case speed
    case tapStrength = "tap_strength"
    case skipTime = "skip_time"
}

struct Withdrawal: Codable, Identifiable, Equatable {
    let id: String
    let amountSats: Int?
    let amount_sats: Int?
    let bolt11: String?
    let status: String
    let admin_note: String?
    let adminNote: String?
    let created_at: String?
    let createdAt: String?

    var sats: Int { amountSats ?? amount_sats ?? 0 }
}
