import AudioToolbox
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showRedeem = false
    @State private var satAnchors: [SatEarnAnchor: CGPoint] = [:]
    @State private var satParticles: [SatParticle] = []
    @State private var redeemGlow = false
    @State private var barFlash = false
    @State private var lastCelebrateAt: Date = .distantPast
    @State private var homeSize: CGSize = .zero

    var body: some View {
        let state = session.state

        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
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
                    if session.tunables?.debugReset != false {
                        Button("Reset") {
                            Task { await session.debugReset() }
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("BrandMuted"))
                    }
                    Button {
                        showRedeem = true
                    } label: {
                        Text("Redeem")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("BrandAccent"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(Color("BrandAccent").opacity(redeemGlow ? 0.38 : 0.14))
                            )
                            .overlay(
                                Capsule().stroke(
                                    Color("BrandAccent").opacity(redeemGlow ? 1.0 : 0.55),
                                    lineWidth: redeemGlow ? 2 : 1
                                )
                            )
                            .shadow(
                                color: Color("BrandAccent").opacity(redeemGlow ? 0.85 : 0),
                                radius: redeemGlow ? 16 : 0,
                                y: 0
                            )
                            .scaleEffect(redeemGlow ? 1.08 : 1.0)
                    }
                    .background(satAnchorReporter(.redeem))
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Text(
                    "Early access — Lightning payouts are real. Earn rates stay modest while we roll out; " +
                        "they can improve as more players join and ad revenue grows."
                )
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color("BrandMuted"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 10)

                Spacer(minLength: 24)

                SatEarnStage(
                    satsBalance: state.satsBalance,
                    progress: state.progress,
                    total: state.unitsPerSat,
                    fillRate: state.fillRate,
                    tapPower: state.effectiveTapPower,
                    autoActive: state.autoFillActive,
                    barFlash: barFlash
                )

                Text(
                    state.tapsRemaining > 0
                        ? "Tap the bar · \(state.tapsRemaining) taps left today"
                        : "0 taps left today"
                )
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color("BrandMuted"))
                    .padding(.top, 14)

                Spacer(minLength: 36)

                Text("Watch an Ad for a Boost")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("BrandMuted"))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

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
                        disabled: !canWatch
                    ) {
                        Task { await session.watch(boost: .speed) }
                    }
                    BoostButton(
                        title: "Stronger",
                        actionLabel: formatStrongerAction(session.tunables),
                        theme: Color("BrandPower"),
                        running: state.tapStrengthActive ?? false,
                        applyCount: state.strongerBoostCount,
                        disabled: !canWatch
                    ) {
                        Task { await session.watch(boost: .tapStrength) }
                    }
                }
                .frame(height: 88)
                .padding(.horizontal, 24)

                SharedAutoTimerView(
                    autoFillUntil: state.autoFillUntil,
                    autoActive: state.autoFillActive
                )
                .padding(.top, 10)
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
                    adsMax: session.tunables?.adsPerCycle ?? 10
                )

                // Reserved height so layout never jumps when Skip appears.
                let skipRemaining = state.effectiveSkipAdsRemaining
                let skipRegenLeft = state.skipAdRegenSecondsLeft ?? 0
                let skipVisible = state.adsRemainingToday <= 0
                    && state.autoFillActive
                    && (skipRemaining < 0 || skipRemaining > 0 || skipRegenLeft > 0)
                let canSkip = !session.isLoading
                    && skipVisible
                    && state.adCooldownSecondsLeft == 0
                    && (skipRemaining < 0 || skipRemaining > 0)

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
        .sheet(isPresented: $showRedeem) {
            RedeemView()
                .environmentObject(session)
        }
    }

    private var canWatch: Bool {
        !session.isLoading
            && session.state.adsRemainingToday > 0
            && session.state.adCooldownSecondsLeft == 0
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

        let from = satAnchors[.barEnd]
            ?? CGPoint(x: max(24, homeSize.width - 36), y: homeSize.height * 0.42)
        let to = satAnchors[.redeem]
            ?? CGPoint(x: max(48, homeSize.width - 56), y: 36)
        if satParticles.count < 4, homeSize.width > 0 {
            satParticles.append(SatParticle(from: from, to: to))
        }

        // Afterglow when the orb lands on Redeem (pop + hover + fly).
        DispatchQueue.main.asyncAfter(deadline: .now() + SatParticleMotion.landAt) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                redeemGlow = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.5)) {
                    redeemGlow = false
                }
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(1057)
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(left > 0 ? Color("BrandTime") : .clear)
                .frame(maxWidth: .infinity)
                .monospacedDigit()
        }
    }
}

struct AdsFooterView: View {
    let adsRemaining: Int
    let cooldownLeft: Int
    let regenLeft: Int
    let adsMax: Int

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

/// Live progress toward the next sat, matching the bar’s local auto-fill interpolation.
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

/// BTC for completed sats plus the in-progress fraction of the current bar (1 full bar = 1 sat).
func formatBtcAmount(satsBalance: Int, barProgress: Double, unitsPerSat: Int) -> String {
    let fraction = unitsPerSat > 0 ? min(1, max(0, barProgress / Double(unitsPerSat))) : 0
    let btc = (Double(satsBalance) + fraction) * 1e-8
    // 11 dp: 1 sat = 1e-8 BTC; with ~1000 units/sat each unit is visible as 1e-11.
    return String(format: "%.11f", btc)
}

// MARK: - Sat earn celebration

private enum SatEarnAnchor: Hashable {
    case redeem
    case barEnd
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

/// BTC balance + progress bar; reports bar-end anchor for the sat-earn particle.
struct SatEarnStage: View {
    let satsBalance: Int
    let progress: Double
    let total: Int
    let fillRate: Double
    let tapPower: Double
    let autoActive: Bool
    var barFlash: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            BtcBalanceView(
                satsBalance: satsBalance,
                progress: progress,
                total: total,
                fillRate: fillRate,
                autoActive: autoActive
            )

            Spacer(minLength: 28)

            ProgressBarView(
                progress: progress,
                total: total,
                fillRate: fillRate,
                tapPower: tapPower,
                autoActive: autoActive,
                flash: barFlash
            )
            .padding(.horizontal, 24)
            .background(barEndReporter)
        }
    }

    private var barEndReporter: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("satEarn"))
            Color.clear.preference(
                key: SatEarnAnchorKey.self,
                value: [.barEnd: CGPoint(x: frame.maxX - 12, y: frame.maxY - 15)]
            )
        }
    }
}

private enum SatParticleMotion {
    static let pop: TimeInterval = 0.32
    static let hover: TimeInterval = 0.50
    static let fly: TimeInterval = 0.85
    /// When the orb arrives at Redeem (for afterglow sync).
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
        // Gentle S-curve toward Redeem (bulge right, then in).
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
            // 1) Pop out of the bar
            withAnimation(.spring(response: 0.36, dampingFraction: 0.58)) {
                popT = 1
            }
            // 2) Hover / breathe
            DispatchQueue.main.asyncAfter(deadline: .now() + SatParticleMotion.pop) {
                withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                    bob = -7
                }
            }
            // 3) Ease along the curve to Redeem
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
    let progress: Double
    let total: Int
    let fillRate: Double
    let autoActive: Bool

    @State private var anchorProgress: Double = 0
    @State private var anchorDate: Date = .now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let display = displayedBarProgress(
                progress: progress,
                total: total,
                fillRate: fillRate,
                autoActive: autoActive,
                anchorProgress: anchorProgress,
                anchorDate: anchorDate,
                now: context.date
            )
            VStack(spacing: 8) {
                Text(formatBtcAmount(satsBalance: satsBalance, barProgress: display, unitsPerSat: total))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color("BrandInk"))
                    .monospacedDigit()
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .shadow(color: Color("BrandAccent").opacity(0.35), radius: 22, y: 6)
                Text("BTC")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color("BrandAccent"))
            }
            .padding(.horizontal, 16)
        }
        .onChange(of: progress) { _, newValue in
            anchorProgress = newValue
            anchorDate = .now
        }
        .onChange(of: fillRate) { _, _ in
            anchorProgress = progress
            anchorDate = .now
        }
        .onAppear {
            anchorProgress = progress
            anchorDate = .now
        }
    }
}

struct ProgressBarView: View {
    let progress: Double
    let total: Int
    let fillRate: Double
    let tapPower: Double
    let autoActive: Bool
    var flash: Bool = false

    @EnvironmentObject private var session: SessionStore
    @State private var anchorProgress: Double = 0
    @State private var anchorDate: Date = .now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let display = displayedBarProgress(
                progress: progress,
                total: total,
                fillRate: fillRate,
                autoActive: autoActive,
                anchorProgress: anchorProgress,
                anchorDate: anchorDate,
                now: context.date
            )
            let fraction = total > 0 ? min(1, display / Double(total)) : 0

            VStack(alignment: .leading, spacing: 10) {
                Text(formatSatsPerHour(fillRate: fillRate, unitsPerSat: total, autoActive: autoActive))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("BrandAccent"))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Text("\(Int(display.rounded(.down))) / \(total) taps")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("BrandInk"))
                        .monospacedDigit()
                    Spacer()
                    BarRateStatusView(
                        autoActive: autoActive,
                        fillRate: fillRate,
                        tapPower: tapPower
                    )
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color("BrandInk").opacity(0.06))
                            .overlay(
                                Capsule().stroke(
                                    Color("BrandAccent").opacity(flash ? 0.85 : 0.10),
                                    lineWidth: flash ? 2 : 1
                                )
                            )
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: flash
                                        ? [Color("BrandAccent"), Color.white]
                                        : [Color("BrandFill"), Color("BrandFillHot")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(flash ? 0.65 : 0.35), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                            .frame(width: max(20, geo.size.width * fraction))
                            .shadow(
                                color: (flash ? Color("BrandAccent") : Color("BrandFill")).opacity(flash ? 0.9 : 0.55),
                                radius: flash ? 18 : 10,
                                y: 0
                            )
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        Task { await session.tap() }
                    }
                }
                .frame(height: 30)
            }
        }
        .onChange(of: progress) { _, newValue in
            anchorProgress = newValue
            anchorDate = .now
        }
        .onChange(of: fillRate) { _, _ in
            anchorProgress = progress
            anchorDate = .now
        }
        .onChange(of: tapPower) { _, _ in
            anchorProgress = progress
            anchorDate = .now
        }
        .onAppear {
            anchorProgress = progress
            anchorDate = .now
        }
    }
}

/// Status above the bar: taps/s · power · fill/s — colored by Speed / Power.
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
                    .lineLimit(1)
                Text(actionLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(detailColor(visual))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("(\(applyCount))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(countColor(visual))
                    .lineLimit(1)
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
