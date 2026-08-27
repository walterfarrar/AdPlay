import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettings = false
    @State private var showAchievements = false
    @State private var barFlash = false
    @State private var satEarnPrimed = false

    var body: some View {
        let state = session.state
        let look = ThemeLook.named(settings.selectedLookId)

        ZStack {
            AtmosphereBackground(look: look)

            GeometryReader { geo in
                let filled = VStack(spacing: 0) {
                    headerBar
                    earlyAccessHint
                    GeometryReader { mid in
                        let wheel = min(
                            mid.size.width * 0.48,
                            max(CGFloat(160), mid.size.height - 168)
                        )
                        VStack(spacing: 0) {
                            SatEarnStage(
                                satsBalance: state.satsBalance,
                                progress: state.progress,
                                total: state.unitsPerSat,
                                fillRate: state.fillRate,
                                tapPower: state.effectiveTapPower,
                                autoActive: state.autoFillActive,
                                autoFillUntil: state.autoFillUntil,
                                wheelFlash: barFlash,
                                wheelSize: wheel
                            )
                            .padding(.top, 12)
                            tapHint(state: state)
                        }
                        .frame(width: mid.size.width, height: mid.size.height, alignment: .top)
                    }
                    boostsColumn(state: state)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                ViewThatFits(in: .vertical) {
                    filled
                    ScrollView {
                        VStack(spacing: 0) {
                            headerBar
                            earlyAccessHint
                            SatEarnStage(
                                satsBalance: state.satsBalance,
                                progress: state.progress,
                                total: state.unitsPerSat,
                                fillRate: state.fillRate,
                                tapPower: state.effectiveTapPower,
                                autoActive: state.autoFillActive,
                                autoFillUntil: state.autoFillUntil,
                                wheelFlash: barFlash,
                                wheelSize: min(CGFloat(240), geo.size.width * 0.50)
                            )
                            .padding(.top, 20)
                            tapHint(state: state)
                            boostsColumn(state: state)
                        }
                        .frame(width: geo.size.width)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .onChange(of: session.state.satsBalance) { oldValue, newValue in
            guard session.isReady else { return }
            if !satEarnPrimed {
                satEarnPrimed = true
                return
            }
            let gained = newValue - oldValue
            guard gained > 0 else { return }
            flashWheelForSatEarn(gained: gained)
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(showsClose: true)
                .environmentObject(session)
                .environmentObject(settings)
        }
    }

    private func tapHint(state: GameState) -> some View {
        Text(
            state.tapsRemaining > 0
                ? "Tap the wheel · \(state.tapsRemaining) taps left today"
                : "0 taps left today"
        )
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(Color("BrandMuted"))
        .padding(.top, 14)
    }

    private var earlyAccessHint: some View {
        Text(
            "Early access — Lightning payouts are real. Earn rates stay modest while we roll out; " +
                "they can improve as more players join and ad revenue grows."
        )
        .font(.system(size: 12, weight: .regular, design: .rounded))
        .foregroundStyle(Color("BrandMuted"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private var headerBar: some View {
        let look = ThemeLook.named(settings.selectedLookId)
        let lifetimeSats = session.progress.lifetimeSats
        let stageTitle = MinerStage.from(lifetimeSats: lifetimeSats).title
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AdPlay")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("BrandInk"))
                Text(stageTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(look.accent)
            }
            Spacer()
            if session.bypassAdsAvailable {
                Button(session.bypassAds ? "Skip ads" : "Real ads") {
                    session.setBypassAds(!session.bypassAds)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(session.bypassAds ? Color("BrandAccent") : Color("BrandMuted"))
            }
            if session.tunables?.debugReset == true {
                Button("Reset") {
                    Task { await session.debugReset() }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color("BrandMuted"))
            }
            Button {
                showAchievements = true
            } label: {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color("BrandAccent"))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color("BrandAccent").opacity(0.14)))
                    .overlay(Circle().stroke(Color("BrandAccent").opacity(0.55), lineWidth: 1))
            }
            .accessibilityLabel("Achievements")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color("BrandInk"))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color("BrandInk").opacity(0.08)))
                    .overlay(Circle().stroke(Color("BrandInk").opacity(0.25), lineWidth: 1))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func boostsColumn(state: GameState) -> some View {
        let skipEnabled = (session.tunables?.skipAdsPerCycle ?? 10) >= 0
        let skipRemaining = state.effectiveSkipAdsRemaining
        let skipRegenLeft = state.skipAdRegenSecondsLeft ?? 0
        let skipVisible = skipEnabled
            && state.adsRemainingToday <= 0
            && state.autoFillActive
            && (skipRemaining < 0 || skipRemaining > 0 || skipRegenLeft > 0)
        let canSkip = !session.isBusy
            && skipVisible
            && state.adCooldownSecondsLeft == 0
            && (skipRemaining < 0 || skipRemaining > 0)
        let adsMax = session.progress.adBank.max > 0
            ? session.progress.adBank.max
            : (session.tunables?.adsPerCycle ?? 5)

        return VStack(spacing: 0) {
            Text(
                state.autoFillActive
                    ? "Watch an Ad for a Boost"
                    : "Watch an Ad to activate Auto Tapper"
            )
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color("BrandMuted"))
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Group {
                if state.autoFillActive {
                    HStack(spacing: 10) {
                        BoostButton(
                            title: "Longer",
                            actionLabel: formatLongerAction(session.tunables),
                            theme: Color("BrandTime"),
                            running: state.longerBoostActive,
                            applyCount: state.longerBoostCount,
                            disabled: !canWatch
                        ) {
                            Task { await session.watch(boost: .duration) }
                        }
                        BoostButton(
                            title: "Faster",
                            actionLabel: formatFasterAction(session.tunables),
                            theme: Color("BrandAccent"),
                            running: state.speedBoostActive,
                            applyCount: state.fasterBoostCount,
                            disabled: !canWatchSecondary
                        ) {
                            Task { await session.watch(boost: .speed) }
                        }
                        BoostButton(
                            title: "Stronger",
                            actionLabel: formatStrongerAction(session.tunables),
                            theme: Color("BrandPower"),
                            running: state.tapStrengthActive ?? false,
                            applyCount: state.strongerBoostCount,
                            disabled: !canWatchSecondary
                        ) {
                            Task { await session.watch(boost: .tapStrength) }
                        }
                    }
                } else {
                    BoostButton(
                        title: "Activate Auto Tapper",
                        actionLabel: formatLongerAction(session.tunables),
                        theme: Color("BrandTime"),
                        showCount: false,
                        disabled: !canActivate
                    ) {
                        Task { await session.watch(boost: .activate) }
                    }
                }
            }
            .frame(height: sizeClass == .regular ? 108 : 88)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            if let err = session.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            AdsFooterView(
                adsRemaining: state.adsRemainingToday,
                cooldownLeft: state.adCooldownSecondsLeft,
                regenLeft: state.adRegenSecondsLeft ?? 0,
                adsMax: adsMax,
                adRegenSeconds: session.tunables?.adRegenSeconds ?? 0
            )

            ZStack {
                if skipVisible {
                    SkipTimeButton(
                        actionLabel: formatSkipTimeAction(session.tunables),
                        remainingLabel: formatSkipButtonStatus(
                            skipAdsRemaining: skipRemaining,
                            cooldownLeft: state.adCooldownSecondsLeft,
                            regenLeft: skipRegenLeft
                        ),
                        disabled: !canSkip
                    ) {
                        Task { await session.watch(boost: .skipTime) }
                    }
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var canWatch: Bool {
        !session.isBusy
            && session.state.adsRemainingToday > 0
            && session.state.adCooldownSecondsLeft == 0
    }

    /// Free starter ad while idle — does not spend from the boost bank.
    private var canActivate: Bool {
        !session.isBusy
            && !session.state.autoFillActive
            && session.state.adCooldownSecondsLeft == 0
    }

    /// Faster / Stronger unlock once Auto Tapper is running.
    private var canWatchSecondary: Bool {
        canWatch && session.state.autoFillActive
    }

    private func flashWheelForSatEarn(gained: Int) {
        let bursts = min(max(gained, 1), 4)
        for i in 0..<bursts {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                withAnimation(.easeOut(duration: 0.12)) {
                    barFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.45)) {
                        barFlash = false
                    }
                }
            }
        }
    }
}

struct SharedAutoTimerView: View {
    let autoFillUntil: String?
    let autoActive: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = autoActive ? remainingSeconds(untilIso: autoFillUntil, now: context.date) : 0
            Text(left > 0 ? "Auto \(formatCountdown(left))" : " ")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(left > 0 ? Color("BrandTime") : .clear)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }
}

struct AdsFooterView: View {
    let adsRemaining: Int
    let cooldownLeft: Int
    let regenLeft: Int
    let adsMax: Int
    let adRegenSeconds: Int

    var body: some View {
        HStack(spacing: 6) {
            AdSlotIcon(size: 16)
            Text(footerText)
                .font(.caption)
                .foregroundStyle(Color("BrandMuted"))
        }
        .padding(.bottom, 16)
    }

    private var footerText: String {
        if adsRemaining <= 0 {
            if regenLeft > 0 {
                return "Next Boost Ad in \(formatCountdown(regenLeft))"
            }
            if adRegenSeconds <= 0 {
                return "Tokens refill when Auto ends"
            }
            return "No Ad Tokens"
        }
        if cooldownLeft > 0 {
            return "Next Boost Ad in \(cooldownLeft)s · \(adsRemaining)/\(adsMax) tokens"
        }
        if adsRemaining < adsMax, regenLeft > 0 {
            return "\(adsRemaining)/\(adsMax) tokens · +1 in \(formatCountdown(regenLeft))"
        }
        return "\(adsRemaining)/\(adsMax) tokens"
    }
}

/// Live progress toward the next sat, matching local auto-fill interpolation.
private func displayedBarProgress(
    progress: Double,
    total: Int,
    fillRate: Double,
    autoActive: Bool,
    anchorProgress: Double,
    anchorDate: Date,
    now: Date
) -> Double {
    guard autoActive, fillRate > 0, total > 0 else { return progress }
    let elapsed = now.timeIntervalSince(anchorDate)
    return min(Double(total), anchorProgress + fillRate * elapsed)
}

/// Wheel / tap-count / BTC: knocker hits always add, even if the player also tapped.
/// The knocker clock is auto-only (no combo). Manual taps sit on top as `extra`.
/// Knocker may run past the bar (keeps striking); clamp for the counter, don't snap the arm.
private func struckSyncedProgress(
    continuous: Double,
    knockerProgress: Double,
    tapPower: Double,
    autoActive: Bool,
    fillRate: Double,
    total: Int
) -> Double {
    guard autoActive, fillRate > 0 else { return continuous }
    let power = max(tapPower, 0.01)
    let cap = Double(total)
    if knockerProgress > continuous + cap * 0.5 && knockerProgress > cap + power {
        return min(cap, continuous)
    }
    let knockerHits = floor(min(knockerProgress, cap + power) / power + 1e-9)
    let quantized = knockerHits * power
    let extra = Swift.max(0.0, continuous - knockerProgress)
    return min(cap, quantized + extra)
}

/// Never let BTC / tap-count walk backward except on a real bar wrap.
private func holdMonotonicProgress(_ held: Double, raw: Double, wrapSlop: Double = 5) -> Double {
    raw + wrapSlop < held ? raw : max(held, raw)
}

/// Strike phase from wall-clock. `originUnits / power` preserves phase across rebases.
private func knockerCyclePhase(
    elapsedSec: Double,
    tapsPerSec: Double,
    originUnits: Double,
    tapPower: Double
) -> Double {
    guard tapsPerSec > 0 else { return 0 }
    let power = max(tapPower, 0.01)
    let originFrac = originUnits / power
    let frac = originFrac - floor(originFrac)
    let raw = elapsedSec * tapsPerSec + frac
    return raw - floor(raw)
}

/// Fixed-point 1e-13 BTC quanta. 1 sat = 1e-8 BTC = 100_000 quanta.
/// Uses fractional bar progress (not floor) so 1.5-power hits advance evenly.
func btcQuanta(satsBalance: Int, barProgress: Double, unitsPerSat: Int) -> Int64 {
    let units = max(1, unitsPerSat)
    // Milli-units keep tapPower like 1.5 exact; avoid floor() which alternates +1/+2.
    let progressMilli = Int64((min(Double(units), max(0, barProgress)) * 1000.0).rounded())
    let clamped = min(Int64(units) * 1000, max(0, progressMilli))
    let denom = Int64(units) * 1000
    // Round-to-nearest quanta — truncating division fluttered the last digit.
    let fracQuanta = (clamped * 100_000 + denom / 2) / denom
    return Int64(satsBalance) * 100_000 + fracQuanta
}

func formatBtcQuanta(_ quanta: Int64) -> String {
    let whole = quanta / 10_000_000_000_000
    let frac = quanta % 10_000_000_000_000
    return String(format: "%lld.%013lld", whole, frac)
}

/// BTC for completed sats plus the in-progress fraction of the current bar (1 full bar = 1 sat).
func formatBtcAmount(satsBalance: Int, barProgress: Double, unitsPerSat: Int) -> String {
    formatBtcQuanta(btcQuanta(satsBalance: satsBalance, barProgress: barProgress, unitsPerSat: unitsPerSat))
}

/// Upward odometer ticks for place 10^power (carries spin lower wheels a full turn).
private func odometerSteps(from: Int64, to: Int64, power: Int, toDigit: Int) -> Int {
    var place: Int64 = 1
    if power > 0 {
        for _ in 0..<power { place *= 10 }
    }
    if to >= from {
        let raw = to / place - from / place
        return Int(min(max(raw, 0), 40))
    }
    let fromDigit = Int((from / place) % 10)
    return (toDigit - fromDigit + 10) % 10
}

private struct BtcGlyph: Identifiable {
    let id: String
    let digit: Int?
    let steps: Int
    let literal: String?
}

private func btcGlyphs(from: Int64, to: Int64) -> [BtcGlyph] {
    let text = formatBtcQuanta(to)
    let digitCount = text.filter(\.isNumber).count
    var power = digitCount - 1
    return text.map { ch in
        if ch.isWholeNumber, let d = ch.wholeNumberValue {
            let p = power
            power -= 1
            return BtcGlyph(
                id: "p\(p)",
                digit: d,
                steps: odometerSteps(from: from, to: to, power: p, toDigit: d),
                literal: nil
            )
        }
        return BtcGlyph(id: "lit-\(ch)", digit: nil, steps: 0, literal: String(ch))
    }
}

// MARK: - Sat earn celebration

struct SatParticle: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
}

/// BTC balance + centered sat wheel + overlapping auto knocker.
struct SatEarnStage: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @EnvironmentObject private var satEarn: SatEarnFlight

    let satsBalance: Int
    let progress: Double
    let total: Int
    let fillRate: Double
    let tapPower: Double
    let autoActive: Bool
    let autoFillUntil: String?
    var wheelFlash: Bool = false
    var wheelSize: CGFloat = 220

    @State private var anchorProgress: Double = 0
    @State private var anchorDate: Date = .now
    /// Auto-only clock for the knocker — ignores manual tap progress jumps.
    @State private var knockerAnchorProgress: Double = 0
    @State private var knockerAnchorDate: Date = .now
    @State private var heldVisual: Double = 0
    @State private var tapPulse = false

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { context in
                satEarnTimeline(at: context.date)
            }
            .onChange(of: progress) { oldValue, newValue in
                // Raise the tap floor. Knocker stays auto-only unless the bar wrapped.
                anchorProgress = newValue
                anchorDate = .now
                if newValue + 5 < oldValue {
                    knockerAnchorProgress = newValue
                    knockerAnchorDate = .now
                    heldVisual = newValue
                }
            }
            .onChange(of: fillRate) { oldRate, _ in
                let now = Date()
                let knockerNow = knockerAnchorProgress + oldRate * now.timeIntervalSince(knockerAnchorDate)
                knockerAnchorProgress = knockerNow
                knockerAnchorDate = now
                let contNow = min(Double(total), anchorProgress + oldRate * now.timeIntervalSince(anchorDate))
                anchorProgress = contNow
                anchorDate = now
            }
            .onChange(of: tapPower) { _, _ in
                // Keep current auto units so phase stays put; period changes with power.
                let now = Date()
                let knockerNow = knockerAnchorProgress + fillRate * now.timeIntervalSince(knockerAnchorDate)
                knockerAnchorProgress = knockerNow
                knockerAnchorDate = now
            }
            .onChange(of: autoActive) { _, active in
                if active {
                    let currentProgress = progress
                    let now = Date.now
                    knockerAnchorProgress = currentProgress
                    knockerAnchorDate = now
                    let visual = currentProgress
                    heldVisual = visual
                }
            }
            .onAppear {
                let currentProgress = progress
                let now = Date.now
                anchorProgress = currentProgress
                anchorDate = now
                knockerAnchorProgress = currentProgress
                knockerAnchorDate = now
                heldVisual = currentProgress
            }

            BarRateStatusView(
                autoActive: autoActive,
                fillRate: fillRate,
                tapPower: tapPower
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.horizontal, 20)
        }
    }

    private func satEarnTimeline(at now: Date) -> some View {
        let look = ThemeLook.named(settings.selectedLookId)
        let lifetimeSats = session.progress.lifetimeSats
        let minerStage = MinerStage.from(lifetimeSats: lifetimeSats)
        let continuous = displayedBarProgress(
            progress: progress,
            total: total,
            fillRate: fillRate,
            autoActive: autoActive,
            anchorProgress: anchorProgress,
            anchorDate: anchorDate,
            now: now
        )
        let tapsPerSec = tapsPerSecond(fillRate: fillRate, tapPower: tapPower)
        let knockerElapsed = autoActive && fillRate > 0
            ? now.timeIntervalSince(knockerAnchorDate)
            : 0
        let knockerProgress = knockerAnchorProgress + fillRate * knockerElapsed
        let rawDisplay = struckSyncedProgress(
            continuous: continuous,
            knockerProgress: knockerProgress,
            tapPower: tapPower,
            autoActive: autoActive,
            fillRate: fillRate,
            total: total
        )
        let display = holdMonotonicProgress(heldVisual, raw: rawDisplay)
        let fraction = total > 0 ? min(1.0, display / Double(total)) : 0.0
        let comboT = ComboTunables.from(session.tunables)
        let comboLive = ComboEngine.at(session.state.combo, now: now, tunables: comboT)
        let comboMeters = ComboEngine.displayMeters(comboLive, tunables: comboT)
        let comboTracks = ComboEngine.displayTracks(comboLive, tunables: comboT)
        let comboMult = comboT.multiplier(of: comboLive)
        let pose = knockerPose(
            elapsedSec: knockerElapsed,
            originUnits: knockerAnchorProgress,
            tapsPerSec: tapsPerSec,
            tapPower: tapPower,
            autoActive: autoActive
        )

        return VStack(spacing: 0) {
            BtcBalanceView(
                satsBalance: satsBalance,
                barProgress: display,
                total: total
            )

            Spacer().frame(height: 20)

            VStack(spacing: 8) {
                Text(formatSatsPerHour(fillRate: fillRate, unitsPerSat: total, autoActive: autoActive))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(look.accent)
                    .monospacedDigit()

                ZStack {
                    MinerStageBackdrop(stage: minerStage)
                    .offset(y: 18)
                    SatWheelView(
                        fraction: fraction,
                        flash: wheelFlash,
                        comboFractions: comboMeters,
                        comboTracks: comboTracks,
                        comboMultiplier: comboMult,
                        look: look
                    )
                    .frame(width: wheelSize, height: wheelSize)
                    .scaleEffect(tapPulse ? 0.96 : 1)
                    .animation(.spring(response: 0.18, dampingFraction: 0.55), value: tapPulse)
                    .contentShape(Circle())
                    .onTapGesture {
                        tapPulse = true
                        if settings.hapticsEnabled {
                            let leveled = comboLive.meter + 1 / Double(max(1, comboT.tapsPerLevel)) >= 1
                            UIImpactFeedbackGenerator(style: leveled ? .medium : .light)
                                .impactOccurred()
                        }
                        Task { await session.tap() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            tapPulse = false
                        }
                    }
                    .background(wheelTipReporter)
                    .overlay {
                        AutoKnockerView(pose: pose, tapPower: tapPower, active: autoActive)
                            .scaleEffect(wheelSize / 220)
                            .frame(width: 400 * wheelSize / 220, height: 300 * wheelSize / 220)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        SharedAutoTimerView(
                            autoFillUntil: autoFillUntil,
                            autoActive: autoActive
                        )
                        .frame(width: 92)
                        .offset(x: 153 * wheelSize / 220, y: 74 * wheelSize / 220)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: wheelSize + 40)

                Text(String(format: "%.1f / %d taps", display, total))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("BrandInk"))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .onChange(of: display) { _, newValue in
            heldVisual = newValue
        }
    }

    private var wheelTipReporter: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("satEarn"))
            Color.clear
                .onAppear { satEarn.wheelTip = CGPoint(x: frame.midX, y: frame.minY + 8) }
                .onChange(of: frame) { _, newFrame in
                    satEarn.wheelTip = CGPoint(x: newFrame.midX, y: newFrame.minY + 8)
                }
        }
    }
}

/// Where the auto tapper is within one strike cycle.
struct KnockerPose {
    /// 0 = cocked on the stop, 1 = head against the rim. Dips negative while winding up.
    var arm: CGFloat = 0
    /// 1 at the moment of contact, fading to 0 shortly after.
    var impact: CGFloat = 0
    /// 0…1 through the current tap, used to turn the drive gears.
    var phase: CGFloat = 0
}

/// Seconds the hammer takes to swing from the cocked stop into the rim.
private func knockerStrikeDuration(tapPower: Double) -> Double {
    max(0.07, 0.16 / max(tapPower, 0.01))
}

/// Impact VFX scale from tap power. Power 1 = baseline size; capped at power 10 (~2.25×).
private func knockerImpactScale(tapPower: Double) -> CGFloat {
    let p = min(max(tapPower, 1), 10)
    return CGFloat(1 + (p - 1) / 9 * 1.25)
}

/// How far the head rebounds off the rim, as a fraction of the full swing.
private let knockerBounce: Double = 0.42
/// Extra travel loaded past the stop just before release.
private let knockerWindUp: Double = 0.07
/// Seconds the contact flash lasts.
private let knockerImpactFade: Double = 0.16

/// Strike cycle for the auto tapper. Phase is wall-clock, not accumulated progress.
private func knockerPose(
    elapsedSec: Double,
    originUnits: Double,
    tapsPerSec: Double,
    tapPower: Double,
    autoActive: Bool
) -> KnockerPose {
    guard autoActive, tapsPerSec > 0 else { return KnockerPose() }
    let period = 1.0 / tapsPerSec
    let phase = knockerCyclePhase(
        elapsedSec: elapsedSec,
        tapsPerSec: tapsPerSec,
        originUnits: originUnits,
        tapPower: tapPower
    )

    // Segments of one tap, as fractions of the period.
    let strike = min(0.34, max(0.06, knockerStrikeDuration(tapPower: tapPower) / period))
    let recoil = min(0.20, max(0.05, 0.07 / period))
    let windUp = max(min(0.09, (1 - strike - recoil) * 0.2), 0.0001)
    let reset = max(1 - strike - recoil - windUp, 0.001)

    let fadeSec = min(knockerImpactFade, period * 0.55)
    let impact = pow(max(0, 1 - (phase * period) / fadeSec), 1.7)
    let arm: Double
    if phase < recoil {
        // Rebounds off the rim.
        arm = 1 - knockerBounce * easeOutQuad(phase / recoil)
    } else if phase < recoil + reset {
        // Drive hauls the hammer back onto its stop.
        arm = (1 - knockerBounce) * (1 - easeInOutCubic((phase - recoil) / reset))
    } else if phase < 1 - strike {
        // Held on the stop, loading a little extra travel.
        arm = -knockerWindUp * easeOutQuad((phase - recoil - reset) / windUp)
    } else {
        // Released: accelerates the whole way in, with no cushion at the end.
        let t = min(1, (phase - (1 - strike)) / strike)
        arm = -knockerWindUp + (1 + knockerWindUp) * pow(t, 2.3)
    }

    return KnockerPose(arm: CGFloat(arm), impact: CGFloat(impact), phase: CGFloat(phase))
}

private func easeOutQuad(_ t: Double) -> Double {
    let x = Swift.min(1.0, Swift.max(0.0, t))
    return 1 - (1 - x) * (1 - x)
}

private func easeInOutCubic(_ t: Double) -> Double {
    let x = Swift.min(1.0, Swift.max(0.0, t))
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

struct SatWheelView: View {
    let fraction: Double
    var flash: Bool = false
    var comboFractions: [Double] = [0, 0, 0]
    var comboTracks: [Bool] = [true, false, false]
    var comboMultiplier: Double = 1
    var look: ThemeLook = .ember

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rim = size * 0.06
            let comboRim = rim * 0.50
            let comboPitch = comboRim * 1.35
            let pad0 = rim * 1.15
            let pad1 = pad0 + comboPitch
            let pad2 = pad0 + comboPitch * 2
            let pads = [pad0, pad1, pad2]
            let fracs = [
                comboFractions.count > 0 ? comboFractions[0] : 0,
                comboFractions.count > 1 ? comboFractions[1] : 0,
                comboFractions.count > 2 ? comboFractions[2] : 0,
            ]
            let shown = [
                (comboTracks.count > 0 ? comboTracks[0] : true) || fracs[0] > 0.001,
                (comboTracks.count > 1 ? comboTracks[1] : false) || fracs[1] > 0.001,
                (comboTracks.count > 2 ? comboTracks[2] : false) || fracs[2] > 0.001,
            ]
            let innerIdx = shown[2] ? 2 : (shown[1] ? 1 : 0)
            let innerRadius = size / 2 - pads[innerIdx]
            let pegOrbit = max(size * 0.16, innerRadius - comboRim * 0.55 - 5)
            let comboLabel = ComboEngine.formatMultiplier(comboMultiplier)
            ZStack {
                Circle()
                    .stroke(Color("BrandInk").opacity(0.08), lineWidth: rim)

                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        AngularGradient(
                            colors: flash
                                ? [look.accent, Color.white, look.accent]
                                : [look.fill, look.fillHot, look.fill],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: rim, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: (flash ? look.accent : look.fill).opacity(flash ? 0.9 : 0.45),
                        radius: flash ? 16 : 8
                    )

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color("BrandInk").opacity(0.04),
                                    Color("BrandInk").opacity(0.10),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.48
                            )
                        )
                        .padding(rim * 0.85)

                    ForEach(0..<60, id: \.self) { i in
                        Capsule()
                            .fill(Color("BrandInk").opacity(0.10))
                            .frame(width: 0.8, height: 5)
                            .offset(y: -(size * 0.365))
                            .rotationEffect(.degrees(Double(i) * 6))
                    }
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(Color("BrandInk").opacity(i % 3 == 0 ? 0.35 : 0.16))
                            .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 14 : 9)
                            .offset(y: -(size * 0.38))
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                }
                .rotationEffect(.degrees(fraction * 360))
                .animation(nil, value: fraction)

                ForEach(0..<3, id: \.self) { ring in
                    ComboBandView(
                        pad: pads[ring],
                        rim: comboRim,
                        size: size,
                        frac: fracs[ring],
                        showTrack: shown[ring],
                        fill: look.comboFill(ring),
                        trackOpacity: 0.10 + Double(ring) * 0.04,
                        tickCount: ring == 0 ? 60 : (ring == 1 ? 48 : 36)
                    )
                }

                if shown[innerIdx] {
                    ForEach(0..<18, id: \.self) { i in
                        Capsule()
                            .fill(Color("BrandInk").opacity(0.30))
                            .frame(width: 1.3, height: comboRim * 0.5)
                            .offset(y: -(innerRadius - comboRim * 0.82))
                            .rotationEffect(.degrees(Double(i) * 20))
                    }
                }

                // Peg rides just inside the innermost drawn combo stroke, on top.
                ZStack {
                    Circle()
                        .fill(Color("BrandInk").opacity(0.55))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(look.accent.opacity(0.95))
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 2.4, height: 2.4)
                        .offset(x: -1.1, y: -1.1)
                }
                .offset(y: -pegOrbit)
                .rotationEffect(.degrees(fraction * 360))
                .animation(nil, value: fraction)

                // Fixed 12 o'clock pointer
                Triangle()
                    .fill(flash ? look.accent : Color("BrandInk").opacity(0.75))
                    .frame(width: 14, height: 12)
                    .offset(y: -(size * 0.5) + 4)

                // Strike plate at 3 o'clock — where the auto tapper lands.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color("BrandInk").opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color("BrandInk").opacity(0.35), lineWidth: 1)
                    )
                    .frame(width: 9, height: 26)
                    .offset(x: size * 0.5)

                // Center hub — combo multiplier when stacked
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color("BrandInk").opacity(0.12), Color("BrandInk").opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(
                        Circle().stroke(Color("BrandInk").opacity(0.12), lineWidth: 1)
                    )
                    .overlay {
                        if !comboLabel.isEmpty {
                            Text(comboLabel)
                                .font(.system(size: size * 0.07, weight: .bold, design: .rounded))
                                .foregroundStyle(look.combo)
                                .monospacedDigit()
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        } else {
                            Circle()
                                .fill(look.accent.opacity(flash ? 0.55 : 0.2))
                                .frame(width: size * 0.08, height: size * 0.08)
                        }
                    }

                if flash {
                    Circle()
                        .stroke(look.accent.opacity(0.85), lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ComboBandView: View {
    let pad: CGFloat
    let rim: CGFloat
    let size: CGFloat
    let frac: Double
    let showTrack: Bool
    let fill: Color
    let trackOpacity: Double
    let tickCount: Int

    var body: some View {
        let radius = size / 2 - pad
        let drawArc = frac > 0.001
        let fresh = drawArc && frac < 0.18
        ZStack {
            if showTrack || drawArc {
                Circle()
                    .stroke(Color("BrandInk").opacity(0.22), lineWidth: rim * 1.22)
                    .padding(pad)
                Circle()
                    .stroke(Color("BrandInk").opacity(trackOpacity), lineWidth: rim)
                    .padding(pad)
                ForEach(0..<tickCount, id: \.self) { i in
                    let major = tickCount >= 12 && i % max(1, tickCount / 12) == 0
                    Capsule()
                        .fill(Color("BrandInk").opacity(major ? 0.32 : 0.11))
                        .frame(width: major ? 1.5 : 0.7, height: major ? rim * 0.88 : rim * 0.42)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(i) * 360 / Double(tickCount)))
                }
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(Color("BrandInk").opacity(0.42))
                        .frame(width: 3.1, height: 3.1)
                        .overlay(Circle().stroke(Color("BrandInk").opacity(0.2), lineWidth: 0.5))
                        .offset(y: -(radius - rim * 0.12))
                        .rotationEffect(.degrees(Double(i) * 90))
                }
            }
            if drawArc {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, frac))))
                    .stroke(
                        fill.opacity(fresh ? 0.55 : 0.28),
                        style: StrokeStyle(lineWidth: rim * (fresh ? 1.85 : 1.55), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(pad)
                    .blur(radius: fresh ? 3.5 : 1.8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, frac))))
                    .stroke(
                        Color("BrandInk").opacity(0.38),
                        style: StrokeStyle(lineWidth: rim, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(pad)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, frac))))
                    .stroke(fill, style: StrokeStyle(lineWidth: rim * 0.70, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(pad)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Fixed tapper geometry, in points relative to the wheel centre.
private enum KnockerGeometry {
    /// Hammer pivot, up and to the right of the wheel.
    static let pivot = CGPoint(x: 150, y: -72)
    /// Head centre at contact — one `headHalfLength` back from `strikePoint`.
    static let contact = CGPoint(x: 117.1, y: -9.7)
    /// The spot on the rim the face lands on (3 o'clock, wheel radius 110).
    static let strikePoint = CGPoint(x: 112, y: 0)
    /// Degrees travelled between the cocked stop and contact.
    static let sweepDegrees: Double = 42
    static let headHalfLength: CGFloat = 11
    static let headHalfWidth: CGFloat = 15

    static let armLength = hypot(contact.x - pivot.x, contact.y - pivot.y)
    static let strikeAngle = atan2(contact.y - pivot.y, contact.x - pivot.x)

    /// Housing the pivot and drive gears are bolted to.
    static let plate = CGRect(x: 128, y: -110, width: 50, height: 56)
    static let gearWindow = CGRect(x: 133, y: -105, width: 40, height: 26)
    static let driveGear = CGPoint(x: 146, y: -92)
    static let idlerGear = CGPoint(x: 164, y: -92)
    static let driveRadius: CGFloat = 11
    static let idlerRadius: CGFloat = 7
    /// Bumper the arm rests against while cocked.
    static let stop = CGRect(x: 163, y: -53, width: 8, height: 14)

    static func angle(arm: CGFloat) -> CGFloat {
        strikeAngle - CGFloat(sweepDegrees * .pi / 180) * (1 - arm)
    }
}

/// Side-mounted auto tapper: a geared hammer that swings onto the wheel rim.
/// Driven only by Auto fill progress — manual taps do not move it.
struct AutoKnockerView: View {
    let pose: KnockerPose
    var tapPower: Double = 1
    var active: Bool = true

    var body: some View {
        Canvas { context, size in
            drawTapper(
                into: &context,
                origin: CGPoint(x: size.width / 2, y: size.height / 2),
                pose: pose,
                tapPower: tapPower,
                active: active
            )
        }
        .frame(width: 400, height: 300)
        .allowsHitTesting(false)
    }
}

private func drawTapper(
    into ctx: inout GraphicsContext,
    origin: CGPoint,
    pose: KnockerPose,
    tapPower: Double,
    active: Bool
) {
    let ink = Color("BrandInk")
    let accent = Color("BrandAccent")
    let accentHot = Color("BrandAccentHot")
    let impact = active ? pose.impact : 0
    let hitScale = active ? knockerImpactScale(tapPower: tapPower) : 1
    let fade = active ? 1.0 : 0.4

    let angle = KnockerGeometry.angle(arm: pose.arm)
    // Contact shoves the whole mount back along the strike axis.
    let kick = CGPoint(
        x: -cos(KnockerGeometry.strikeAngle) * impact * 3 * hitScale,
        y: -sin(KnockerGeometry.strikeAngle) * impact * 3 * hitScale
    )
    func mounted(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x + kick.x, y: origin.y + p.y + kick.y)
    }

    // Housing.
    let plate = KnockerGeometry.plate.offsetBy(dx: origin.x + kick.x, dy: origin.y + kick.y)
    let platePath = Path(roundedRect: plate, cornerRadius: 8, style: .continuous)
    ctx.fill(
        platePath,
        with: .linearGradient(
            Gradient(colors: [ink.opacity(0.21 * fade), ink.opacity(0.07 * fade)]),
            startPoint: CGPoint(x: plate.minX, y: plate.minY),
            endPoint: CGPoint(x: plate.maxX, y: plate.maxY)
        )
    )
    ctx.stroke(platePath, with: .color(ink.opacity(0.22 * fade)), lineWidth: 1)
    ctx.stroke(
        Path(roundedRect: plate.insetBy(dx: 5, dy: 5), cornerRadius: 5, style: .continuous),
        with: .color(ink.opacity(0.10 * fade)),
        lineWidth: 1
    )

    // Gear window, then the drive train — one turn per tap, so the machine reads
    // as the thing swinging the arm.
    let window = KnockerGeometry.gearWindow.offsetBy(dx: origin.x + kick.x, dy: origin.y + kick.y)
    ctx.fill(
        Path(roundedRect: window, cornerRadius: 13, style: .continuous),
        with: .color(.black.opacity(0.35 * fade))
    )
    let turn = pose.phase * 2 * .pi
    drawGear(
        into: &ctx,
        center: mounted(KnockerGeometry.driveGear),
        radius: KnockerGeometry.driveRadius,
        teeth: 9,
        rotation: turn,
        color: ink.opacity(0.34 * fade),
        hub: ink.opacity(0.5 * fade)
    )
    drawGear(
        into: &ctx,
        center: mounted(KnockerGeometry.idlerGear),
        radius: KnockerGeometry.idlerRadius,
        teeth: 6,
        rotation: -turn * (KnockerGeometry.driveRadius / KnockerGeometry.idlerRadius) + .pi / 6,
        color: ink.opacity(0.28 * fade),
        hub: ink.opacity(0.44 * fade)
    )

    for bolt in [
        CGPoint(x: plate.minX + 9, y: plate.maxY - 9),
        CGPoint(x: plate.maxX - 9, y: plate.maxY - 9),
    ] {
        ctx.fill(
            Path(ellipseIn: CGRect(x: bolt.x - 3, y: bolt.y - 3, width: 6, height: 6)),
            with: .color(ink.opacity(0.26 * fade))
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: bolt.x - 1.2, y: bolt.y - 1.2, width: 2.4, height: 2.4)),
            with: .color(ink.opacity(0.5 * fade))
        )
    }

    ctx.fill(
        Path(
            roundedRect: KnockerGeometry.stop.offsetBy(dx: origin.x + kick.x, dy: origin.y + kick.y),
            cornerRadius: 3,
            style: .continuous
        ),
        with: .color(ink.opacity(0.30 * fade))
    )

    // Arm and head, drawn along +x from the pivot.
    let pivot = mounted(KnockerGeometry.pivot)
    let length = KnockerGeometry.armLength
    ctx.drawLayer { arm in
        arm.translateBy(x: pivot.x, y: pivot.y)
        arm.rotate(by: .radians(Double(angle)))

        var bar = Path()
        bar.move(to: CGPoint(x: -11, y: -9))
        bar.addLine(to: CGPoint(x: length - 8, y: -5.5))
        bar.addLine(to: CGPoint(x: length - 8, y: 5.5))
        bar.addLine(to: CGPoint(x: -11, y: 9))
        bar.closeSubpath()
        for hole in [length * 0.34, length * 0.56] {
            bar.addEllipse(in: CGRect(x: hole - 3.2, y: -3.2, width: 6.4, height: 6.4))
        }
        arm.fill(
            bar,
            with: .linearGradient(
                Gradient(colors: [ink.opacity(0.58 * fade), ink.opacity(0.22 * fade)]),
                startPoint: CGPoint(x: 0, y: -9),
                endPoint: CGPoint(x: 0, y: 9)
            ),
            style: FillStyle(eoFill: true)
        )
        var edge = Path()
        edge.move(to: CGPoint(x: -8, y: -7))
        edge.addLine(to: CGPoint(x: length - 8, y: -4))
        arm.stroke(edge, with: .color(ink.opacity(0.72 * fade)), lineWidth: 1.5)

        arm.drawLayer { head in
            head.translateBy(x: length, y: 0)
            // Impact squashes the head into the rim.
            head.scaleBy(x: 1 - 0.18 * impact, y: 1 + 0.16 * impact)

            head.fill(
                Path(roundedRect: CGRect(x: -14, y: -9, width: 8, height: 18), cornerRadius: 2.5, style: .continuous),
                with: .color(ink.opacity(0.45 * fade))
            )
            let box = CGRect(
                x: -KnockerGeometry.headHalfLength,
                y: -KnockerGeometry.headHalfWidth,
                width: KnockerGeometry.headHalfLength * 2,
                height: KnockerGeometry.headHalfWidth * 2
            )
            head.fill(
                Path(roundedRect: box, cornerRadius: 5, style: .continuous),
                with: .linearGradient(
                    Gradient(colors: [accentHot.opacity(fade), accent.opacity(fade)]),
                    startPoint: CGPoint(x: 0, y: box.minY),
                    endPoint: CGPoint(x: 0, y: box.maxY)
                )
            )
            head.fill(
                Path(
                    roundedRect: CGRect(x: box.maxX - 6, y: box.minY + 3, width: 6, height: box.height - 6),
                    cornerRadius: 3,
                    style: .continuous
                ),
                with: .color(.white.opacity((0.28 + 0.55 * Double(impact)) * fade))
            )
            head.fill(
                Path(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5)),
                with: .color(.black.opacity(0.18 * fade))
            )
        }
    }

    // Pivot boss on top of the arm root.
    let boss = CGRect(x: pivot.x - 9, y: pivot.y - 9, width: 18, height: 18)
    ctx.fill(
        Path(ellipseIn: boss),
        with: .linearGradient(
            Gradient(colors: [ink.opacity(0.42 * fade), ink.opacity(0.18 * fade)]),
            startPoint: CGPoint(x: boss.minX, y: boss.minY),
            endPoint: CGPoint(x: boss.maxX, y: boss.maxY)
        )
    )
    ctx.stroke(Path(ellipseIn: boss), with: .color(ink.opacity(0.3 * fade)), lineWidth: 1)
    ctx.fill(
        Path(ellipseIn: boss.insetBy(dx: 5.5, dy: 5.5)),
        with: .color(ink.opacity(0.55 * fade))
    )

    guard impact > 0.01 else { return }

    // Contact flash on the rim — grows with Stronger (capped at power 10).
    let hit = CGPoint(
        x: origin.x + KnockerGeometry.strikePoint.x,
        y: origin.y + KnockerGeometry.strikePoint.y
    )
    let ring = (10 + 24 * (1 - impact)) * hitScale
    ctx.stroke(
        Path(ellipseIn: CGRect(x: hit.x - ring, y: hit.y - ring, width: ring * 2, height: ring * 2)),
        with: .color(accent.opacity(0.6 * Double(impact))),
        lineWidth: 1.5 + 0.5 * hitScale
    )
    var sparks = Path()
    let sparkCount = 4 + Int(((hitScale - 1) / 1.25) * 4) // 4…8
    for i in 0..<sparkCount {
        let a = CGFloat((45 + Double(i) * (360.0 / Double(sparkCount))) * .pi / 180)
        let near = (10 + 8 * (1 - impact)) * hitScale
        let far = near + (8 + 14 * (1 - impact)) * hitScale
        sparks.move(to: CGPoint(x: hit.x + cos(a) * near, y: hit.y + sin(a) * near))
        sparks.addLine(to: CGPoint(x: hit.x + cos(a) * far, y: hit.y + sin(a) * far))
    }
    ctx.stroke(
        sparks,
        with: .color(accent.opacity(0.85 * Double(impact))),
        style: StrokeStyle(lineWidth: 1.5 + 0.5 * hitScale, lineCap: .round)
    )
    let flash = (4 + 7 * impact) * hitScale
    ctx.fill(
        Path(ellipseIn: CGRect(x: hit.x - flash, y: hit.y - flash, width: flash * 2, height: flash * 2)),
        with: .color(.white.opacity(0.75 * Double(impact)))
    )
}

private func drawGear(
    into ctx: inout GraphicsContext,
    center: CGPoint,
    radius: CGFloat,
    teeth: Int,
    rotation: CGFloat,
    color: Color,
    hub: Color
) {
    var path = Path()
    let root = radius * 0.72
    for i in 0..<(teeth * 2) {
        let r = i.isMultiple(of: 2) ? radius : root
        let a = rotation + CGFloat(i) * .pi / CGFloat(teeth)
        let point = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    ctx.fill(path, with: .color(color))
    ctx.fill(
        Path(ellipseIn: CGRect(
            x: center.x - radius * 0.26,
            y: center.y - radius * 0.26,
            width: radius * 0.52,
            height: radius * 0.52
        )),
        with: .color(hub)
    )
}

enum SatParticleMotion {
    static let pop: TimeInterval = 0.32
    static let hover: TimeInterval = 0.50
    static let fly: TimeInterval = 0.85
    /// When the orb arrives at the Redeem tab (for afterglow sync).
    static var landAt: TimeInterval { pop + hover + fly - 0.06 }
}

struct FlyingSatParticleView: View {
    let particle: SatParticle
    let onFinished: () -> Void

    @State private var popT: CGFloat = 0
    @State private var flyT: CGFloat = 0
    @State private var bob: CGFloat = 0

    var body: some View {
        let hover = CGPoint(x: particle.from.x + 18, y: particle.from.y - 58)
        // Gentle S-curve toward the Redeem tab (bulge right, then in).
        let ctrl = CGPoint(
            x: hover.x + (particle.to.x - hover.x) * 0.3 + 42,
            y: min(hover.y, particle.to.y) - 36
        )
        let pos: CGPoint = {
            if flyT > 0.0001 {
                return quadBezier(hover, ctrl, particle.to, easedFly(flyT))
            }
            let p = lerp(particle.from, hover, popEase(popT))
            return CGPoint(x: p.x, y: p.y + bob)
        }()
        let scale: CGFloat = {
            if flyT > 0.0001 {
                return 1.28 - 0.38 * easedFly(flyT)
            }
            return 0.55 + 0.78 * popEase(popT)
        }()
        let fade: CGFloat = {
            if popT < 0.15 { return popT / 0.15 }
            if flyT < 0.82 { return 1 }
            return max(0, (1 - flyT) / 0.18)
        }()

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color("BrandAccent"),
                            Color("BrandAccent").opacity(0.35),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 28
                    )
                )
                .frame(width: 56, height: 56)
            Text("S")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.92))
        }
        .scaleEffect(scale)
        .opacity(fade)
        .position(pos)
        .allowsHitTesting(false)
        .onAppear {
            // 1) Pop out of the wheel tip
            withAnimation(.spring(response: 0.36, dampingFraction: 0.58)) {
                popT = 1
            }
            // 2) Hover / breathe
            DispatchQueue.main.asyncAfter(deadline: .now() + SatParticleMotion.pop) {
                withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                    bob = -7
                }
            }
            // 3) Ease along the curve to the Redeem tab
            DispatchQueue.main.asyncAfter(deadline: .now() + SatParticleMotion.pop + SatParticleMotion.hover) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { bob = 0 }
                withAnimation(.timingCurve(0.4, 0.0, 0.15, 1.0, duration: SatParticleMotion.fly)) {
                    flyT = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + SatParticleMotion.fly + 0.08) {
                    onFinished()
                }
            }
        }
    }

    /// Ease-out cubic for the pop lerp (spring still drives popT).
    private func popEase(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return 1 - pow(1 - x, 3)
    }

    /// Extra ease on fly progress so mid-path coasts then settles.
    private func easedFly(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        // Smoothstep-ish ease-in-out
        return x * x * (3 - 2 * x)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func quadBezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
    }
}

struct BtcBalanceView: View {
    let satsBalance: Int
    let barProgress: Double
    let total: Int

    var body: some View {
        VStack(spacing: 8) {
            RollingDigitsLabel(
                quanta: btcQuanta(satsBalance: satsBalance, barProgress: barProgress, unitsPerSat: total),
                fontSize: 42
            )
            .shadow(color: Color("BrandAccent").opacity(0.28), radius: 14, y: 4)
            Text("BTC")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(Color("BrandAccent"))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

/// Odometer-style label: each digit always rolls upward; punctuation stays put.
struct RollingDigitsLabel: View {
    let quanta: Int64
    var fontSize: CGFloat = 42

    @State private var fromQuanta: Int64?

    private var digitFont: Font {
        .system(size: fontSize, weight: .heavy, design: .rounded)
    }

    private var glyphs: [BtcGlyph] {
        btcGlyphs(from: fromQuanta ?? quanta, to: quanta)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(glyphs) { glyph in
                if let digit = glyph.digit {
                    RollingDigitSlot(
                        digit: digit,
                        steps: glyph.steps,
                        rollId: quanta,
                        font: digitFont
                    )
                } else if let lit = glyph.literal {
                    Text(lit)
                        .font(digitFont)
                        .foregroundStyle(Color("BrandInk"))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .minimumScaleFactor(0.4)
        .scaledToFit()
        .lineLimit(1)
        .onAppear {
            if fromQuanta == nil { fromQuanta = quanta }
        }
        .onChange(of: quanta) { _, newValue in
            if (fromQuanta ?? 0) <= 0 && newValue >= 100_000 {
                fromQuanta = newValue
                return
            }
            Task { @MainActor in
                fromQuanta = newValue
            }
        }
    }
}

private struct RollingDigitSlot: View {
    let digit: Int
    let steps: Int
    let rollId: Int64
    let font: Font

    /// No slide — just tick the glyph through intermediates (incl. full-turn carries).
    @State private var displayed: Int = 0
    @State private var primed = false
    @State private var rollTask: Task<Void, Never>?

    var body: some View {
        Text("\(displayed)")
            .font(font)
            .foregroundStyle(Color("BrandInk"))
            .monospacedDigit()
            .onAppear {
                guard !primed else { return }
                displayed = max(0, min(9, digit))
                primed = true
            }
            .onChange(of: rollId) { _, _ in
                let target = max(0, min(9, digit))
                let n = max(0, steps)
                rollTask?.cancel()
                rollTask = Task { @MainActor in
                    defer {
                        if Task.isCancelled { displayed = target }
                    }
                    if n == 0 {
                        displayed = target
                        return
                    }
                    let tickNs: UInt64 = n >= 20 ? 20_000_000 : n >= 10 ? 30_000_000 : 45_000_000
                    for _ in 0..<n {
                        if Task.isCancelled { return }
                        displayed = (displayed + 1) % 10
                        try? await Task.sleep(nanoseconds: tickNs)
                    }
                    if !Task.isCancelled {
                        displayed = target
                    }
                }
            }
            .onDisappear {
                rollTask?.cancel()
            }
    }
}

/// Rate line under the wheel stage: taps/s · power · fill/s — colored by Speed / Power.
struct BarRateStatusView: View {
    let autoActive: Bool
    let fillRate: Double
    let tapPower: Double

    var body: some View {
        let power = tapPower > 0 ? tapPower : 1
        Group {
            if !autoActive || fillRate <= 0 {
                HStack(spacing: 0) {
                    Text("Idle").foregroundStyle(Color("BrandMuted"))
                    if power > 1.000000001 {
                        Text(" · ").foregroundStyle(Color("BrandMuted"))
                        Text(String(format: "%.2f power", power))
                            .foregroundStyle(Color("BrandPower"))
                    }
                }
            } else {
                let tapsPerSec = fillRate / power
                HStack(spacing: 0) {
                    Text(String(format: "%.2f taps/s", tapsPerSec))
                        .foregroundStyle(Color("BrandAccent"))
                    Text(" × ").foregroundStyle(Color("BrandMuted"))
                    Text(String(format: "%.2f power", power))
                        .foregroundStyle(Color("BrandPower"))
                    Text(" = ").foregroundStyle(Color("BrandMuted"))
                    Text(String(format: "%.2f/s", fillRate))
                        .foregroundStyle(Color("BrandFill"))
                }
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

func formatLongerAction(_ t: Tunables?) -> String {
    let seconds = t?.durationBoostSeconds ?? 1800
    let minutes = seconds / 60
    if minutes % 60 == 0 && minutes >= 60 {
        return "Add \(minutes / 60)h"
    }
    return "Add \(minutes) min"
}

func formatFasterAction(_ t: Tunables?) -> String {
    String(format: "+%.2f taps/s", t?.speedBoostAmount ?? 0.5)
}

func formatStrongerAction(_ t: Tunables?) -> String {
    String(format: "+%.2f power/tap", t?.tapStrengthBoostAmount ?? 0.25)
}

func formatSkipTimeAction(_ t: Tunables?) -> String {
    let seconds = t?.skipTimeSeconds ?? 60
    let minutes = seconds / 60
    if minutes >= 1 && seconds % 60 == 0 {
        return "Skip \(minutes) min"
    }
    return "Skip \(seconds)s"
}

func formatSkipRemaining(_ skipAdsRemaining: Int) -> String {
    if skipAdsRemaining < 0 { return "Unlimited" }
    return "\(skipAdsRemaining) left"
}

func formatSkipButtonStatus(skipAdsRemaining: Int, cooldownLeft: Int, regenLeft: Int = 0) -> String {
    if cooldownLeft > 0 { return "Next in \(cooldownLeft)s" }
    if skipAdsRemaining == 0 && regenLeft > 0 {
        return "Next in \(formatCountdown(regenLeft))"
    }
    return formatSkipRemaining(skipAdsRemaining)
}

/// Raw auto tap rate (excludes Stronger). fillRate from server is total units/s.
func tapsPerSecond(fillRate: Double, tapPower: Double) -> Double {
    let power = tapPower > 0 ? tapPower : 1
    return fillRate / power
}

/// Sats earned per hour from the current auto fill rate (0 when idle).
func satsPerHour(fillRate: Double, unitsPerSat: Int, autoActive: Bool) -> Double {
    guard autoActive, fillRate > 0, unitsPerSat > 0 else { return 0 }
    return (fillRate / Double(unitsPerSat)) * 3600
}

func formatSatsPerHour(fillRate: Double, unitsPerSat: Int, autoActive: Bool) -> String {
    let rate = satsPerHour(fillRate: fillRate, unitsPerSat: unitsPerSat, autoActive: autoActive)
    if rate <= 0 { return "0 sats/h" }
    if rate >= 100 {
        return String(format: "%.0f sats/h", rate)
    }
    return String(format: "%.1f sats/h", rate)
}

struct SkipTimeButton: View {
    let actionLabel: String
    let remainingLabel: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        let theme = Color("BrandTime")
        Button(action: action) {
            HStack {
                Text(actionLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(disabled ? Color("BrandMuted").opacity(0.55) : Color("BrandInk"))
                Spacer()
                Text(remainingLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(disabled ? Color("BrandMuted").opacity(0.45) : theme)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: disabled
                        ? [Color("BrandInk").opacity(0.03), Color("BrandInk").opacity(0.05)]
                        : [Color("BrandInk").opacity(0.06), theme.opacity(0.20)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        disabled ? Color("BrandInk").opacity(0.08) : theme.opacity(0.85),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct BoostButton: View {
    let title: String
    let actionLabel: String
    let theme: Color
    var running: Bool = false
    var applyCount: Int = 0
    var showCount: Bool = true
    let disabled: Bool
    let action: () -> Void

    private enum Visual {
        case ready, runningReady, runningLocked, locked
    }

    var body: some View {
        let visual: Visual = {
            if running && !disabled { return .runningReady }
            if running && disabled { return .runningLocked }
            if !disabled { return .ready }
            return .locked
        }()

        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor(visual))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                Text(actionLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(detailColor(visual))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if showCount {
                    Text("(\(applyCount))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(countColor(visual))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fillGradient(visual))
                    .shadow(color: theme.opacity(running ? 0.40 : 0.22), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor(visual), lineWidth: borderWidth(visual))
            )
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }

    private func titleColor(_ visual: Visual) -> Color {
        switch visual {
        case .ready, .runningReady: return Color("BrandInk")
        case .runningLocked: return Color("BrandInk").opacity(0.55)
        case .locked: return Color("BrandMuted").opacity(0.55)
        }
    }

    private func detailColor(_ visual: Visual) -> Color {
        switch visual {
        case .ready: return theme
        case .runningReady: return Color(red: 0.043, green: 0.047, blue: 0.078)
        case .runningLocked: return theme.opacity(0.55)
        case .locked: return Color("BrandMuted").opacity(0.45)
        }
    }

    private func countColor(_ visual: Visual) -> Color {
        switch visual {
        case .ready: return Color("BrandInk").opacity(0.45)
        case .runningReady: return Color(red: 0.043, green: 0.047, blue: 0.078).opacity(0.75)
        case .runningLocked: return theme.opacity(0.40)
        case .locked: return Color("BrandMuted").opacity(0.35)
        }
    }

    private func borderColor(_ visual: Visual) -> Color {
        switch visual {
        case .ready: return theme.opacity(0.85)
        case .runningReady: return theme
        case .runningLocked: return theme.opacity(0.35)
        case .locked: return Color("BrandInk").opacity(0.08)
        }
    }

    private func borderWidth(_ visual: Visual) -> CGFloat {
        switch visual {
        case .ready: return 1.5
        case .runningReady: return 2
        case .runningLocked: return 1.5
        case .locked: return 1
        }
    }

    private func fillGradient(_ visual: Visual) -> LinearGradient {
        switch visual {
        case .ready:
            return LinearGradient(
                colors: [Color("BrandInk").opacity(0.08), theme.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .runningReady:
            return LinearGradient(
                colors: [theme.opacity(0.95), theme.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .runningLocked:
            return LinearGradient(
                colors: [Color("BrandInk").opacity(0.05), theme.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .locked:
            return LinearGradient(
                colors: [Color("BrandInk").opacity(0.03), Color("BrandInk").opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

func formatCountdown(_ totalSeconds: Int) -> String {
    var rem = max(0, totalSeconds)
    let d = rem / 86_400
    rem %= 86_400
    let h = rem / 3_600
    rem %= 3_600
    let m = rem / 60
    let s = rem % 60
    var parts: [String] = []
    if d > 0 { parts.append("\(d)d") }
    if h > 0 || d > 0 { parts.append("\(h)h") }
    if m > 0 || h > 0 || d > 0 { parts.append("\(m)m") }
    parts.append("\(s)s")
    return parts.joined(separator: " ")
}

func remainingSeconds(untilIso: String?, now: Date = Date()) -> Int {
    guard let untilIso, let until = parseIso8601(untilIso) else { return 0 }
    return max(0, Int(until.timeIntervalSince(now)))
}

struct AtmosphereBackground: View {
    var look: ThemeLook = .ember

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.071, green: 0.075, blue: 0.122),
                Color(red: 0.055, green: 0.059, blue: 0.102),
                Color(red: 0.039, green: 0.043, blue: 0.071),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Circle()
                .fill(look.glow.opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: -120, y: -240)
            Circle()
                .fill(look.fill.opacity(0.14))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 150, y: 280)
        }
        .ignoresSafeArea()
    }
}
