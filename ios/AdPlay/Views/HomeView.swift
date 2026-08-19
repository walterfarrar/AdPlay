import AudioToolbox
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettings = false
    @State private var showAchievements = false
    @State private var satAnchors: [SatEarnAnchor: CGPoint] = [:]
    @State private var satParticles: [SatParticle] = []
    @State private var trophyGlow = false
    @State private var barFlash = false
    @State private var lastCelebrateAt: Date = .distantPast
    @State private var homeSize: CGSize = .zero

    var body: some View {
        let state = session.state

        ZStack {
            AtmosphereBackground()

            GeometryReader { geo in
                let wide = sizeClass == .regular && geo.size.width > 700
                let wheel = min(260, max(180, (wide ? geo.size.width * 0.28 : geo.size.width * 0.55)))
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 28) {
                                playStage(state: state, wheel: wheel)
                                boostsColumn(state: state)
                            }
                        } else {
                            VStack(spacing: 0) {
                                playStage(state: state, wheel: wheel)
                                boostsColumn(state: state)
                            }
                        }
                    }
                    .frame(maxWidth: wide ? .infinity : 560)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
            }

            ForEach(satParticles) { particle in
                FlyingSatParticleView(particle: particle) {
                    satParticles.removeAll { $0.id == particle.id }
                }
            }
        }
        .coordinateSpace(name: "satEarn")
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { homeSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in homeSize = newSize }
            }
        )
        .onPreferenceChange(SatEarnAnchorKey.self) { satAnchors = $0 }
        .onChange(of: session.state.satsBalance) { oldValue, newValue in
            let gained = newValue - oldValue
            guard gained > 0 else { return }
            celebrateSatEarn(gained: gained)
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

    private func playStage(state: GameState, wheel: CGFloat) -> some View {
        VStack(spacing: 0) {
            headerBar
            Text(
                "Early access — Lightning payouts are real. Earn rates stay modest while we roll out; " +
                    "they can improve as more players join and ad revenue grows."
            )
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(Color("BrandMuted"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)

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
            .padding(.top, 20)

            Text(
                state.tapsRemaining > 0
                    ? "Tap the wheel · \(state.tapsRemaining) taps left today"
                    : "0 taps left today"
            )
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Color("BrandMuted"))
            .padding(.top, 14)
        }
    }

    private var headerBar: some View {
        HStack {
            Text("AdPlay")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color("BrandInk"))
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
                    .background(
                        Circle().fill(Color("BrandAccent").opacity(trophyGlow ? 0.38 : 0.14))
                    )
                    .overlay(
                        Circle().stroke(
                            Color("BrandAccent").opacity(trophyGlow ? 1.0 : 0.55),
                            lineWidth: trophyGlow ? 2 : 1
                        )
                    )
                    .shadow(
                        color: Color("BrandAccent").opacity(trophyGlow ? 0.85 : 0),
                        radius: trophyGlow ? 16 : 0,
                        y: 0
                    )
                    .scaleEffect(trophyGlow ? 1.08 : 1.0)
            }
            .accessibilityLabel("Achievements")
            .background(satAnchorReporter(.trophy))
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
        let canSkip = !session.isLoading
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
            .padding(.top, 28)
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
            .frame(height: 88)
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
        !session.isLoading
            && session.state.adsRemainingToday > 0
            && session.state.adCooldownSecondsLeft == 0
    }

    /// Free starter ad while idle — does not spend from the boost bank.
    private var canActivate: Bool {
        !session.isLoading
            && !session.state.autoFillActive
            && session.state.adCooldownSecondsLeft == 0
    }

    /// Faster / Stronger unlock once Auto Tapper is running.
    private var canWatchSecondary: Bool {
        canWatch && session.state.autoFillActive
    }

    private func celebrateSatEarn(gained: Int) {
        let bursts = min(max(gained, 1), 4)
        for i in 0..<bursts {
            let delay = Double(i) * 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                fireSatCelebrationBeat()
            }
        }
    }

    private func fireSatCelebrationBeat() {
        let now = Date()
        guard now.timeIntervalSince(lastCelebrateAt) >= 0.12 || satParticles.isEmpty else { return }
        lastCelebrateAt = now

        withAnimation(.easeOut(duration: 0.12)) {
            barFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.45)) {
                barFlash = false
            }
        }

        let from = satAnchors[.wheelTip]
            ?? CGPoint(x: max(24, homeSize.width * 0.38), y: homeSize.height * 0.38)
        let to = satAnchors[.trophy]
            ?? CGPoint(x: max(48, homeSize.width - 88), y: 36)
        if satParticles.count < 4, homeSize.width > 0 {
            satParticles.append(SatParticle(from: from, to: to))
        }

        // Afterglow when the orb lands on the trophy (pop + hover + fly).
        DispatchQueue.main.asyncAfter(deadline: .now() + SatParticleMotion.landAt) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                trophyGlow = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.5)) {
                    trophyGlow = false
                }
            }
        }

        if settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if settings.soundEnabled {
            AudioServicesPlaySystemSound(1057)
        }
    }

    private func satAnchorReporter(_ id: SatEarnAnchor) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SatEarnAnchorKey.self,
                value: [id: CGPoint(
                    x: geo.frame(in: .named("satEarn")).midX,
                    y: geo.frame(in: .named("satEarn")).midY
                )]
            )
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
        Text(footerText)
            .font(.caption)
            .foregroundStyle(Color("BrandMuted"))
            .padding(.bottom, 16)
    }

    private var footerText: String {
        if adsRemaining <= 0 {
            if regenLeft > 0 {
                return "Next Boost Ad in \(formatCountdown(regenLeft))"
            }
            if adRegenSeconds <= 0 {
                return "Ads refill when Auto ends"
            }
            return "No ads available"
        }
        if cooldownLeft > 0 {
            return "Next Boost Ad in \(cooldownLeft)s · \(adsRemaining)/\(adsMax) ads"
        }
        if adsRemaining < adsMax, regenLeft > 0 {
            return "\(adsRemaining)/\(adsMax) ads · +1 in \(formatCountdown(regenLeft))"
        }
        return "\(adsRemaining)/\(adsMax) ads"
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

/// Wheel / tap-count / BTC progress: advances only on whole knocker (or manual) hits.
/// Both clocks are quantized to the tapPower lattice so dual-timer drift can't jitter
/// the last BTC digit between frames.
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
    // Bar wrap / reset left the knocker clock on the previous bar.
    if knockerProgress > continuous + max(power * 2, 5) {
        return continuous
    }
    // Epsilon keeps float edges from flickering across a hit boundary.
    let knockerHits = floor(knockerProgress / power + 1e-9)
    let continuousHits = floor(continuous / power + 1e-9)
    // Manual taps bump `continuous` by ~power; take the lead without raw float residue.
    let hits = max(knockerHits, continuousHits)
    return min(Double(total), hits * power)
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

private enum SatEarnAnchor: Hashable {
    case trophy
    case wheelTip
}

private struct SatEarnAnchorKey: PreferenceKey {
    static var defaultValue: [SatEarnAnchor: CGPoint] = [:]
    static func reduce(value: inout [SatEarnAnchor: CGPoint], nextValue: () -> [SatEarnAnchor: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SatParticle: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
}

/// BTC balance + centered sat wheel + overlapping auto knocker.
struct SatEarnStage: View {
    @EnvironmentObject private var session: SessionStore

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

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { context in
                let continuous = displayedBarProgress(
                    progress: progress,
                    total: total,
                    fillRate: fillRate,
                    autoActive: autoActive,
                    anchorProgress: anchorProgress,
                    anchorDate: anchorDate,
                    now: context.date
                )
                let tapsPerSec = tapsPerSecond(fillRate: fillRate, tapPower: tapPower)
                let knockerProgress = autoActive && fillRate > 0
                    ? knockerAnchorProgress + fillRate * context.date.timeIntervalSince(knockerAnchorDate)
                    : knockerAnchorProgress
                let display = struckSyncedProgress(
                    continuous: continuous,
                    knockerProgress: knockerProgress,
                    tapPower: tapPower,
                    autoActive: autoActive,
                    fillRate: fillRate,
                    total: total
                )
                let fraction = total > 0 ? min(1, display / Double(total)) : 0
                let pose = knockerPose(
                    displayProgress: knockerProgress,
                    tapsPerSec: tapsPerSec,
                    tapPower: tapPower,
                    autoActive: autoActive
                )

                VStack(spacing: 0) {
                    BtcBalanceView(
                        satsBalance: satsBalance,
                        barProgress: display,
                        total: total
                    )

                    Spacer(minLength: 20)

                    VStack(spacing: 8) {
                        Text(formatSatsPerHour(fillRate: fillRate, unitsPerSat: total, autoActive: autoActive))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("BrandAccent"))
                            .monospacedDigit()

                        // Wheel and tapper are one machine, nudged left to make room for the arm.
                        ZStack {
                            SatWheelView(fraction: fraction, flash: wheelFlash)
                                .frame(width: wheelSize, height: wheelSize)
                                .contentShape(Circle())
                                .onTapGesture {
                                    Task { await session.tap() }
                                }
                                .background(wheelTipReporter)

                            AutoKnockerView(pose: pose, tapPower: tapPower, active: autoActive)
                                .scaleEffect(wheelSize / 220)
                                .frame(width: 400 * wheelSize / 220, height: 300 * wheelSize / 220)

                            SharedAutoTimerView(
                                autoFillUntil: autoFillUntil,
                                autoActive: autoActive
                            )
                            .frame(width: 92)
                            .offset(x: 153 * wheelSize / 220, y: 74 * wheelSize / 220)
                        }
                        .offset(x: -22 * wheelSize / 220)
                        .frame(maxWidth: .infinity)
                        .frame(height: wheelSize + 40)

                        Text("\(Int(display.rounded(.down))) / \(total) taps")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("BrandInk"))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                }
            }
            .onChange(of: progress) { _, newValue in
                // Wheel / BTC follow taps; knocker keeps its auto-only clock
                // unless the bar wrapped (progress rewound).
                anchorProgress = newValue
                anchorDate = .now
                if newValue + 5 < knockerAnchorProgress {
                    knockerAnchorProgress = newValue
                    knockerAnchorDate = .now
                }
            }
            .onChange(of: fillRate) { _, _ in
                anchorProgress = progress
                anchorDate = .now
                knockerAnchorProgress = progress
                knockerAnchorDate = .now
            }
            .onChange(of: tapPower) { _, _ in
                anchorProgress = progress
                anchorDate = .now
                knockerAnchorProgress = progress
                knockerAnchorDate = .now
            }
            .onChange(of: autoActive) { _, active in
                if active {
                    knockerAnchorProgress = progress
                    knockerAnchorDate = .now
                }
            }
            .onAppear {
                anchorProgress = progress
                anchorDate = .now
                knockerAnchorProgress = progress
                knockerAnchorDate = .now
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

    private var wheelTipReporter: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("satEarn"))
            Color.clear.preference(
                key: SatEarnAnchorKey.self,
                value: [.wheelTip: CGPoint(x: frame.midX, y: frame.minY + 8)]
            )
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

/// Strike cycle for the auto tapper.
/// One strike per tap. Progress is in units (`taps/s × power`), so divide by
/// `tapPower` — Stronger hits harder (snappier swing), Faster raises frequency.
private func knockerPose(
    displayProgress: Double,
    tapsPerSec: Double,
    tapPower: Double,
    autoActive: Bool
) -> KnockerPose {
    guard autoActive, tapsPerSec > 0 else { return KnockerPose() }
    let power = max(tapPower, 0.01)
    let tapIndex = displayProgress / power
    let period = 1.0 / tapsPerSec
    let phase = tapIndex - floor(tapIndex) // 0 = just struck

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
    let x = min(1, max(0, t))
    return 1 - (1 - x) * (1 - x)
}

private func easeInOutCubic(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

struct SatWheelView: View {
    let fraction: Double
    var flash: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rim = size * 0.06
            ZStack {
                // Track ring
                Circle()
                    .stroke(Color("BrandInk").opacity(0.08), lineWidth: rim)

                // Progress arc from 12 o'clock clockwise
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        AngularGradient(
                            colors: flash
                                ? [Color("BrandAccent"), Color.white, Color("BrandAccent")]
                                : [Color("BrandFill"), Color("BrandFillHot"), Color("BrandFill")],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: rim, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: (flash ? Color("BrandAccent") : Color("BrandFill")).opacity(flash ? 0.9 : 0.45),
                        radius: flash ? 16 : 8
                    )

                // Rotating face + ticks
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

                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(Color("BrandInk").opacity(i % 3 == 0 ? 0.35 : 0.16))
                            .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 14 : 9)
                            .offset(y: -(size * 0.38))
                            .rotationEffect(.degrees(Double(i) * 30))
                    }

                    // Hub peg marker at the "start" of the wheel face (aligns with tip at 0)
                    Circle()
                        .fill(Color("BrandAccent").opacity(0.85))
                        .frame(width: 8, height: 8)
                        .offset(y: -(size * 0.30))
                }
                .rotationEffect(.degrees(fraction * 360))
                .animation(nil, value: fraction)

                // Fixed 12 o'clock pointer
                Triangle()
                    .fill(flash ? Color("BrandAccent") : Color("BrandInk").opacity(0.75))
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

                // Center hub
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
                    .overlay(
                        Circle()
                            .fill(Color("BrandAccent").opacity(flash ? 0.55 : 0.2))
                            .frame(width: size * 0.08, height: size * 0.08)
                    )

                if flash {
                    Circle()
                        .stroke(Color("BrandAccent").opacity(0.85), lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private enum SatParticleMotion {
    static let pop: TimeInterval = 0.32
    static let hover: TimeInterval = 0.50
    static let fly: TimeInterval = 0.85
    /// When the orb arrives at the trophy (for afterglow sync).
    static var landAt: TimeInterval { pop + hover + fly - 0.06 }
}

private struct FlyingSatParticleView: View {
    let particle: SatParticle
    let onFinished: () -> Void

    @State private var popT: CGFloat = 0
    @State private var flyT: CGFloat = 0
    @State private var bob: CGFloat = 0

    var body: some View {
        let hover = CGPoint(x: particle.from.x + 18, y: particle.from.y - 58)
        // Gentle S-curve toward the trophy (bulge right, then in).
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
            // 3) Ease along the curve to the trophy
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
        .padding(.horizontal, 16)
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
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.45)
        .lineLimit(1)
        .onAppear {
            if fromQuanta == nil { fromQuanta = quanta }
        }
        .onChange(of: quanta) { _, newValue in
            // Body already rendered glyphs against the previous baseline; advance after.
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

func parseIso8601(_ value: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: value) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}

struct AtmosphereBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.071, green: 0.075, blue: 0.122), // #12131F
                Color(red: 0.055, green: 0.059, blue: 0.102), // #0E0F1A
                Color(red: 0.039, green: 0.043, blue: 0.071), // #0A0B12
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Circle()
                .fill(Color("BrandAccent").opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: -120, y: -240)
            Circle()
                .fill(Color(red: 0.42, green: 0.36, blue: 0.95).opacity(0.16)) // indigo glow
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 150, y: 280)
        }
        .ignoresSafeArea()
    }
}
