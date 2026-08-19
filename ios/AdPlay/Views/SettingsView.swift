import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    var showsClose: Bool = false
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @Environment(\.dismiss) private var dismiss

    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)
    private let supportURL = URL(string: "https://fullyversed.com/adplay/support")!
    private let privacyURL = URL(string: "https://fullyversed.com/adplay/privacy")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    panel(title: "Play") {
                        toggle("Reminders", isOn: $settings.remindersEnabled)
                        toggle("Haptics", isOn: $settings.hapticsEnabled)
                        toggle("Sound", isOn: $settings.soundEnabled)
                    }
                    panel(title: "Account") {
                        LabeledContent("Player ID") {
                            Text(playerId)
                                .font(.caption.monospaced())
                                .foregroundStyle(Color("BrandMuted"))
                                .textSelection(.enabled)
                        }
                        Link("Privacy policy", destination: privacyURL)
                            .foregroundStyle(Color("BrandAccent"))
                        Link("Support", destination: supportURL)
                            .foregroundStyle(Color("BrandAccent"))
                    }
                    panel(title: "Delete account") {
                        Text("Email support with your Player ID to request deletion of your anonymous session and game data.")
                            .font(.footnote)
                            .foregroundStyle(Color("BrandMuted"))
                        if let mail = deleteMailURL {
                            Link("Request deletion", destination: mail)
                                .foregroundStyle(Color("BrandAccent"))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(AtmosphereBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(red: 0.055, green: 0.059, blue: 0.102), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Color("BrandInk"))
                    }
                }
            }
            .onChange(of: settings.remindersEnabled) { _, enabled in
                if enabled {
                    GameReminderScheduler.requestPermissionIfNeeded()
                    GameReminderScheduler.sync(session.state)
                } else {
                    GameReminderScheduler.clearAll()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var playerId: String {
        Auth.auth().currentUser?.uid ?? "Not signed in"
    }

    private var deleteMailURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = "support@fullyversed.com"
        c.queryItems = [
            URLQueryItem(name: "subject", value: "AdPlay account deletion"),
            URLQueryItem(name: "body", value: "Please delete my AdPlay account.\n\nPlayer ID: \(playerId)\n"),
        ]
        return c.url
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .tint(Color("BrandAccent"))
            .foregroundStyle(Color("BrandInk"))
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBg)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(panelBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
