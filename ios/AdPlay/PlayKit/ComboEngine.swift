import Foundation

/// Manual-tap odometer combo. Keep in lockstep with `functions/src/combo.ts`.
/// One tap counter; rings are place-value digits. Auto / offline never use this.
struct ComboTunables: Equatable {
    var tapsPerLevel: Int
    var step: Double
    var base: Double
    var absMax: Double
    var ringMax: [Double]
    var idleGraceSeconds: Double
    var drainPerSecondActive: Double
    var drainPerSecondIdle: Double

    static let ringCount = 3

    static let defaults = ComboTunables(
        tapsPerLevel: 100,
        step: 0.1,
        base: 1.0,
        absMax: 3.0,
        ringMax: [1.0, 1.0, 1.0],
        idleGraceSeconds: 1.5,
        drainPerSecondActive: 0.002,
        drainPerSecondIdle: 0.5
    )

    static func from(_ t: Tunables?) -> ComboTunables {
        guard let t else { return .defaults }
        let taps = t.comboTapsPerLevel ?? defaults.tapsPerLevel
        let grace = t.comboIdleGraceSeconds ?? defaults.idleGraceSeconds
        let r0 = t.comboRing0Max ?? defaults.ringMax[0]
        let r1 = t.comboRing1Max ?? defaults.ringMax[1]
        let r2 = t.comboRing2Max ?? defaults.ringMax[2]
        return ComboTunables(
            tapsPerLevel: taps > 0 ? taps : defaults.tapsPerLevel,
            step: t.comboStep ?? defaults.step,
            base: t.comboBase ?? defaults.base,
            absMax: (t.comboAbsMax ?? 0) > 0 ? (t.comboAbsMax ?? defaults.absMax) : defaults.absMax,
            ringMax: [r0, r1, r2],
            idleGraceSeconds: grace > 0 ? grace : defaults.idleGraceSeconds,
            drainPerSecondActive: t.comboDrainPerSecondActive ?? defaults.drainPerSecondActive,
            drainPerSecondIdle: t.comboDrainPerSecondIdle ?? defaults.drainPerSecondIdle
        )
    }

    var caps: ComboCaps { ComboCaps.from(self) }

    func multiplier(of state: ComboState) -> Double {
        ComboEngine.multiplier(state, tunables: self)
    }

    func formatMultiplier(_ m: Double) -> String {
        ComboEngine.formatMultiplier(m)
    }
}

struct ComboCaps: Equatable {
    var c0: Int
    var c1: Int
    var c2: Int
    var ml2: Int
    var maxTaps: Double
    var ring1Enabled: Bool
    var ring2Enabled: Bool

    static func from(_ t: ComboTunables) -> ComboCaps {
        let step = t.step > 0 ? t.step : 0.1
        let c0 = clampInt(t.tapsPerLevel, lo: 1, hi: 10000)
        let r0 = t.ringMaxValue(0)
        let r1 = t.ringMaxValue(1)
        let raw1 = Int(((r0 < 0 ? 0 : r0) / step) + 0.5)
        let raw2 = Int(((r1 < 0 ? 0 : r1) / step) + 0.5)
        let ring1Enabled = clampInt(raw1, lo: 0, hi: 100) > 0
        let ring2Enabled = clampInt(raw2, lo: 0, hi: 100) > 0 && t.ringMaxValue(2) > 0
        let c1 = ring1Enabled ? clampInt(raw1, lo: 1, hi: 100) : 1
        let c2 = ring2Enabled ? clampInt(raw2, lo: 1, hi: 100) : 1
        let r2 = t.ringMaxValue(2)
        let raw3 = Int(((r2 < 0 ? 0 : r2) / step) + 0.5)
        let ml2 = ring2Enabled ? clampInt(raw3, lo: 1, hi: 100) : 0
        return ComboCaps(
            c0: c0,
            c1: c1,
            c2: c2,
            ml2: ml2,
            maxTaps: Double(c0) * Double(c1) * Double(c2),
            ring1Enabled: ring1Enabled,
            ring2Enabled: ring2Enabled
        )
    }
}

extension ComboTunables {
    func ringMaxValue(_ ring: Int) -> Double {
        guard ring >= 0, ring < ringMax.count else { return 0 }
        let v = ringMax[ring]
        return v < 0.0 ? 0.0 : v
    }
}

struct ComboPersist {
    var taps: Double
    var meter0: Double
    var level0: Int
    var contrib0: Double
    var meter1: Double
    var level1: Int
    var contrib1: Double
    var meter2: Double
    var level2: Int
    var contrib2: Double
}

struct ComboState: Equatable {
    var taps: Double
    var lastTapAt: Date?

    static let empty = ComboState(taps: 0, lastTapAt: nil)
}

/// Snap floating combo math. Named to avoid Darwin `nice()` (process priority).
private func roundedMultiplier(_ n: Double) -> Double {
    (n * 1e8).rounded() / 1e8
}

private func clamp01(_ n: Double) -> Double {
    if n.isNaN || n <= 0 { return 0 }
    return n >= 1 ? 1 : n
}

private func clampInt(_ n: Int, lo: Int, hi: Int) -> Int {
    if n < lo { return lo }
    if n > hi { return hi }
    return n
}

private func posMod(_ a: Double, _ b: Double) -> Double {
    if !(b > 0) || !a.isFinite { return 0 }
    let r = a.truncatingRemainder(dividingBy: b)
    return r < 0 ? r + b : r
}

enum ComboEngine {
    static func formatMultiplier(_ m: Double) -> String {
        guard m > 1.001 else { return "" }
        let tenths = (m * 10).rounded() / 10
        if abs(m - tenths) < 5e-4 { return String(format: "×%.1f", tenths) }
        let hundredths = (m * 100).rounded() / 100
        if abs(m - hundredths) < 5e-5 { return String(format: "×%.2f", hundredths) }
        let thousandths = (m * 1000).rounded() / 1000
        if abs(m - thousandths) < 5e-6 { return String(format: "×%.3f", thousandths) }
        return String(format: "×%.4f", (m * 10000).rounded() / 10000)
    }

    static func clampTaps(_ taps: Double, tunables t: ComboTunables) -> Double {
        let maxTaps = t.caps.maxTaps
        if !taps.isFinite || taps <= 0 { return 0 }
        return taps >= maxTaps ? maxTaps : taps
    }

    static func tapsFromPersisted(
        comboTaps: Double?,
        comboLevel: Int,
        comboMeter: Double,
        tunables t: ComboTunables
    ) -> Double {
        if let raw = comboTaps, raw.isFinite {
            return clampTaps(raw, tunables: t)
        }
        let c0 = Double(t.caps.c0)
        let level = comboLevel < 0 ? 0 : comboLevel
        return clampTaps(Double(level) * c0 + clamp01(comboMeter) * c0, tunables: t)
    }

    static func multiplier(_ state: ComboState, tunables t: ComboTunables) -> Double {
        let caps = t.caps
        let taps = clampTaps(state.taps, tunables: t)
        let base = t.base > 0 ? t.base : 1.0
        let cap = t.absMax > 0 ? t.absMax : 3.0
        let laps = Int(taps / Double(caps.c0))
        let parts = ringContributions(laps: laps, tunables: t)
        let bonus = parts.0 + parts.1 + parts.2
        let sum = base + bonus
        return roundedMultiplier(cap < sum ? cap : sum)
    }

    static func ringContributions(laps: Int, tunables t: ComboTunables) -> (Double, Double, Double) {
        let caps = t.caps
        let step = t.step > 0 ? t.step : 0.1
        let L = laps < 0 ? 0 : laps
        if L <= 0 { return (0, 0, 0) }
        let ml0 = caps.c1
        let ml1 = caps.c2
        let ml2 = caps.ml2
        let r1Levels = caps.ring1Enabled ? L / caps.c1 : 0
        let r2Levels = caps.ring2Enabled ? L / (caps.c1 * caps.c2) : 0
        let r0Max1 = caps.ring1Enabled ? Double(caps.c1 * ml1) : Double.infinity
        let r0Max2 = caps.ring2Enabled && ml2 > 0 ? Double(caps.c1 * caps.c2 * ml2) : Double.infinity
        let c0 = ringBonus(
            levels: L,
            ml: ml0,
            step: step,
            bands: [(r0Max1, 0), (r0Max2, 1), (Double.infinity, 2)]
        )
        let r1Max2 = caps.ring2Enabled && ml2 > 0 ? Double(ml1 * ml2) : Double.infinity
        let c1 = caps.ring1Enabled
            ? ringBonus(levels: r1Levels, ml: ml1, step: step, bands: [(r1Max2, 0), (Double.infinity, 1)])
            : 0
        let c2 = caps.ring2Enabled
            ? ringBonus(levels: r2Levels, ml: ml2, step: step, bands: [(Double.infinity, 0)])
            : 0
        return applyBonusRoom(c0, c1, c2, tunables: t)
    }

    private static func overflowStep(innerMaxed: Int, step: Double) -> Double {
        let inner = innerMaxed < 0 ? 0 : innerMaxed
        return roundedMultiplier(step / pow(10, Double(1 + inner)))
    }

    private static func ringBonus(
        levels: Int,
        ml: Int,
        step: Double,
        bands: [(Double, Int)]
    ) -> Double {
        if levels <= 0 || ml <= 0 { return 0 }
        let normalLv = levels < ml ? levels : ml
        var sum = Double(normalLv) * step
        if levels <= ml { return roundedMultiplier(sum) }
        var from = Double(ml)
        let lim = Double(levels)
        for band in bands {
            if from >= lim { break }
            let to = lim < band.0 ? lim : band.0
            if to > from {
                sum += (to - from) * overflowStep(innerMaxed: band.1, step: step)
            }
            if band.0 > from { from = band.0 }
        }
        return roundedMultiplier(sum)
    }

    private static func applyBonusRoom(
        _ a: Double,
        _ b: Double,
        _ c: Double,
        tunables t: ComboTunables
    ) -> (Double, Double, Double) {
        let base = t.base > 0 ? t.base : 1.0
        let cap = t.absMax > 0 ? t.absMax : 3.0
        var room = cap - base
        if room < 0 { room = 0 }
        var out = [a, b, c]
        for i in 0..<3 {
            let raw = out[i] < 0 ? 0 : out[i]
            let take = raw < room ? raw : room
            out[i] = roundedMultiplier(take)
            room = roundedMultiplier(room - take)
        }
        return (out[0], out[1], out[2])
    }

    static func displayMeters(_ state: ComboState, tunables t: ComboTunables) -> [Double] {
        let caps = t.caps
        let taps = clampTaps(state.taps, tunables: t)
        if taps >= caps.maxTaps - 1e-12 {
            return [1, caps.ring1Enabled ? 1 : 0, caps.ring2Enabled ? 1 : 0]
        }
        let c0 = Double(caps.c0)
        let c1 = Double(caps.c1)
        let c2 = Double(caps.c2)
        let m0 = posMod(taps, c0) / c0
        let laps = floor(taps / c0)
        let m1 = caps.ring1Enabled ? posMod(laps, c1) / c1 : 0
        let inner = floor(taps / (c0 * c1))
        let m2 = caps.ring2Enabled ? posMod(inner, c2) / c2 : 0
        return [clamp01(m0), clamp01(m1), clamp01(m2)]
    }

    static func displayTracks(_ state: ComboState, tunables t: ComboTunables) -> [Bool] {
        let caps = t.caps
        let taps = clampTaps(state.taps, tunables: t)
        return [
            taps > 1e-9,
            caps.ring1Enabled && taps >= Double(caps.c0) - 1e-12,
            caps.ring2Enabled && taps >= Double(caps.c0 * caps.c1) - 1e-12,
        ]
    }

    static func wouldCompleteOuter(_ state: ComboState, tunables t: ComboTunables) -> Bool {
        let caps = t.caps
        let taps = clampTaps(state.taps, tunables: t)
        if taps >= caps.maxTaps - 1e-12 { return false }
        return posMod(taps, Double(caps.c0)) + 1 >= Double(caps.c0) - 1e-12
    }

    static func at(_ state: ComboState, now: Date, tunables t: ComboTunables) -> ComboState {
        let taps = clampTaps(state.taps, tunables: t)
        guard let last = state.lastTapAt else {
            return ComboState(taps: taps, lastTapAt: nil)
        }
        if now <= last { return ComboState(taps: taps, lastTapAt: last) }
        let grace = t.idleGraceSeconds < 0 ? 0 : t.idleGraceSeconds
        let dt = now.timeIntervalSince(last)
        if dt <= grace { return ComboState(taps: taps, lastTapAt: last) }
        let rate = (t.drainPerSecondIdle < 0 ? 0 : t.drainPerSecondIdle) * Double(t.caps.c0)
        let drain = (dt - grace) * rate
        if !drain.isFinite || drain >= taps {
            return ComboState(taps: 0, lastTapAt: last)
        }
        return ComboState(taps: clampTaps(taps - drain, tunables: t), lastTapAt: last)
    }

    static func applyTap(_ state: ComboState, now: Date, tunables t: ComboTunables) -> ComboState {
        let cur = at(state, now: now, tunables: t)
        return ComboState(taps: clampTaps(cur.taps + 1, tunables: t), lastTapAt: now)
    }

    static func persist(_ state: ComboState, tunables t: ComboTunables) -> ComboPersist {
        let caps = t.caps
        let taps = clampTaps(state.taps, tunables: t)
        let meters = displayMeters(ComboState(taps: taps, lastTapAt: state.lastTapAt), tunables: t)
        let laps0 = Int(taps / Double(caps.c0))
        let laps1 = Int(taps / Double(caps.c0 * caps.c1))
        let laps2 = Int(taps / Double(caps.c0 * caps.c1 * caps.c2))
        let parts = ringContributions(laps: laps0, tunables: t)
        return ComboPersist(
            taps: roundedMultiplier(taps),
            meter0: meters[0],
            level0: laps0,
            contrib0: parts.0,
            meter1: meters[1],
            level1: laps1,
            contrib1: parts.1,
            meter2: meters[2],
            level2: laps2,
            contrib2: parts.2
        )
    }
}
