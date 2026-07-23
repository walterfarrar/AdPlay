import Foundation
import UserNotifications

/// Local reminders keyed off Firebase server timestamps (`autoFillUntil` / `tapStrengthUntil`).
/// Device clock only affects *when* the alert fires, not how much was earned.
enum GameReminderScheduler {
    private static let idAuto = "adplay.auto_ended"
    private static let idAds = "adplay.ads_available"

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Reschedule from latest authoritative game state.
    static func sync(_ state: GameState) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [idAuto, idAds])

        let now = Date()
        let autoAt = parseDate(state.autoFillUntil).flatMap { state.autoFillActive ? $0 : nil }
        let tapActive = state.tapStrengthActive ?? false
        let tapAt = parseDate(state.tapStrengthUntil).flatMap { tapActive ? $0 : nil }

        // Ads refill when both auto and Stronger windows are gone
        let adsRefillAt: Date? = {
            if state.adsRemainingToday > 0 { return nil }
            return [autoAt, tapAt].compactMap { $0 }.max()
        }()

        let scheduleAuto = autoAt.map { $0 > now.addingTimeInterval(2) } ?? false
        let scheduleAds = adsRefillAt.map { $0 > now.addingTimeInterval(2) } ?? false

        if scheduleAuto, scheduleAds,
           let autoAt, let adsRefillAt,
           abs(autoAt.timeIntervalSince(adsRefillAt)) < 1.5 {
            // Same moment — one combined alert
            schedule(id: idAds, at: adsRefillAt, title: "More ads available",
                     body: "Your ad run refreshed — open AdPlay to watch more.")
        } else {
            if scheduleAuto, let autoAt {
                schedule(id: idAuto, at: autoAt, title: "Auto fill ended",
                         body: "Your auto timer ran out.")
            }
            if scheduleAds, let adsRefillAt {
                schedule(id: idAds, at: adsRefillAt, title: "More ads available",
                         body: "Your ad run refreshed — open AdPlay to watch more.")
            }
        }
    }

    private static func schedule(id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func parseDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return parseIso8601(iso)
    }
}
