package com.adplay.app.data

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.round

/** Keep in lockstep with `functions/src/combo.ts`. One tap counter; rings are digits. */
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
    val caps: ComboCaps get() = ComboCaps.from(this)

    fun ringMaxValue(ring: Int): Double =
        if (ring in ringMax.indices) max(0.0, ringMax[ring]) else 0.0

    fun multiplier(state: ComboState): Double = ComboEngine.multiplier(state, this)

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

data class ComboCaps(
    val c0: Int,
    val c1: Int,
    val c2: Int,
    val ml2: Int,
    val maxTaps: Double,
    val ring1Enabled: Boolean,
    val ring2Enabled: Boolean,
) {
    companion object {
        fun from(t: ComboTunables): ComboCaps {
            val step = if (t.step > 0) t.step else 0.1
            val c0 = clampInt(t.tapsPerLevel, 1, 10000)
            val raw1 = ((t.ringMaxValue(0) / step) + 0.5).toInt()
            val raw2 = ((t.ringMaxValue(1) / step) + 0.5).toInt()
            val ring1Enabled = clampInt(raw1, 0, 100) > 0
            val ring2Enabled = clampInt(raw2, 0, 100) > 0 && t.ringMaxValue(2) > 0
            val c1 = if (ring1Enabled) clampInt(raw1, 1, 100) else 1
            val c2 = if (ring2Enabled) clampInt(raw2, 1, 100) else 1
            val raw3 = ((t.ringMaxValue(2) / step) + 0.5).toInt()
            val ml2 = if (ring2Enabled) clampInt(raw3, 1, 100) else 0
            return ComboCaps(
                c0 = c0,
                c1 = c1,
                c2 = c2,
                ml2 = ml2,
                maxTaps = c0.toDouble() * c1.toDouble() * c2.toDouble(),
                ring1Enabled = ring1Enabled,
                ring2Enabled = ring2Enabled,
            )
        }
    }
}

data class ComboPersist(
    val taps: Double,
    val meter0: Double,
    val level0: Int,
    val contrib0: Double,
    val meter1: Double,
    val level1: Int,
    val contrib1: Double,
    val meter2: Double,
    val level2: Int,
    val contrib2: Double,
)

data class ComboState(
    val taps: Double = 0.0,
    val lastTapAtMs: Long? = null,
)

private fun clampInt(n: Int, lo: Int, hi: Int): Int = min(hi, max(lo, n))

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

    fun clampTaps(taps: Double, t: ComboTunables): Double {
        val maxTaps = t.caps.maxTaps
        if (!taps.isFinite() || taps <= 0.0) return 0.0
        return if (taps >= maxTaps) maxTaps else taps
    }

    fun tapsFromPersisted(
        comboTaps: Double?,
        comboLevel: Int,
        comboMeter: Double,
        t: ComboTunables,
    ): Double {
        if (comboTaps != null && comboTaps.isFinite()) return clampTaps(comboTaps, t)
        val c0 = t.caps.c0.toDouble()
        val level = max(0, comboLevel)
        return clampTaps(level * c0 + clamp01(comboMeter) * c0, t)
    }

    fun multiplier(state: ComboState, t: ComboTunables): Double {
        val caps = t.caps
        val taps = clampTaps(state.taps, t)
        val base = if (t.base > 0) t.base else 1.0
        val cap = if (t.absMax > 0) t.absMax else 3.0
        val laps = floor(taps / caps.c0).toInt()
        val parts = ringContributions(laps, t)
        return nice(min(cap, base + parts[0] + parts[1] + parts[2]))
    }

    fun ringContributions(laps: Int, t: ComboTunables): List<Double> {
        val caps = t.caps
        val step = if (t.step > 0) t.step else 0.1
        val L = max(0, laps)
        if (L <= 0) return listOf(0.0, 0.0, 0.0)
        val ml0 = caps.c1
        val ml1 = caps.c2
        val ml2 = caps.ml2
        val r1Levels = if (caps.ring1Enabled) L / caps.c1 else 0
        val r2Levels = if (caps.ring2Enabled) L / (caps.c1 * caps.c2) else 0
        val r0Max1 = if (caps.ring1Enabled) (caps.c1 * ml1).toDouble() else Double.POSITIVE_INFINITY
        val r0Max2 = if (caps.ring2Enabled && ml2 > 0) {
            (caps.c1 * caps.c2 * ml2).toDouble()
        } else {
            Double.POSITIVE_INFINITY
        }
        val c0 = ringBonus(L, ml0, step, listOf(r0Max1 to 0, r0Max2 to 1, Double.POSITIVE_INFINITY to 2))
        val r1Max2 = if (caps.ring2Enabled && ml2 > 0) (ml1 * ml2).toDouble() else Double.POSITIVE_INFINITY
        val c1 = if (caps.ring1Enabled) {
            ringBonus(r1Levels, ml1, step, listOf(r1Max2 to 0, Double.POSITIVE_INFINITY to 1))
        } else {
            0.0
        }
        val c2 = if (caps.ring2Enabled) {
            ringBonus(r2Levels, ml2, step, listOf(Double.POSITIVE_INFINITY to 0))
        } else {
            0.0
        }
        return applyBonusRoom(listOf(c0, c1, c2), t)
    }

    private fun overflowStep(innerMaxed: Int, step: Double): Double {
        val exp = 1 + max(0, innerMaxed)
        return nice(step / 10.0.pow(exp.toDouble()))
    }

    private fun ringBonus(
        levels: Int,
        ml: Int,
        step: Double,
        bands: List<Pair<Double, Int>>,
    ): Double {
        if (levels <= 0 || ml <= 0) return 0.0
        val normalLv = min(levels, ml)
        var sum = normalLv * step
        if (levels <= ml) return nice(sum)
        var from = ml.toDouble()
        val lim = levels.toDouble()
        for (band in bands) {
            if (from >= lim) break
            val to = min(lim, band.first)
            if (to > from) sum += (to - from) * overflowStep(band.second, step)
            if (band.first > from) from = band.first
        }
        return nice(sum)
    }

    private fun applyBonusRoom(parts: List<Double>, t: ComboTunables): List<Double> {
        val base = if (t.base > 0) t.base else 1.0
        val cap = if (t.absMax > 0) t.absMax else 3.0
        var room = max(0.0, cap - base)
        return parts.map { raw ->
            val take = min(max(0.0, raw), room)
            room = nice(room - take)
            nice(take)
        }
    }

    fun displayMeters(state: ComboState, t: ComboTunables): List<Double> {
        val caps = t.caps
        val taps = clampTaps(state.taps, t)
        if (taps >= caps.maxTaps - 1e-12) {
            return listOf(1.0, if (caps.ring1Enabled) 1.0 else 0.0, if (caps.ring2Enabled) 1.0 else 0.0)
        }
        val c0 = caps.c0.toDouble()
        val c1 = caps.c1.toDouble()
        val c2 = caps.c2.toDouble()
        val m0 = posMod(taps, c0) / c0
        val laps = floor(taps / c0)
        val m1 = if (caps.ring1Enabled) posMod(laps, c1) / c1 else 0.0
        val inner = floor(taps / (c0 * c1))
        val m2 = if (caps.ring2Enabled) posMod(inner, c2) / c2 else 0.0
        return listOf(clamp01(m0), clamp01(m1), clamp01(m2))
    }

    fun displayTracks(state: ComboState, t: ComboTunables): List<Boolean> {
        val caps = t.caps
        val taps = clampTaps(state.taps, t)
        return listOf(
            taps > 1e-9,
            caps.ring1Enabled && taps >= caps.c0 - 1e-12,
            caps.ring2Enabled && taps >= caps.c0 * caps.c1 - 1e-12,
        )
    }

    fun wouldCompleteOuter(state: ComboState, t: ComboTunables): Boolean {
        val caps = t.caps
        val taps = clampTaps(state.taps, t)
        if (taps >= caps.maxTaps - 1e-12) return false
        return posMod(taps, caps.c0.toDouble()) + 1 >= caps.c0 - 1e-12
    }

    fun at(state: ComboState, nowMs: Long, t: ComboTunables): ComboState {
        val taps = clampTaps(state.taps, t)
        val last = state.lastTapAtMs ?: return ComboState(taps, null)
        if (nowMs <= last) return ComboState(taps, last)
        val grace = max(0.0, t.idleGraceSeconds)
        val dt = (nowMs - last) / 1000.0
        if (dt <= grace) return ComboState(taps, last)
        val rate = max(0.0, t.drainPerSecondIdle) * t.caps.c0
        val drain = (dt - grace) * rate
        if (!drain.isFinite() || drain >= taps) return ComboState(0.0, last)
        return ComboState(clampTaps(taps - drain, t), last)
    }

    fun applyTap(state: ComboState, nowMs: Long, t: ComboTunables): ComboState {
        val cur = at(state, nowMs, t)
        return ComboState(clampTaps(cur.taps + 1, t), nowMs)
    }

    fun persist(state: ComboState, t: ComboTunables): ComboPersist {
        val caps = t.caps
        val taps = clampTaps(state.taps, t)
        val meters = displayMeters(ComboState(taps, state.lastTapAtMs), t)
        val laps0 = floor(taps / caps.c0).toInt()
        val laps1 = floor(taps / (caps.c0 * caps.c1)).toInt()
        val laps2 = floor(taps / (caps.c0.toDouble() * caps.c1 * caps.c2)).toInt()
        val parts = ringContributions(laps0, t)
        return ComboPersist(
            taps = nice(taps),
            meter0 = meters[0],
            level0 = laps0,
            contrib0 = parts[0],
            meter1 = meters[1],
            level1 = laps1,
            contrib1 = parts[1],
            meter2 = meters[2],
            level2 = laps2,
            contrib2 = parts[2],
        )
    }

    private fun clamp01(n: Double): Double =
        if (!n.isFinite() || n <= 0.0) 0.0 else min(1.0, n)

    private fun posMod(a: Double, b: Double): Double {
        if (!(b > 0) || !a.isFinite()) return 0.0
        val r = a % b
        return if (r < 0) r + b else r
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
