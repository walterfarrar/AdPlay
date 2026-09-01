import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: PlayerSettings
    @State private var tab = 0

    var body: some View {
        SatEarnFlightHost {
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Label("Play", systemImage: "play.circle.fill") }
                    .tag(0)
                ActivityView()
                    .tabItem { Label("Daily Goals", systemImage: "checkmark.circle.fill") }
                    .badge(goalBadge)
                    .tag(1)
                StoreView()
                    .tabItem { Label("Store", systemImage: "bag.fill") }
                    .tag(2)
                RedeemView(showsClose: false)
                    .tabItem { Label("Redeem", systemImage: "bolt.fill") }
                    .tag(3)
            }
            .tint(Color("BrandAccent"))
            .preferredColorScheme(.dark)
        }
        .onChange(of: tab) { _, t in
            session.flushPublishedProgress()
            if t == 1 {
                settings.acknowledgeDailyGoals(session.progress.displayedDailyGoals)
            }
        }
        .onChange(of: session.progress.displayedDailyGoals) { _, goals in
            if tab == 1 {
                settings.acknowledgeDailyGoals(goals)
            }
        }
    }

    private var goalBadge: Text? {
        let n = settings.unseenCompletedGoalCount(in: session.progress.displayedDailyGoals)
        return n > 0 ? Text("\(n)") : nil
    }
}
