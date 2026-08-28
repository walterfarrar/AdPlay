import AudioToolbox
import SwiftUI
import UIKit

private let satEarnHaptic = UIImpactFeedbackGenerator(style: .medium)

/// Shared sat-earn flight targets in the `satEarn` coordinate space.
final class SatEarnFlight: ObservableObject {
    @Published var wheelTip: CGPoint = .zero
    @Published var redeem: CGPoint = .zero
    @Published var canvasSize: CGSize = .zero

    /// Ignore sub-point jitter so 60 fps layout does not republish the whole Play shell.
    func setWheelTip(_ next: CGPoint) {
        if hypot(wheelTip.x - next.x, wheelTip.y - next.y) < 1.5 { return }
        wheelTip = next
    }
}

/// Hosts the sat orb overlay above the tab bar so a earned sat can land on Redeem.
struct SatEarnFlightHost<Content: View>: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @StateObject private var flight = SatEarnFlight()
    @State private var satParticles: [SatParticle] = []
    @State private var redeemGlow = false
    @State private var lastCelebrateAt: Date = .distantPast
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
            redeemTabAnchor
            ForEach(satParticles) { particle in
                FlyingSatParticleView(particle: particle) {
                    satParticles.removeAll { $0.id == particle.id }
                }
            }
        }
        .coordinateSpace(name: "satEarn")
        .environmentObject(flight)
        .background(
            GeometryReader { geo in
                let global = geo.frame(in: .global)
                Color.clear
                    .onAppear { flight.canvasSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in flight.canvasSize = newSize }
                    .background(
                        RedeemTabBarProbe(glow: redeemGlow) { windowPoint in
                            let next = CGPoint(
                                x: windowPoint.x - global.minX,
                                y: windowPoint.y - global.minY
                            )
                            if abs(flight.redeem.x - next.x) > 0.5
                                || abs(flight.redeem.y - next.y) > 0.5 {
                                flight.redeem = next
                            }
                        }
                    )
            }
        )
        .onChange(of: session.state.satsBalance) { oldValue, newValue in
            let gained = newValue - oldValue
            guard gained > 0 else { return }
            celebrateSatEarn(gained: gained)
        }
    }

    /// Four equal columns matching the tab bar; Redeem is the trailing item.
    private var redeemTabAnchor: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                        .background {
                            if index == 3 {
                                GeometryReader { geo in
                                    let frame = geo.frame(in: .named("satEarn"))
                                    Color.clear
                                        .onAppear {
                                            if flight.redeem == .zero {
                                                flight.redeem = CGPoint(x: frame.midX, y: frame.midY)
                                            }
                                        }
                                        .onChange(of: frame) { _, newFrame in
                                            if flight.redeem == .zero {
                                                flight.redeem = CGPoint(
                                                    x: newFrame.midX,
                                                    y: newFrame.midY
                                                )
                                            }
                                        }
                                }
                            }
                        }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var redeemTarget: CGPoint {
        if flight.redeem != .zero { return flight.redeem }
        let size = flight.canvasSize
        return CGPoint(
            x: max(24, size.width * 7 / 8),
            y: max(36, size.height - 24)
        )
    }

    private func celebrateSatEarn(gained: Int) {
        let bursts = min(max(gained, 1), 4)
        for i in 0..<bursts {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                fireSatCelebrationBeat()
            }
        }
    }

    private func fireSatCelebrationBeat() {
        let now = Date()
        guard now.timeIntervalSince(lastCelebrateAt) >= 0.12 || satParticles.isEmpty else { return }
        lastCelebrateAt = now

        let size = flight.canvasSize
        let from = flight.wheelTip != .zero
            ? flight.wheelTip
            : CGPoint(x: max(24, size.width * 0.38), y: size.height * 0.38)
        let to = redeemTarget
        if satParticles.count < 4, size.width > 0 {
            satParticles.append(SatParticle(from: from, to: to))
        }

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

        if settings.hapticsEnabled {
            satEarnHaptic.impactOccurred()
        }
        if settings.soundEnabled {
            AudioServicesPlaySystemSound(1057)
        }
    }
}

/// Reads the trailing UITabBar button so the orb lands on Redeem, and pulses that item.
private struct RedeemTabBarProbe: UIViewRepresentable {
    var glow: Bool
    var onWindowPoint: (CGPoint) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindowPoint = onWindowPoint
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onWindowPoint = onWindowPoint
        uiView.setGlow(glow)
        uiView.reportSoon()
    }

    final class ProbeView: UIView {
        var onWindowPoint: ((CGPoint) -> Void)?
        private var glowing = false
        private weak var lastButton: UIView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                applyGlow(to: lastButton, on: false, animated: false)
            }
            reportSoon()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportSoon()
        }

        func setGlow(_ on: Bool) {
            let button = redeemButton()
            let changed = glowing != on || lastButton !== button
            glowing = on
            lastButton = button
            applyGlow(to: button, on: on, animated: changed)
        }

        func reportSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.report()
            }
        }

        private func report() {
            guard let button = redeemButton() else { return }
            lastButton = button
            if glowing {
                applyGlow(to: button, on: true, animated: false)
            }
            let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
            onWindowPoint?(button.convert(center, to: nil))
        }

        private func applyGlow(to button: UIView?, on: Bool, animated: Bool) {
            guard let button else { return }
            button.superview?.clipsToBounds = false
            button.superview?.layer.masksToBounds = false
            let accent = UIColor(named: "BrandAccent")
                ?? UIColor(red: 0.969, green: 0.580, blue: 0.102, alpha: 1)
            let updates = {
                button.layer.masksToBounds = false
                button.layer.shadowColor = accent.cgColor
                button.layer.shadowOffset = .zero
                button.layer.shadowRadius = on ? 12 : 0
                button.layer.shadowOpacity = on ? 0.95 : 0
                button.transform = on
                    ? CGAffineTransform(scaleX: 1.08, y: 1.08)
                    : .identity
            }
            if animated {
                UIView.animate(
                    withDuration: on ? 0.28 : 0.45,
                    delay: 0,
                    usingSpringWithDamping: on ? 0.55 : 1,
                    initialSpringVelocity: 0.35,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: updates
                )
            } else {
                updates()
            }
        }

        private func redeemButton() -> UIView? {
            guard let tabBar = findTabBar() else { return nil }
            let buttons = tabBar.subviews.filter { view in
                let name = String(describing: type(of: view))
                return name.contains("Button") && !view.isHidden
            }.sorted { $0.frame.minX < $1.frame.minX }
            if buttons.count >= 4 { return buttons[3] }
            return buttons.last
        }

        private func findTabBar() -> UITabBar? {
            var current: UIView? = superview
            while let view = current {
                if let bar = view as? UITabBar { return bar }
                current = view.superview
            }
            guard let root = window else { return nil }
            return findTabBar(in: root)
        }

        private func findTabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for child in view.subviews {
                if let found = findTabBar(in: child) { return found }
            }
            return nil
        }
    }
}
