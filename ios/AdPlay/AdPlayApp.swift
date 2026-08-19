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
                .environmentObject(settings)
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
