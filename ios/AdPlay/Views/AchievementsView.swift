import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Unlock these by playing. The first three slot achievements raise how many boost ads you can hold.")
                        .font(.footnote)
                        .foregroundStyle(Color("BrandMuted"))
                    ForEach(session.progress.displayedAchievements) { a in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: a.unlocked ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(a.unlocked ? Color("BrandFill") : Color("BrandMuted"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color("BrandInk"))
                                Text(a.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color("BrandMuted"))
                            }
                            Spacer()
                            if a.grantsSlot {
                                Text(a.unlocked ? "+1 hold" : "+1")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(a.unlocked ? Color("BrandAccent") : Color("BrandMuted"))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelBg)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(panelBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(AtmosphereBackground())
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(red: 0.055, green: 0.059, blue: 0.102), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color("BrandInk"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
