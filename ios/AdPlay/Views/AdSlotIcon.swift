import SwiftUI

/// Gold coin stamped with a play mark — one Ad Token (spend to watch a Boost Ad).
struct AdSlotIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color("BrandAccentHot"),
                            Color("BrandAccent"),
                            Color(red: 0.72, green: 0.42, blue: 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Circle()
                .stroke(Color(red: 0.45, green: 0.24, blue: 0.04), lineWidth: size * 0.07)
            Circle()
                .stroke(Color.white.opacity(0.38), lineWidth: size * 0.055)
                .padding(size * 0.14)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.94))
                .offset(x: size * 0.025)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
