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
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("BrandAccent"))
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

                VStack(spacing: 10) {
                    Text("\(state.satsBalance)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("BrandInk"))
                        .contentTransition(.numericText())
                    Text("sats")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("BrandMuted"))
                }

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
            let display = displayedProgress(at: context.date)
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
                            .fill(Color("BrandInk").opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color("BrandAccent"), Color("BrandAccentHot")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(18, geo.size.width * fraction))
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        Task { await session.tap() }
                    }
                }
                .frame(height: 28)
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

    private func displayedProgress(at now: Date) -> Double {
        guard autoActive, fillRate > 0, total > 0 else { return progress }
        let elapsed = now.timeIntervalSince(anchorDate)
        return min(Double(total), anchorProgress + fillRate * elapsed)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fillGradient(visual))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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

    private func fillGradient(_ visual: Visual) -> LinearGradient {
        switch visual {
        case .ready:
            return LinearGradient(
                colors: [Color.white.opacity(0.92), Color("BrandAccent").opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .runningReady:
            return LinearGradient(
                colors: [Color("BrandAccent").opacity(0.58), Color("BrandAccentHot").opacity(0.48)],
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
                Color(red: 0.98, green: 0.96, blue: 0.92),
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.90, green: 0.93, blue: 0.90),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Circle()
                .fill(Color("BrandAccent").opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: -120, y: -220)
            Circle()
                .fill(Color(red: 0.45, green: 0.62, blue: 0.55).opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: 140, y: 260)
        }
    }
}
