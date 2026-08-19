import Foundation
import UserNotifications

/// Local reminders keyed off Firebase server timestamps (`autoFillUntil` / `nextAdChargeAt`).
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

    /// Clear the app-icon badge when the player opens AdPlay.
    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [idAuto, idAds])
        clearBadge()
    }

    /// Reschedule from latest authoritative game state.
    static func sync(_ state: GameState) {
        let remindersOn = UserDefaults.standard.object(forKey: "adplay.remindersEnabled") as? Bool ?? true
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [idAuto, idAds])
        guard remindersOn else { return }

        let now = Date()
        let autoAt = parseDate(state.autoFillUntil).flatMap { state.autoFillActive ? $0 : nil }

        // Out of Boost Ads: notify when the next timed charge lands.
        let adsRefillAt = nextBoostAdRefill(from: state, now: now)

        let scheduleAuto = autoAt.map { $0 > now.addingTimeInterval(2) } ?? false
        let scheduleAds = adsRefillAt.map { $0 > now.addingTimeInterval(2) } ?? false

        if scheduleAuto, scheduleAds,
           let autoAt, let adsRefillAt,
           abs(autoAt.timeIntervalSince(adsRefillAt)) < 1.5 {
            schedule(
                id: idAds,
                at: adsRefillAt,
                title: "Boost Ad ready",
                body: "A Boost Ad charged up — open AdPlay to use it."
            )
        } else {
            if scheduleAuto, let autoAt {
                schedule(id: idAuto, at: autoAt, title: "Auto fill ended",
                         body: "Your auto timer ran out.")
            }
            if scheduleAds, let adsRefillAt {
                schedule(
                    id: idAds,
                    at: adsRefillAt,
                    title: "Boost Ad ready",
                    body: "A Boost Ad charged up — open AdPlay to use it."
                )
            }
        }
    }

    /// Only when the bank is empty — first regen charge from 0 → 1.
    private static func nextBoostAdRefill(from state: GameState, now: Date) -> Date? {
        guard state.adsRemainingToday <= 0 else { return nil }
        if let at = parseDate(state.nextAdChargeAt) {
            return at
        }
        let regenLeft = state.adRegenSecondsLeft ?? 0
        guard regenLeft > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(regenLeft))
    }

    private static func schedule(id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1

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
