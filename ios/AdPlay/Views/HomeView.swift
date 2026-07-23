import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showRedeem = false

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
                                Capsule().fill(Color("BrandAccent").opacity(0.14))
                            )
                            .overlay(
                                Capsule().stroke(Color("BrandAccent").opacity(0.55), lineWidth: 1)
                            )
                    }
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

                BtcBalanceView(
                    satsBalance: state.satsBalance,
                    progress: state.progress,
                    total: state.unitsPerSat,
                    fillRate: state.fillRate,
                    autoActive: state.autoFillActive
                )

                Spacer(minLength: 28)

                ProgressBarView(
                    progress: state.progress,
                    total: state.unitsPerSat,
                    fillRate: state.fillRate,
                    autoActive: state.autoFillActive
                )
                .padding(.horizontal, 24)

                Text(
                    state.tapsRemaining > 0
                        ? "Tap the bar · \(state.tapsRemaining) taps left today"
                        : "0 taps left today"
                )
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color("BrandMuted"))
                    .padding(.top, 14)

                Spacer(minLength: 36)

                HStack(spacing: 10) {
                    BoostButton(
                        title: "Longer",
                        idleSubtitle: "Extend auto",
                        activeUntil: state.autoFillActive ? state.autoFillUntil : nil,
                        disabled: !canWatch
                    ) {
                        Task { await session.watch(boost: .duration) }
                    }
                    BoostButton(
                        title: "Faster",
                        idleSubtitle: "Raise speed",
                        activeUntil: state.autoFillActive ? state.autoFillUntil : nil,
                        activeMetric: (state.autoFillActive && state.fillRate > 0)
                            ? String(format: "%.2f/s", state.fillRate)
                            : nil,
                        disabled: !canWatch
                    ) {
                        Task { await session.watch(boost: .speed) }
                    }
                    BoostButton(
                        title: "Stronger",
                        idleSubtitle: "Boost tap power",
                        activeUntil: (state.tapStrengthActive ?? false) ? state.tapStrengthUntil : nil,
                        activeMetric: (state.tapStrengthActive ?? false)
                            ? "\(state.effectiveTapPower)/tap"
                            : nil,
                        disabled: !canWatch
                    ) {
                        Task { await session.watch(boost: .tapStrength) }
                    }
                }
                .frame(height: 96)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

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
                    autoFillUntil: state.autoFillUntil,
                    autoActive: state.autoFillActive
                )
            }
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
}

struct AdsFooterView: View {
    let adsRemaining: Int
    let cooldownLeft: Int
    let autoFillUntil: String?
    let autoActive: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            Text(footerText(at: context.date))
                .font(.caption)
                .foregroundStyle(Color("BrandMuted"))
                .padding(.bottom, 16)
        }
    }

    private func footerText(at now: Date) -> String {
        if adsRemaining <= 0 {
            let left = remainingSeconds(untilIso: autoFillUntil, now: now)
            if left > 0 {
                return "More ads in \(formatCountdown(left))"
            }
            return "More ads soon…"
        }
        if cooldownLeft > 0 {
            return "Next ad in \(cooldownLeft)s · \(adsRemaining) ads left"
        }
        return "\(adsRemaining) ads left this run"
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
    let autoActive: Bool

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
            let status = autoActive
                ? String(format: "%.2f taps/s", fillRate)
                : "Idle"

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(Int(display.rounded(.down))) / \(total) taps")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("BrandInk"))
                        .monospacedDigit()
                    Spacer()
                    Text(status)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(autoActive ? Color("BrandAccent") : Color("BrandMuted"))
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color("BrandInk").opacity(0.06))
                            .overlay(
                                Capsule().stroke(Color("BrandInk").opacity(0.10), lineWidth: 1)
                            )
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color("BrandAccent"), Color("BrandAccentHot")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                            .frame(width: max(20, geo.size.width * fraction))
                            .shadow(color: Color("BrandAccent").opacity(0.55), radius: 10, y: 0)
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
        .onAppear {
            anchorProgress = progress
            anchorDate = .now
        }
    }
}

struct BoostButton: View {
    let title: String
    let idleSubtitle: String
    var activeUntil: String? = nil
    var activeMetric: String? = nil
    let disabled: Bool
    let action: () -> Void

    private enum Visual {
        case ready, runningReady, runningLocked, locked
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = remainingSeconds(untilIso: activeUntil, now: context.date)
            let active = left > 0
            let visual: Visual = {
                if active && !disabled { return .runningReady }
                if active && disabled { return .runningLocked }
                if !disabled { return .ready }
                return .locked
            }()
            let line2 = active ? formatCountdown(left) : idleSubtitle
            let line3 = active ? (activeMetric ?? "") : ""

            Button(action: action) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor(visual))
                        .lineLimit(1)
                    Text(line2)
                        .font(.system(
                            size: 11,
                            weight: (visual == .runningReady || visual == .runningLocked) ? .bold : .medium,
                            design: .rounded
                        ))
                        .foregroundStyle(detailColor(visual))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(line3.isEmpty ? " " : line3)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(line3.isEmpty ? .clear : detailColor(visual))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(fillGradient(visual))
                        .shadow(color: shadowColor(visual), radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(borderColor(visual), lineWidth: borderWidth(visual))
                )
            }
            .disabled(disabled)
            .buttonStyle(.plain)
        }
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
        case .ready: return Color("BrandMuted")
        case .runningReady: return Color(red: 0.48, green: 0.23, blue: 0.07)
        case .runningLocked: return Color("BrandMuted").opacity(0.75)
        case .locked: return Color("BrandMuted").opacity(0.45)
        }
    }

    private func borderColor(_ visual: Visual) -> Color {
        switch visual {
        case .ready: return Color("BrandAccent").opacity(0.85)
        case .runningReady: return Color("BrandAccentHot")
        case .runningLocked: return Color("BrandMuted").opacity(0.35)
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

    private func shadowColor(_ visual: Visual) -> Color {
        switch visual {
        case .ready: return Color("BrandAccent").opacity(0.28)
        case .runningReady: return Color("BrandAccentHot").opacity(0.45)
        case .runningLocked, .locked: return Color.black.opacity(0.25)
        }
    }

    private func fillGradient(_ visual: Visual) -> LinearGradient {
        switch visual {
        case .ready:
            return LinearGradient(
                colors: [Color("BrandInk").opacity(0.08), Color("BrandAccent").opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .runningReady:
            return LinearGradient(
                colors: [Color("BrandAccent").opacity(0.85), Color("BrandAccentHot").opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .runningLocked:
            return LinearGradient(
                colors: [Color("BrandInk").opacity(0.05), Color("BrandInk").opacity(0.08)],
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

private func parseIso8601(_ value: String) -> Date? {
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
