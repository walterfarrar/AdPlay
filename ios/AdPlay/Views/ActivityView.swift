import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var session: SessionStore

    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    streakCard
                    goalsCard
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(AtmosphereBackground())
            .navigationTitle("Daily Goals")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(red: 0.055, green: 0.059, blue: 0.102), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                try? await session.refresh(force: true)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var progress: PlayerProgress { session.progress }

    private var streakCard: some View {
        panel(title: "Login streak") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.loginStreak)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("BrandAccent"))
                Text("days")
                    .foregroundStyle(Color("BrandMuted"))
                Spacer()
                Text("Best \(progress.bestLoginStreak)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("BrandInk"))
            }
            Text("Open AdPlay once each UTC day. +1 ad hold per day while the streak is alive, up to 5. Miss a day and this bonus drops to 0. Now +\(progress.adBank.streakBonus).")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
        }
    }

    private var goalsCard: some View {
        panel(title: "Daily goals") {
            Text("Each completed goal adds +1 ad hold today. Resets with the UTC day. Now +\(progress.adBank.dailyBonus).")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
            ForEach(progress.displayedDailyGoals) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                                .foregroundStyle(Color("BrandInk"))
                            Text(ProgressCatalog.howTo(for: goal))
                                .font(.caption)
                                .foregroundStyle(Color("BrandMuted"))
                        }
                        Spacer()
                        Text(goal.completed ? "Done · +1" : "\(min(goal.current, goal.target)) / \(goal.target)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(goal.completed ? Color("BrandFill") : Color("BrandMuted"))
                    }
                    ProgressView(value: Double(min(goal.current, goal.target)), total: Double(max(goal.target, 1)))
                        .tint(goal.completed ? Color("BrandFill") : Color("BrandAccent"))
                }
            }
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
