import SwiftUI

struct ThemeLook: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let productId: String?
    /// Unlocked by the first-sat achievement (not IAP).
    let earnedByFirstSat: Bool
    let fill: Color
    let fillHot: Color
    let accent: Color
    let combo: Color
    /// Hotter mid-tier combo (ring 1).
    let comboHot: Color
    /// White-hot core combo (ring 2).
    let comboCore: Color
    let glow: Color

    func comboFill(_ ring: Int) -> Color {
        switch ring {
        case 1: return comboHot
        case 2: return comboCore
        default: return combo
        }
    }

    static let ember = ThemeLook(
        id: "ember",
        name: "Ember",
        detail: "Default look.",
        productId: nil,
        earnedByFirstSat: false,
        fill: Color("BrandFill"),
        fillHot: Color("BrandFillHot"),
        accent: Color("BrandAccent"),
        combo: Color("BrandAccent"),
        comboHot: Color(red: 1.0, green: 0.76, blue: 0.29),
        comboCore: Color(red: 1.0, green: 0.95, blue: 0.77),
        glow: Color("BrandAccent")
    )

    static let copper = ThemeLook(
        id: "copper",
        name: "Copper",
        detail: "Earn your first sat to unlock.",
        productId: nil,
        earnedByFirstSat: true,
        fill: Color(red: 0.85, green: 0.52, blue: 0.28),
        fillHot: Color(red: 0.95, green: 0.68, blue: 0.32),
        accent: Color(red: 0.92, green: 0.58, blue: 0.22),
        combo: Color(red: 1.0, green: 0.78, blue: 0.42),
        comboHot: Color(red: 1.0, green: 0.88, blue: 0.52),
        comboCore: Color(red: 1.0, green: 0.96, blue: 0.84),
        glow: Color(red: 0.90, green: 0.50, blue: 0.18)
    )

    static let gold = ThemeLook(
        id: "gold",
        name: "Gold",
        detail: "Warm gold wheel and glow.",
        productId: "com.adplay.app.theme.gold",
        earnedByFirstSat: false,
        fill: Color(red: 0.95, green: 0.78, blue: 0.28),
        fillHot: Color(red: 1.0, green: 0.90, blue: 0.45),
        accent: Color(red: 0.98, green: 0.75, blue: 0.20),
        combo: Color(red: 1.0, green: 0.92, blue: 0.55),
        comboHot: Color(red: 1.0, green: 0.96, blue: 0.68),
        comboCore: Color(red: 1.0, green: 0.99, blue: 0.88),
        glow: Color(red: 0.95, green: 0.72, blue: 0.15)
    )

    static let neon = ThemeLook(
        id: "neon",
        name: "Neon",
        detail: "Cyan and magenta night farm.",
        productId: "com.adplay.app.theme.neon",
        earnedByFirstSat: false,
        fill: Color(red: 0.20, green: 0.95, blue: 0.85),
        fillHot: Color(red: 0.55, green: 0.40, blue: 1.0),
        accent: Color(red: 0.95, green: 0.30, blue: 0.85),
        combo: Color(red: 0.45, green: 0.95, blue: 1.0),
        comboHot: Color(red: 0.72, green: 0.98, blue: 1.0),
        comboCore: Color(red: 0.94, green: 1.0, blue: 1.0),
        glow: Color(red: 0.35, green: 0.55, blue: 1.0)
    )

    static let all: [ThemeLook] = [.ember, .copper, .gold, .neon]

    static func named(_ id: String) -> ThemeLook {
        all.first { $0.id == id } ?? .ember
    }

    static var iapProductIds: [String] {
        all.compactMap(\.productId)
    }
}
