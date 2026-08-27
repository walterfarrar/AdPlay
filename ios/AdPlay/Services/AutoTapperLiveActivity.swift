import Foundation
import ActivityKit

enum AutoTapperLiveActivity {
    static func sync(state: GameState, progress: PlayerProgress, comboMultiplier: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let stage = MinerStage.from(lifetimeSats: progress.lifetimeSats)
        let ends = parseIso8601(state.autoFillUntil ?? "")
        let content = AutoTapperAttributes.ContentState(
            progressFraction: state.progressFraction,
            satsBalance: state.satsBalance,
            comboMultiplier: comboMultiplier,
            autoEndsAt: state.autoFillActive ? ends : nil,
            stageTitle: stage.title
        )
        let attrs = AutoTapperAttributes(playerTitle: stage.title)

        if state.autoFillActive {
            if let existing = Activity<AutoTapperAttributes>.activities.first {
                Task { await existing.update(.init(state: content, staleDate: ends)) }
            } else {
                do {
                    _ = try Activity<AutoTapperAttributes>.request(
                        attributes: attrs,
                        content: .init(state: content, staleDate: ends),
                        pushType: nil
                    )
                } catch {
                    // Live Activities can fail on Simulator / permission — Play still works.
                }
            }
        } else {
            let finished = content
            Task {
                for activity in Activity<AutoTapperAttributes>.activities {
                    await activity.end(.init(state: finished, staleDate: nil), dismissalPolicy: .immediate)
                }
            }
        }
    }
}
