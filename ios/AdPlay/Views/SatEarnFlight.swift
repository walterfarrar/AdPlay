import AudioToolbox
import SwiftUI
import UIKit

/// Shared sat-earn flight targets in the `satEarn` coordinate space.
final class SatEarnFlight: ObservableObject {
    @Published var wheelTip: CGPoint = .zero
    @Published var redeem: CGPoint = .zero
    @Published var canvasSize: CGSize = .zero
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
            if redeemGlow {
                redeemGlowMark
            }
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
                Color.clear
                    .onAppear { flight.canvasSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in flight.canvasSize = newSize }
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
                                            flight.redeem = CGPoint(x: frame.midX, y: frame.midY)
                                        }
                                        .onChange(of: frame) { _, newFrame in
                                            flight.redeem = CGPoint(x: newFrame.midX, y: newFrame.midY)
                                        }
                                }
                            }
                        }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var redeemGlowMark: some View {
        Circle()
            .fill(Color("BrandAccent").opacity(0.28))
            .frame(width: 48, height: 48)
            .overlay(
                Circle().stroke(Color("BrandAccent").opacity(0.95), lineWidth: 2)
            )
            .shadow(color: Color("BrandAccent").opacity(0.85), radius: 16)
            .scaleEffect(1.08)
            .position(redeemTarget)
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if settings.soundEnabled {
            AudioServicesPlaySystemSound(1057)
        }
    }
}
