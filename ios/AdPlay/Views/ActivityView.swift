import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var session: SessionStore

    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)

    var body: some View {
        NavigationStack {
            FitPage {
                VStack(alignment: .leading, spacing: 16) {
                    streakCard
                    goalsCard
                }
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
                Text(progress.loginStreak == 1 ? "day" : "days")
                    .foregroundStyle(Color("BrandMuted"))
                Spacer()
                Text("Best \(progress.bestLoginStreak)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("BrandInk"))
            }
            StreakTimeline(days: progress.loginStreak)
                .padding(.top, 4)
            HStack(alignment: .top, spacing: 8) {
                AdSlotIcon(size: 18)
                Text("Check in once each UTC day. Extra Ad Tokens unlock at days 1, 3, 5, 7, and 30. Miss a day and those tokens reset. Now +\(progress.adBank.streakBonus).")
                    .font(.footnote)
                    .foregroundStyle(Color("BrandMuted"))
            }
        }
    }

    private var goalsCard: some View {
        panel(title: "Daily goals") {
            HStack(alignment: .top, spacing: 8) {
                AdSlotIcon(size: 18)
                Text("Each completed goal adds +1 Ad Token today. Resets with the UTC day. Now +\(progress.adBank.dailyBonus).")
                    .font(.footnote)
                    .foregroundStyle(Color("BrandMuted"))
            }
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
                        if goal.completed {
                            HStack(spacing: 4) {
                                AdSlotIcon(size: 14)
                                Text("Done · +1 token")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color("BrandFill"))
                            }
                        } else {
                            Text("\(min(goal.current, goal.target)) / \(goal.target)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color("BrandMuted"))
                        }
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

/// Days 1–7 are dotted; 7→30 is a long fill with only the day-30 stop.
private struct StreakTimeline: View {
    let days: Int

    private let marks = ProgressCatalog.streakMilestones
    private let accent = Color("BrandAccent")
    private let muted = Color("BrandMuted")
    private let ink = Color("BrandInk")
    private let track = Color(red: 0.169, green: 0.176, blue: 0.239)

    var body: some View {
        GeometryReader { geo in
            let inset = 16.0
            let usable = max(geo.size.width - inset * 2, 1)
            let nodeSlot: CGFloat = 22
            let railY = nodeSlot / 2
            let fillWidth = usable * ProgressCatalog.streakTrackFill(days: days)

            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(track)
                        .frame(width: usable, height: 4)
                        .position(x: inset + usable / 2, y: railY)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, Color("BrandAccentHot")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(fillWidth, days > 0 ? 8 : 0), height: 4)
                        .position(x: inset + max(fillWidth, 0) / 2, y: railY)

                    ForEach(marks) { mark in
                        let x = inset + usable * ProgressCatalog.streakRailX(day: mark.day)
                        let reached = days >= mark.day
                        node(for: mark, reached: reached)
                            .frame(width: nodeSlot, height: nodeSlot)
                            .position(x: x, y: railY)
                    }
                }
                .frame(height: nodeSlot)

                ZStack(alignment: .topLeading) {
                    ForEach(marks) { mark in
                        let x = inset + usable * ProgressCatalog.streakRailX(day: mark.day)
                        let reached = days >= mark.day
                        Text("\(mark.day)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(reached ? ink : muted)
                            .frame(width: 36)
                            .position(x: x, y: 8)
                    }
                }
                .frame(height: 16)
            }
        }
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Login streak timeline, \(days) days")
    }

    @ViewBuilder
    private func node(for mark: StreakMilestone, reached: Bool) -> some View {
        if mark.grantsToken {
            AdSlotIcon(size: mark.isLongRun ? 22 : 18)
                .opacity(reached ? 1 : 0.38)
        } else {
            ZStack {
                Circle()
                    .fill(Color(red: 0.090, green: 0.094, blue: 0.149))
                Circle()
                    .stroke(reached ? accent : track, lineWidth: 1.5)
                if reached {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 14, height: 14)
        }
    }
}
