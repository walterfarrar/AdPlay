import Foundation

/// Runtime ad bypass for debug builds. When enabled, boost buttons skip AdsBitvex
/// and credit via mockComplete (cooldown / timers still apply).
///
/// Compile gate: only available when `DEBUG_BYPASS_ADS` is defined (Debug in project.yml).
/// Preference defaults to on so debug installs skip ads until you turn it off in-app.
enum DebugAdBypass {
    private static let key = "adplay.debug.bypassAds"

    static var available: Bool {
        #if DEBUG_BYPASS_ADS
        true
        #else
        false
        #endif
    }

    static var isEnabled: Bool {
        get {
            guard available else { return false }
            if UserDefaults.standard.object(forKey: key) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            guard available else { return }
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
