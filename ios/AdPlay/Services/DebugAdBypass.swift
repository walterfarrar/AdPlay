import Foundation

/// Runtime ad bypass for debug builds. When enabled, boost buttons skip the ad
/// waterfall and credit via mockComplete (cooldown / timers still apply).
///
/// Compile gate: only available when `DEBUG_BYPASS_ADS` is set (Debug config in
/// project.yml). Preference defaults to on so debug installs skip ads until you
/// turn it off in-app. Release / TestFlight builds always report disabled.
enum DebugAdBypass {
    private static let key = "adplay.debug.bypassAds"

    /// Feature compiled into this binary (Debug builds only).
    static var available: Bool {
        #if DEBUG_BYPASS_ADS
        return true
        #else
        return false
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
