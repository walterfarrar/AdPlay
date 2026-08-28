package com.adplay.app.data

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.round

/** Keep in lockstep with `functions/src/combo.ts`. Auto / offline never use this. */
data class ComboTunables(
    val tapsPerLevel: Int = 100,
    val step: Double = 0.1,
    val base: Double = 1.0,
    val absMax: Double = 3.0,
    val ringMax: List<Double> = listOf(1.0, 1.0, 1.0),
    val idleGraceSeconds: Double = 1.5,
    val drainPerSecondActive: Double = 0.002,
    val drainPerSecondIdle: Double = 0.5,
) {
    fun maxLevels(ring: Int): Int {
        val mx = ringMaxValue(ring)
        if (mx <= 0.0) return 0
        val s = if (step > 0) step else 0.1
        return max(0, ((mx / s) + 0.5).toInt())
    }

    fun ringMaxValue(ring: Int): Double =
        if (ring in ringMax.indices) max(0.0, ringMax[ring]) else 0.0

    fun multiplier(state: ComboState): Double {
        val b = if (base > 0) base else 1.0
        val cap = if (absMax > 0) absMax else 3.0
        val bonus = state.rings.sumOf { it.contribution }
        return ComboEngine.nice(min(cap, b + bonus))
    }

    companion object {
        const val RING_COUNT = 3
        val defaults = ComboTunables()

        fun from(t: Tunables?): ComboTunables {
            if (t == null) return defaults
            return ComboTunables(
                tapsPerLevel = t.comboTapsPerLevel.takeIf { it > 0 } ?: defaults.tapsPerLevel,
                step = t.comboStep.takeIf { it > 0 } ?: defaults.step,
                base = t.comboBase.takeIf { it > 0 } ?: defaults.base,
                absMax = t.comboAbsMax?.takeIf { it > 0 } ?: defaults.absMax,
                ringMax = listOf(
                    t.comboRing0Max ?: defaults.ringMax[0],
                    t.comboRing1Max ?: defaults.ringMax[1],
                    t.comboRing2Max ?: defaults.ringMax[2],
                ),
                idleGraceSeconds = t.comboIdleGraceSeconds.takeIf { it > 0 }
                    ?: defaults.idleGraceSeconds,
                drainPerSecondActive = t.comboDrainPerSecondActive.takeIf { it >= 0 }
                    ?: defaults.drainPerSecondActive,
                drainPerSecondIdle = t.comboDrainPerSecondIdle.takeIf { it >= 0 }
                    ?: defaults.drainPerSecondIdle,
            )
        }
    }
}

data class ComboRingState(
    val meter: Double = 0.0,
    val level: Int = 0,
    val contribution: Double = 0.0,
)

data class ComboState(
    val rings: List<ComboRingState> = List(ComboTunables.RING_COUNT) { ComboRingState() },
    val lastTapAtMs: Long? = null,
) {
    val meter: Double get() = rings.getOrNull(0)?.meter ?: 0.0
    val level: Int get() = rings.getOrNull(0)?.level ?: 0
}

object ComboEngine {
    fun nice(n: Double): Double = round(n * 1e8) / 1e8

    fun formatMultiplier(m: Double): String {
        if (m <= 1.001) return ""
        val tenths = Math.round(m * 10.0) / 10.0
        if (kotlin.math.abs(m - tenths) < 5e-4) return String.format("×%.1f", tenths)
        val hundredths = Math.round(m * 100.0) / 100.0
        if (kotlin.math.abs(m - hundredths) < 5e-5) return String.format("×%.2f", hundredths)
        val thousandths = Math.round(m * 1000.0) / 1000.0
        if (kotlin.math.abs(m - thousandths) < 5e-6) return String.format("×%.3f", thousandths)
        return String.format("×%.4f", Math.round(m * 10000.0) / 10000.0)
    }

    fun displayMeters(state: ComboState, t: ComboTunables): List<Double> {
        val cur = normalize(state, t)
        return (0 until ComboTunables.RING_COUNT).map { i ->
            if (t.maxLevels(i) <= 0) 0.0
            else clamp01(cur.rings[i].meter)
        }
    }

    fun displayTracks(state: ComboState, t: ComboTunables): List<Boolean> {
        val cur = normalize(state, t)
        val meters = displayMeters(cur, t)
        return (0 until ComboTunables.RING_COUNT).map { i ->
            when {
                t.maxLevels(i) <= 0 -> false
                meters[i] > 0.001 -> true
                isAtMax(cur, i, t) -> true
                else -> cur.rings[i].level > 0 || cur.rings[i].contribution > 1e-12
            }
        }
    }

    fun at(state: ComboState, nowMs: Long, t: ComboTunables): ComboState {
        var cur = normalize(state, t)
        val last = cur.lastTapAtMs ?: return cur
        if (nowMs <= last) return cur
        val grace = max(0.0, t.idleGraceSeconds)
        val dt = (nowMs - last) / 1000.0
        if (dt <= grace) {
            return applyDrain(cur, drainAmount(dt, idle = false, t), t)
        }
        val afterGrace = applyDrain(cur, drainAmount(grace, idle = false, t), t)
        return applyDrain(afterGrace, drainAmount(dt - grace, idle = true, t), t)
    }

    fun applyTap(state: ComboState, nowMs: Long, t: ComboTunables): ComboState {
        var cur = at(state, nowMs, t)
        val per = max(1, t.tapsPerLevel)
        cur = addFill(cur, 0, 1.0 / per, t)
        return cur.copy(lastTapAtMs = nowMs)
    }

    private fun clamp01(n: Double) = min(1.0, max(0.0, n))

    private fun normalize(state: ComboState, t: ComboTunables): ComboState {
        val rings = (0 until ComboTunables.RING_COUNT).map { i ->
            val src = state.rings.getOrNull(i) ?: ComboRingState()
            val level = max(0, src.level)
            var contrib = max(0.0, src.contribution)
            if (contrib <= 0.0 && level > 0) {
                contrib = derivedContribution(level, i, t)
            }
            ComboRingState(meter = clamp01(src.meter), level = level, contribution = nice(contrib))
        }
        return ComboState(rings = rings, lastTapAtMs = state.lastTapAtMs)
    }

    private fun derivedContribution(level: Int, ring: Int, t: ComboTunables): Double {
        val step = if (t.step > 0) t.step else 0.1
        val ml = t.maxLevels(ring)
        val stepLv = min(level, ml)
        val overflowLv = max(0, level - ml)
        return nice(stepLv * step + overflowLv * overflowStep(0, t))
    }

    private fun isAtMax(state: ComboState, ring: Int, t: ComboTunables): Boolean {
        val ml = t.maxLevels(ring)
        if (ml <= 0) return false
        return state.rings[ring].level >= ml
    }

    private fun innerMaxedCount(state: ComboState, ring: Int, t: ComboTunables): Int {
        var n = 0
        for (j in (ring + 1) until ComboTunables.RING_COUNT) {
            if (isAtMax(state, j, t)) n += 1
        }
        return n
    }

    private fun overflowStep(innerMaxed: Int, t: ComboTunables): Double {
        val step = if (t.step > 0) t.step else 0.1
        val exp = 1 + max(0, innerMaxed)
        return nice(step / 10.0.pow(exp.toDouble()))
    }

    private fun completionIncrement(state: ComboState, ring: Int, t: ComboTunables): Double {
        val ml = t.maxLevels(ring)
        if (state.rings[ring].level < ml) return if (t.step > 0) t.step else 0.1
        return overflowStep(innerMaxedCount(state, ring, t), t)
    }

    private fun totalBonus(state: ComboState): Double = state.rings.sumOf { it.contribution }

    private fun mutate(state: ComboState, ring: Int, transform: (ComboRingState) -> ComboRingState): ComboState {
        val rings = state.rings.toMutableList()
        while (rings.size < ComboTunables.RING_COUNT) rings.add(ComboRingState())
        rings[ring] = transform(rings[ring])
        return state.copy(rings = rings)
    }

    private fun applyCompletion(state: ComboState, ring: Int, t: ComboTunables): ComboState {
        val inc = completionIncrement(state, ring, t)
        val cap = if (t.absMax > 0) t.absMax else 3.0
        val base = if (t.base > 0) t.base else 1.0
        val room = max(0.0, cap - base - totalBonus(state))
        val applied = min(inc, room)
        var next = mutate(state, ring) {
            it.copy(level = it.level + 1, contribution = nice(it.contribution + applied))
        }
        if (ring + 1 < ComboTunables.RING_COUNT) {
            val per = max(1, t.maxLevels(ring))
            next = addFill(next, ring + 1, 1.0 / per, t)
        }
        return next
    }

    private fun addFill(state: ComboState, ring: Int, amount: Double, t: ComboTunables): ComboState {
        if (t.maxLevels(ring) <= 0 || amount <= 0.0) return state
        var cur = mutate(state, ring) { it.copy(meter = nice(it.meter + amount)) }
        while (cur.rings[ring].meter >= 1.0 - 1e-12) {
            cur = mutate(cur, ring) { it.copy(meter = nice(it.meter - 1.0)) }
            cur = applyCompletion(cur, ring, t)
        }
        return cur
    }

    private fun reverseCompletion(state: ComboState, ring: Int, t: ComboTunables): ComboState {
        val r = state.rings[ring]
        if (r.level <= 0) return state
        val ml = t.maxLevels(ring)
        val step = if (t.step > 0) t.step else 0.1
        val inc = if (r.level > ml) overflowStep(innerMaxedCount(state, ring, t), t) else step
        var level = r.level - 1
        var contrib = nice(max(0.0, r.contribution - inc))
        if (level < ml) {
            contrib = nice(min(contrib, level * step))
        } else if (level == ml) {
            contrib = nice(min(contrib, t.ringMaxValue(ring)))
        }
        if (level <= 0) {
            level = 0
            contrib = 0.0
        }
        var next = mutate(state, ring) { it.copy(level = level, contribution = contrib) }
        if (ring + 1 < ComboTunables.RING_COUNT) {
            val per = max(1, t.maxLevels(ring))
            next = unwindFill(next, ring + 1, 1.0 / per, t)
        }
        return next
    }

    private fun unwindFill(state: ComboState, ring: Int, amount: Double, t: ComboTunables): ComboState {
        if (t.maxLevels(ring) <= 0 || amount <= 0.0) return state
        var cur = mutate(state, ring) { it.copy(meter = nice(it.meter - amount)) }
        while (cur.rings[ring].meter < -1e-12) {
            if (cur.rings[ring].level <= 0) {
                cur = mutate(cur, ring) { it.copy(meter = 0.0) }
                break
            }
            cur = reverseCompletion(cur, ring, t)
            cur = mutate(cur, ring) { it.copy(meter = nice(it.meter + 1.0)) }
        }
        return cur
    }

    private fun peelRing(state: ComboState, ring: Int, t: ComboTunables): ComboState {
        val next = reverseCompletion(state, ring, t)
        return mutate(next, ring) { it.copy(meter = 1.0) }
    }

    private fun drainAmount(dt: Double, idle: Boolean, t: ComboTunables): Double {
        val rate = if (idle) t.drainPerSecondIdle else t.drainPerSecondActive
        return max(0.0, dt) * max(0.0, rate)
    }

    private fun applyDrain(state: ComboState, amount: Double, t: ComboTunables): ComboState {
        var next = normalize(state, t)
        var remain = max(0.0, amount)
        while (remain > 1e-12) {
            var i = -1
            for (r in 0 until ComboTunables.RING_COUNT) {
                if (next.rings[r].meter > 1e-12 || next.rings[r].level > 0) {
                    i = r
                    break
                }
            }
            if (i < 0) break
            val ring = next.rings[i]
            if (ring.meter > 1e-12) {
                val take = min(ring.meter, remain)
                next = mutate(next, i) { it.copy(meter = nice(it.meter - take)) }
                remain = nice(remain - take)
            } else if (ring.level > 0) {
                next = peelRing(next, i, t)
            } else {
                break
            }
        }
        return next
    }
}

enum class MinerStage(val title: String) {
    Garage("Spark"),
    Bench("Satoshi Scout"),
    Farm("Farm Hand"),
    Rig("Rig Boss");

    companion object {
        fun from(lifetimeSats: Int): MinerStage = when {
            lifetimeSats >= 500 -> Rig
            lifetimeSats >= 50 -> Farm
            lifetimeSats >= 1 -> Bench
            else -> Garage
        }
    }
}
