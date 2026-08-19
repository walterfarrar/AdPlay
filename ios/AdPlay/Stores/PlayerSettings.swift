import Foundation
import Combine

@MainActor
final class PlayerSettings: ObservableObject {
    @Published var remindersEnabled: Bool {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: Keys.reminders) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Keys.sound) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    @Published private(set) var seenDailyGoalDay: String
    @Published private(set) var seenDailyGoalIds: [String]

    init() {
        let d = UserDefaults.standard
        remindersEnabled = d.object(forKey: Keys.reminders) as? Bool ?? true
        hapticsEnabled = d.object(forKey: Keys.haptics) as? Bool ?? true
        soundEnabled = d.object(forKey: Keys.sound) as? Bool ?? true
        hasCompletedOnboarding = d.bool(forKey: Keys.onboarding)
        seenDailyGoalDay = d.string(forKey: Keys.seenGoalDay) ?? ""
        seenDailyGoalIds = d.stringArray(forKey: Keys.seenGoalIds) ?? []
    }

    func unseenCompletedGoalCount(in goals: [DailyGoal]) -> Int {
        let seen = seenDailyGoalDay == Self.utcDayKey() ? Set(seenDailyGoalIds) : []
        return goals.filter { $0.completed && !seen.contains($0.id) }.count
    }

    func acknowledgeDailyGoals(_ goals: [DailyGoal]) {
        seenDailyGoalDay = Self.utcDayKey()
        seenDailyGoalIds = goals.filter(\.completed).map(\.id)
        let d = UserDefaults.standard
        d.set(seenDailyGoalDay, forKey: Keys.seenGoalDay)
        d.set(seenDailyGoalIds, forKey: Keys.seenGoalIds)
    }

    static func utcDayKey() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private enum Keys {
        static let reminders = "adplay.remindersEnabled"
        static let haptics = "adplay.hapticsEnabled"
        static let sound = "adplay.soundEnabled"
        static let onboarding = "adplay.hasCompletedOnboarding"
        static let seenGoalDay = "adplay.seenDailyGoalDay"
        static let seenGoalIds = "adplay.seenDailyGoalIds"
    }
}
