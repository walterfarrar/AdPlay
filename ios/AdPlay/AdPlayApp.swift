import SwiftUI
import FirebaseCore

@main
struct AdPlayApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var settings = PlayerSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(session.play)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.onForeground()
            case .background:
                session.onBackground()
            // Full-screen rewarded ads (and Control Center) go inactive — do not
            // tear down or refresh, or the watch is reported as "Ad not completed".
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
