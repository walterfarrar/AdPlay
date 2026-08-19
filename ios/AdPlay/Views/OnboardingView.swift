import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: PlayerSettings
    @State private var page = 0

    private let pages: [(title: String, body: String, icon: String)] = [
        (
            "Tap the wheel",
            "Each tap fills the progress wheel. Fill it completely to earn 1 sat — a tiny unit of Bitcoin.",
            "circle.hexagongrid.fill"
        ),
        (
            "Ads are currency",
            "Boost ads sit in a hold bank. Daily goals, login streaks, achievements, and optional extra slots raise how many you can hold.",
            "play.rectangle.fill"
        ),
        (
            "Watch ads to boost",
            "Activate Auto Tapper, then watch Longer, Faster, or Stronger to speed up earning. Ads are optional.",
            "bolt.fill"
        ),
        (
            "Redeem over Lightning",
            "When you have enough sats, paste a Lightning invoice on Redeem.",
            "bolt.horizontal.fill"
        ),
    ]

    var body: some View {
        ZStack {
            AtmosphereBackground()
            VStack(spacing: 28) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        VStack(spacing: 18) {
                            Image(systemName: pages[i].icon)
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(Color("BrandAccent"))
                            Text(pages[i].title)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color("BrandInk"))
                            Text(pages[i].body)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Color("BrandMuted"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        settings.hasCompletedOnboarding = true
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Start playing")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                        .frame(maxWidth: 360)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color("BrandAccent"), Color("BrandAccentHot")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
    }
}
