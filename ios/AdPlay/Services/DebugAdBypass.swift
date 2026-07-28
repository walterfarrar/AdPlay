import Foundation

/// Runtime ad bypass for testing. When enabled, boost buttons skip the ad
/// waterfall and credit via mockComplete (cooldown / timers still apply).
///
/// Shown in the UI when server `debugReset` is on (same gate as Reset).
/// Preference defaults to on so test installs skip ads until you turn it off in-app.
enum DebugAdBypass {
    private static let key = "adplay.debug.bypassAds"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
