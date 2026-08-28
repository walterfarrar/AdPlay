import SwiftUI
import AuthenticationServices
import FirebaseAuth

struct SettingsView: View {
    var showsClose: Bool = false
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var appleCollision = false

    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)
    private let supportURL = URL(string: "https://fullyversed.com/adplay/support")!
    private let privacyURL = URL(string: "https://fullyversed.com/adplay/privacy")!

    var body: some View {
        NavigationStack {
            FitPage {
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
                        if session.appleLinked {
                            Text("Progress is saved with Apple. Sign in on a new iPhone to restore this account.")
                                .font(.footnote)
                                .foregroundStyle(Color("BrandMuted"))
                        } else {
                            Text("Keep sats and progress when you get a new phone. Play still starts without signing in.")
                                .font(.footnote)
                                .foregroundStyle(Color("BrandMuted"))
                            AppleSignInButton(isEnabled: !session.isLoading) { result in
                                Task { await saveProgressWithApple(result) }
                            }
                            .frame(height: 44)
                            .accessibilityLabel("Save progress with Apple")
                        }
                        Link("Privacy policy", destination: privacyURL)
                            .foregroundStyle(Color("BrandAccent"))
                        Link("Support", destination: supportURL)
                            .foregroundStyle(Color("BrandAccent"))
                        if let err = session.errorMessage, !err.isEmpty {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(Color("BrandPower"))
                        }
                    }
                    panel(title: "Delete account") {
                        Text("Permanently erase this anonymous session and all game data on the server. This cannot be undone.")
                            .font(.footnote)
                            .foregroundStyle(Color("BrandMuted"))
                        Button("Delete my account") {
                            confirmDelete = true
                        }
                        .foregroundStyle(Color(red: 1, green: 0.37, blue: 0.48))
                        .disabled(session.isLoading)
                    }
                }
            }
            .background(AtmosphereBackground(look: ThemeLook.named(settings.selectedLookId)))
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
            .onAppear { session.refreshAppleLink() }
            .onChange(of: settings.remindersEnabled) { _, enabled in
                if enabled {
                    GameReminderScheduler.requestPermissionIfNeeded()
                    GameReminderScheduler.sync(session.state)
                } else {
                    GameReminderScheduler.clearAll()
                }
            }
            .alert("Delete account?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete account", role: .destructive) {
                    Task {
                        if await session.deleteAccount() {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("This is permanent and cannot be undone. Your sats, play progress, combo, and any pending withdrawals will be erased. A new empty session will start on this device.")
            }
            .alert("Apple ID already has an account", isPresented: $appleCollision) {
                Button("Keep this device", role: .cancel) {
                    session.discardPendingApple()
                }
                Button("Use saved Apple account") {
                    Task { _ = await session.useSavedAppleAccount() }
                }
            } message: {
                Text("This Apple ID is already linked to another AdPlay account. Using it will load that account on this device and leave this device’s unsaved progress behind.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var playerId: String {
        Auth.auth().currentUser?.uid ?? "Not signed in"
    }

    private func saveProgressWithApple(_ result: Result<ASAuthorization, Error>) async {
        let outcome = await session.saveProgressWithApple(result: result)
        if outcome == .needsChoice { appleCollision = true }
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
