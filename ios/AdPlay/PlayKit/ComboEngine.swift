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
        return max(0, Int((mx / s) + 0.5))
    }

    func ringMaxValue(_ ring: Int) -> Double {
        guard ring >= 0, ring < ringMax.count else { return 0 }
        return max(0, ringMax[ring])
    }

    func multiplier(of state: ComboState) -> Double {
        let b = base > 0 ? base : 1
        let cap = absMax > 0 ? absMax : 3
        var bonus = 0.0
        for r in state.rings { bonus += r.contribution }
        return nice(min(cap, b + bonus))
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
            if isAtMax(cur, ring: i, t: t) { return 1 }
            return clamp01(cur.rings[i].meter)
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
        var cur = normalize(state, t: t)
        guard let last = cur.lastTapAt else { return cur }
        if now <= last { return cur }
        let grace = max(0, t.idleGraceSeconds)
        let dt = now.timeIntervalSince(last)
        if dt <= grace {
            return applyDrain(cur, amount: drainAmount(dt, idle: false, t: t), t: t)
        }
        let afterGrace = applyDrain(cur, amount: drainAmount(grace, idle: false, t: t), t: t)
        return applyDrain(afterGrace, amount: drainAmount(dt - grace, idle: true, t: t), t: t)
    }

    static func applyTap(_ state: ComboState, now: Date, tunables t: ComboTunables) -> ComboState {
        var cur = at(state, now: now, tunables: t)
        let per = max(1, t.tapsPerLevel)
        addFill(&cur, ring: 0, amount: 1 / Double(per), t: t)
        cur.lastTapAt = now
        return cur
    }

    private static func nice(_ n: Double) -> Double {
        (n * 1e8).rounded() / 1e8
    }

    private static func clamp01(_ n: Double) -> Double {
        min(1, max(0, n))
    }

    private static func normalize(_ state: ComboState, t: ComboTunables) -> ComboState {
        var rings: [ComboRingState] = []
        for i in 0..<ComboTunables.ringCount {
            let src = i < state.rings.count ? state.rings[i] : .empty
            let level = max(0, src.level)
            var contrib = max(0, src.contribution)
            if contrib <= 0 && level > 0 {
                contrib = derivedContribution(level: level, ring: i, t: t)
            }
            rings.append(ComboRingState(meter: clamp01(src.meter), level: level, contribution: nice(contrib)))
        }
        return ComboState(rings: rings, lastTapAt: state.lastTapAt)
    }

    private static func derivedContribution(level: Int, ring: Int, t: ComboTunables) -> Double {
        let step = t.step > 0 ? t.step : 0.1
        let ml = t.maxLevels(ring: ring)
        let stepLv = min(level, ml)
        let overflowLv = max(0, level - ml)
        return nice(Double(stepLv) * step + Double(overflowLv) * overflowStep(innerMaxed: 0, t: t))
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
        let exp = 1 + max(0, innerMaxed)
        return nice(step / pow(10, Double(exp)))
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
        let cap = t.absMax > 0 ? t.absMax : 3
        let base = t.base > 0 ? t.base : 1
        let room = max(0, cap - base - totalBonus(state))
        let applied = min(inc, room)
        state.rings[ring].level += 1
        state.rings[ring].contribution = nice(state.rings[ring].contribution + applied)
        if ring + 1 < ComboTunables.ringCount {
            let per = max(1, t.maxLevels(ring: ring))
            addFill(&state, ring: ring + 1, amount: 1 / Double(per), t: t)
        }
    }

    private static func addFill(_ state: inout ComboState, ring: Int, amount: Double, t: ComboTunables) {
        if t.maxLevels(ring: ring) <= 0 || amount <= 0 { return }
        state.rings[ring].meter = nice(state.rings[ring].meter + amount)
        while state.rings[ring].meter >= 1 - 1e-12 {
            state.rings[ring].meter = nice(state.rings[ring].meter - 1)
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
        state.rings[ring].contribution = nice(max(0, state.rings[ring].contribution - inc))
        if state.rings[ring].level < ml {
            state.rings[ring].contribution = nice(min(state.rings[ring].contribution, Double(state.rings[ring].level) * step))
        } else if state.rings[ring].level == ml {
            state.rings[ring].contribution = nice(min(state.rings[ring].contribution, t.ringMaxValue(ring)))
        }
        if state.rings[ring].level <= 0 {
            state.rings[ring].level = 0
            state.rings[ring].contribution = 0
        }
        if ring + 1 < ComboTunables.ringCount {
            let per = max(1, t.maxLevels(ring: ring))
            unwindFill(&state, ring: ring + 1, amount: 1 / Double(per), t: t)
        }
    }

    private static func unwindFill(_ state: inout ComboState, ring: Int, amount: Double, t: ComboTunables) {
        if t.maxLevels(ring: ring) <= 0 || amount <= 0 { return }
        state.rings[ring].meter = nice(state.rings[ring].meter - amount)
        while state.rings[ring].meter < -1e-12 {
            if state.rings[ring].level <= 0 {
                state.rings[ring].meter = 0
                break
            }
            reverseCompletion(&state, ring: ring, t: t)
            state.rings[ring].meter = nice(state.rings[ring].meter + 1)
        }
    }

    private static func peelRing(_ state: inout ComboState, ring: Int, t: ComboTunables) {
        reverseCompletion(&state, ring: ring, t: t)
        state.rings[ring].meter = 1
    }

    private static func drainAmount(_ dt: TimeInterval, idle: Bool, t: ComboTunables) -> Double {
        let rate = idle ? t.drainPerSecondIdle : t.drainPerSecondActive
        return max(0, dt) * max(0, rate)
    }

    private static func applyDrain(_ state: ComboState, amount: Double, t: ComboTunables) -> ComboState {
        var next = normalize(state, t: t)
        var remain = max(0, amount)
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
                let take = min(next.rings[i].meter, remain)
                next.rings[i].meter = nice(next.rings[i].meter - take)
                remain = nice(remain - take)
            } else if next.rings[i].level > 0 {
                peelRing(&next, ring: i, t: t)
            } else {
                break
            }
        }
        return next
    }
}
