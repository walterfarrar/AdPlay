import Foundation

/// Manual-tap nested combo. Keep in lockstep with `functions/src/combo.ts`.
/// Auto Tapper / offline catch-up never use this.
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

    func maxLevels(ring: Int) -> Int {
        let mx = ringMaxValue(ring)
        if mx <= 0 { return 0 }
        let s = step > 0 ? step : 0.1
        let levels = Int((mx / s) + 0.5)
        return levels < 0 ? 0 : levels
    }

    func ringMaxValue(_ ring: Int) -> Double {
        guard ring >= 0, ring < ringMax.count else { return 0 }
        let v = ringMax[ring]
        return v < 0.0 ? 0.0 : v
    }

    func multiplier(of state: ComboState) -> Double {
        let b = base > 0 ? base : 1.0
        let cap = absMax > 0 ? absMax : 3.0
        var bonus = 0.0
        for r in state.rings { bonus += r.contribution }
        let sum = b + bonus
        return roundedMultiplier(cap < sum ? cap : sum)
    }

    func formatMultiplier(_ m: Double) -> String {
        ComboEngine.formatMultiplier(m)
    }
}

struct ComboRingState: Equatable {
    var meter: Double
    var level: Int
    var contribution: Double

    static let empty = ComboRingState(meter: 0, level: 0, contribution: 0)
}

struct ComboState: Equatable {
    var rings: [ComboRingState]
    var lastTapAt: Date?

    static let empty = ComboState(
        rings: Array(repeating: .empty, count: ComboTunables.ringCount),
        lastTapAt: nil
    )

    var meter: Double { rings.first?.meter ?? 0 }
    var level: Int { rings.first?.level ?? 0 }
}

/// Snap floating combo math. Named to avoid Darwin `nice()` (process priority).
private func roundedMultiplier(_ n: Double) -> Double {
    (n * 1e8).rounded() / 1e8
}

/// Clamp to [0, 1] with Double comparisons only — never Darwin min/max.
private func clampMultiplier(_ n: Double) -> Double {
    let lo = n < 0.0 ? 0.0 : n
    return lo > 1.0 ? 1.0 : lo
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

    static func displayMeters(_ state: ComboState, tunables t: ComboTunables) -> [Double] {
        let cur = normalize(state, t: t)
        return (0..<ComboTunables.ringCount).map { i in
            if t.maxLevels(ring: i) <= 0 { return 0 }
            return clampMultiplier(cur.rings[i].meter)
        }
    }

    static func displayTracks(_ state: ComboState, tunables t: ComboTunables) -> [Bool] {
        let cur = normalize(state, t: t)
        let meters = displayMeters(cur, tunables: t)
        return (0..<ComboTunables.ringCount).map { i in
            if t.maxLevels(ring: i) <= 0 { return false }
            if meters[i] > 0.001 { return true }
            if isAtMax(cur, ring: i, t: t) { return true }
            return cur.rings[i].level > 0 || cur.rings[i].contribution > 1e-12
        }
    }

    static func at(_ state: ComboState, now: Date, tunables t: ComboTunables) -> ComboState {
        let cur = normalize(state, t: t)
        guard let last = cur.lastTapAt else { return cur }
        if now <= last { return cur }
        let grace = t.idleGraceSeconds < 0.0 ? 0.0 : t.idleGraceSeconds
        let dt = now.timeIntervalSince(last)
        if dt <= grace {
            return applyDrain(cur, amount: drainAmount(dt, idle: false, t: t), t: t)
        }
        let afterGrace = applyDrain(cur, amount: drainAmount(grace, idle: false, t: t), t: t)
        return applyDrain(afterGrace, amount: drainAmount(dt - grace, idle: true, t: t), t: t)
    }

    static func applyTap(_ state: ComboState, now: Date, tunables t: ComboTunables) -> ComboState {
        var cur = at(state, now: now, tunables: t)
        let per = t.tapsPerLevel < 1 ? 1 : t.tapsPerLevel
        addFill(&cur, ring: 0, amount: 1 / Double(per), t: t)
        cur.lastTapAt = now
        return cur
    }

    private static func normalize(_ state: ComboState, t: ComboTunables) -> ComboState {
        var rings: [ComboRingState] = []
        for i in 0..<ComboTunables.ringCount {
            let src = i < state.rings.count ? state.rings[i] : .empty
            let level = src.level < 0 ? 0 : src.level
            var contrib = src.contribution < 0.0 ? 0.0 : src.contribution
            if contrib <= 0 && level > 0 {
                contrib = derivedContribution(level: level, ring: i, t: t)
            }
            rings.append(ComboRingState(meter: clampMultiplier(src.meter), level: level, contribution: roundedMultiplier(contrib)))
        }
        return ComboState(rings: rings, lastTapAt: state.lastTapAt)
    }

    private static func derivedContribution(level: Int, ring: Int, t: ComboTunables) -> Double {
        let step = t.step > 0 ? t.step : 0.1
        let ml = t.maxLevels(ring: ring)
        let stepLv = level < ml ? level : ml
        let overflowLv = level - ml < 0 ? 0 : level - ml
        return roundedMultiplier(Double(stepLv) * step + Double(overflowLv) * overflowStep(innerMaxed: 0, t: t))
    }

    private static func isAtMax(_ state: ComboState, ring: Int, t: ComboTunables) -> Bool {
        let ml = t.maxLevels(ring: ring)
        if ml <= 0 { return false }
        return state.rings[ring].level >= ml
    }

    private static func innerMaxedCount(_ state: ComboState, ring: Int, t: ComboTunables) -> Int {
        var n = 0
        var j = ring + 1
        while j < ComboTunables.ringCount {
            if isAtMax(state, ring: j, t: t) { n += 1 }
            j += 1
        }
        return n
    }

    private static func overflowStep(innerMaxed: Int, t: ComboTunables) -> Double {
        let step = t.step > 0 ? t.step : 0.1
        let inner = innerMaxed < 0 ? 0 : innerMaxed
        let exp = 1 + inner
        return roundedMultiplier(step / pow(10, Double(exp)))
    }

    private static func completionIncrement(_ state: ComboState, ring: Int, t: ComboTunables) -> Double {
        let ml = t.maxLevels(ring: ring)
        if state.rings[ring].level < ml { return t.step > 0 ? t.step : 0.1 }
        return overflowStep(innerMaxed: innerMaxedCount(state, ring: ring, t: t), t: t)
    }

    private static func totalBonus(_ state: ComboState) -> Double {
        state.rings.reduce(0) { $0 + $1.contribution }
    }

    private static func applyCompletion(_ state: inout ComboState, ring: Int, t: ComboTunables) {
        let inc = completionIncrement(state, ring: ring, t: t)
        let cap = t.absMax > 0 ? t.absMax : 3.0
        let base = t.base > 0 ? t.base : 1.0
        let roomRaw = cap - base - totalBonus(state)
        let room = roomRaw < 0.0 ? 0.0 : roomRaw
        let applied = inc < room ? inc : room
        state.rings[ring].level += 1
        state.rings[ring].contribution = roundedMultiplier(state.rings[ring].contribution + applied)
        if ring + 1 < ComboTunables.ringCount {
            let perRaw = t.maxLevels(ring: ring)
            let per = perRaw < 1 ? 1 : perRaw
            addFill(&state, ring: ring + 1, amount: 1 / Double(per), t: t)
        }
    }

    private static func addFill(_ state: inout ComboState, ring: Int, amount: Double, t: ComboTunables) {
        if t.maxLevels(ring: ring) <= 0 || amount <= 0 { return }
        state.rings[ring].meter = roundedMultiplier(state.rings[ring].meter + amount)
        while state.rings[ring].meter >= 1 - 1e-12 {
            state.rings[ring].meter = roundedMultiplier(state.rings[ring].meter - 1)
            applyCompletion(&state, ring: ring, t: t)
        }
    }

    private static func reverseCompletion(_ state: inout ComboState, ring: Int, t: ComboTunables) {
        if state.rings[ring].level <= 0 { return }
        let ml = t.maxLevels(ring: ring)
        let step = t.step > 0 ? t.step : 0.1
        let inc = state.rings[ring].level > ml
            ? overflowStep(innerMaxed: innerMaxedCount(state, ring: ring, t: t), t: t)
            : step
        state.rings[ring].level -= 1
        let after = state.rings[ring].contribution - inc
        state.rings[ring].contribution = roundedMultiplier(after < 0.0 ? 0.0 : after)
        if state.rings[ring].level < ml {
            let levelCap = Double(state.rings[ring].level) * step
            let c = state.rings[ring].contribution
            state.rings[ring].contribution = roundedMultiplier(c < levelCap ? c : levelCap)
        } else if state.rings[ring].level == ml {
            let ringCap = t.ringMaxValue(ring)
            let c = state.rings[ring].contribution
            state.rings[ring].contribution = roundedMultiplier(c < ringCap ? c : ringCap)
        }
        if state.rings[ring].level <= 0 {
            state.rings[ring].level = 0
            state.rings[ring].contribution = 0
        }
        if ring + 1 < ComboTunables.ringCount {
            let perRaw = t.maxLevels(ring: ring)
            let per = perRaw < 1 ? 1 : perRaw
            unwindFill(&state, ring: ring + 1, amount: 1 / Double(per), t: t)
        }
    }

    private static func unwindFill(_ state: inout ComboState, ring: Int, amount: Double, t: ComboTunables) {
        if t.maxLevels(ring: ring) <= 0 || amount <= 0 { return }
        state.rings[ring].meter = roundedMultiplier(state.rings[ring].meter - amount)
        while state.rings[ring].meter < -1e-12 {
            if state.rings[ring].level <= 0 {
                state.rings[ring].meter = 0
                break
            }
            reverseCompletion(&state, ring: ring, t: t)
            state.rings[ring].meter = roundedMultiplier(state.rings[ring].meter + 1)
        }
    }

    private static func peelRing(_ state: inout ComboState, ring: Int, t: ComboTunables) {
        reverseCompletion(&state, ring: ring, t: t)
        state.rings[ring].meter = 1
    }

    private static func drainAmount(_ dt: TimeInterval, idle: Bool, t: ComboTunables) -> Double {
        let rate = idle ? t.drainPerSecondIdle : t.drainPerSecondActive
        let dtClamped = dt < 0.0 ? 0.0 : dt
        let rateClamped = rate < 0.0 ? 0.0 : rate
        return dtClamped * rateClamped
    }

    private static func applyDrain(_ state: ComboState, amount: Double, t: ComboTunables) -> ComboState {
        var next = normalize(state, t: t)
        var remain = amount < 0.0 ? 0.0 : amount
        while remain > 1e-12 {
            var i = -1
            var r = 0
            while r < ComboTunables.ringCount {
                if next.rings[r].meter > 1e-12 || next.rings[r].level > 0 {
                    i = r
                    break
                }
                r += 1
            }
            if i < 0 { break }
            if next.rings[i].meter > 1e-12 {
                let meter = next.rings[i].meter
                let take = meter < remain ? meter : remain
                next.rings[i].meter = roundedMultiplier(next.rings[i].meter - take)
                remain = roundedMultiplier(remain - take)
            } else if next.rings[i].level > 0 {
                peelRing(&next, ring: i, t: t)
            } else {
                break
            }
        }
        return next
    }
}
