import SwiftUI
import FirebaseCore
import GoogleMobileAds

@main
struct AdPlayApp: App {
    @StateObject private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .task {
                    // Start AdMob after UI is up — calling from App.init can abort
                    // with GADInvalidInitializationException if linker/plist aren't ready.
                    await Self.startAdsIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.onForeground()
            case .background, .inactive:
                session.onBackground()
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private static func startAdsIfNeeded() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in
                cont.resume()
            }
        }
        AdMobRewardedPresenter.shared.preload()
    }
}
