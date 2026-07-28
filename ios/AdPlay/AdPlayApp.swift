import SwiftUI
import FirebaseCore
import GoogleMobileAds

@main
struct AdPlayApp: App {
    @StateObject private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        MobileAds.shared.start { _ in
            Task { @MainActor in
                AdMobRewardedPresenter.shared.preload()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
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
}
