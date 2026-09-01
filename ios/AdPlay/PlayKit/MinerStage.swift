import Foundation

/// Lifetime sats unlock ten Play backdrops. Thresholds come from Firebase
/// `config/tunables.minerStageThresholds` (defaults: 0, then 5 × 10^(level-2)).
enum MinerStage: Int, CaseIterable, Equatable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5
    case level6 = 6
    case level7 = 7
    case level8 = 8
    case level9 = 9
    case level10 = 10

    static let defaultThresholds = [0, 5, 50, 500, 5_000, 50_000, 500_000, 5_000_000, 50_000_000, 500_000_000]

    static func sanitizedThresholds(_ raw: [Int]?) -> [Int] {
        guard let raw, raw.count == defaultThresholds.count else { return defaultThresholds }
        var prev = -1
        for n in raw {
            guard n >= 0, n > prev else { return defaultThresholds }
            prev = n
        }
        return raw
    }

    static func thresholds(from tunables: Tunables?) -> [Int] {
        sanitizedThresholds(tunables?.minerStageThresholds)
    }

    static func from(lifetimeSats: Int, thresholds: [Int] = defaultThresholds) -> MinerStage {
        let sats = max(0, lifetimeSats)
        let t = sanitizedThresholds(thresholds)
        var current = MinerStage.level1
        for stage in MinerStage.allCases where sats >= stage.thresholdSats(in: t) {
            current = stage
        }
        return current
    }

    static func from(lifetimeSats: Int, tunables: Tunables?) -> MinerStage {
        from(lifetimeSats: lifetimeSats, thresholds: thresholds(from: tunables))
    }

    func thresholdSats(in thresholds: [Int] = defaultThresholds) -> Int {
        let t = Self.sanitizedThresholds(thresholds)
        let i = rawValue - 1
        if t.indices.contains(i) { return t[i] }
        return Self.defaultThresholds[i]
    }

    var level: Int { rawValue }

    var title: String {
        switch self {
        case .level1: return "Spark"
        case .level2: return "Satoshi Scout"
        case .level3: return "Farm Hand"
        case .level4: return "Rig Boss"
        case .level5: return "Floor Captain"
        case .level6: return "Plant Lead"
        case .level7: return "Hash Warden"
        case .level8: return "Mega Operator"
        case .level9: return "Campus Baron"
        case .level10: return "Genesis Foundry"
        }
    }

    var subtitle: String {
        switch self {
        case .level1: return "Garage"
        case .level2: return "Workbench"
        case .level3: return "Small farm"
        case .level4: return "Mining farm"
        case .level5: return "Warehouse"
        case .level6: return "Industrial hall"
        case .level7: return "Data hall"
        case .level8: return "Mega farm"
        case .level9: return "Hash campus"
        case .level10: return "Foundry"
        }
    }

    var imageName: String { "StageLevel\(rawValue)" }

    var wheelFaceName: String { "WheelFace\(rawValue)" }

    var next: MinerStage? {
        MinerStage(rawValue: rawValue + 1)
    }

    var isMax: Bool { next == nil }

    /// Fill toward the next level. At max, always 1.
    func progress(lifetimeSats: Int, thresholds: [Int] = defaultThresholds) -> Double {
        guard let next else { return 1 }
        let t = Self.sanitizedThresholds(thresholds)
        let span = Double(next.thresholdSats(in: t) - thresholdSats(in: t))
        guard span > 0 else { return 1 }
        let earned = Double(max(0, lifetimeSats) - thresholdSats(in: t))
        return min(1, max(0, earned / span))
    }

    func progressLabel(lifetimeSats: Int, thresholds: [Int] = defaultThresholds) -> String {
        guard let next else { return "Max level" }
        let t = Self.sanitizedThresholds(thresholds)
        return "\(max(0, lifetimeSats)) / \(next.thresholdSats(in: t)) Lifetime Sats"
    }

    /// Visual-only sat-wheel chrome. Radii / tap / combo / knocker geometry stay the same.
    var wheelChrome: WheelChrome {
        switch self {
        case .level1:
            return WheelChrome(
                discCenter: 0.92, discEdge: 0.97,
                track: 0.28, tickMinor: 0.28, tickMajor: 0.48, tickCardinal: 0.78,
                hubTop: 0.42, hubBottom: 0.28, hubStroke: 0.40,
                pointer: 0.95, plate: 0.62,
                halo: 0, bevel: 0.18, gearTeeth: 0,
                coreGlow: 0.28, fillBloom: 0, tealMix: 0, goldRim: 0
            )
        case .level2:
            return WheelChrome(
                discCenter: 0.93, discEdge: 0.97,
                track: 0.32, tickMinor: 0.32, tickMajor: 0.52, tickCardinal: 0.82,
                hubTop: 0.48, hubBottom: 0.32, hubStroke: 0.46,
                pointer: 0.96, plate: 0.68,
                halo: 0.10, bevel: 0.26, gearTeeth: 0,
                coreGlow: 0.34, fillBloom: 0.12, tealMix: 0, goldRim: 0
            )
        case .level3:
            return WheelChrome(
                discCenter: 0.94, discEdge: 0.98,
                track: 0.36, tickMinor: 0.36, tickMajor: 0.56, tickCardinal: 0.86,
                hubTop: 0.52, hubBottom: 0.36, hubStroke: 0.52,
                pointer: 0.97, plate: 0.72,
                halo: 0.16, bevel: 0.32, gearTeeth: 8,
                coreGlow: 0.40, fillBloom: 0.18, tealMix: 0, goldRim: 0
            )
        case .level4:
            return WheelChrome(
                discCenter: 0.94, discEdge: 0.98,
                track: 0.40, tickMinor: 0.38, tickMajor: 0.60, tickCardinal: 0.88,
                hubTop: 0.56, hubBottom: 0.40, hubStroke: 0.56,
                pointer: 0.97, plate: 0.76,
                halo: 0.22, bevel: 0.38, gearTeeth: 12,
                coreGlow: 0.46, fillBloom: 0.24, tealMix: 0, goldRim: 0.12
            )
        case .level5:
            return WheelChrome(
                discCenter: 0.95, discEdge: 0.98,
                track: 0.44, tickMinor: 0.42, tickMajor: 0.64, tickCardinal: 0.90,
                hubTop: 0.60, hubBottom: 0.44, hubStroke: 0.60,
                pointer: 0.98, plate: 0.80,
                halo: 0.28, bevel: 0.44, gearTeeth: 16,
                coreGlow: 0.52, fillBloom: 0.30, tealMix: 0, goldRim: 0.20
            )
        case .level6:
            return WheelChrome(
                discCenter: 0.95, discEdge: 0.98,
                track: 0.48, tickMinor: 0.46, tickMajor: 0.68, tickCardinal: 0.92,
                hubTop: 0.64, hubBottom: 0.48, hubStroke: 0.64,
                pointer: 0.98, plate: 0.84,
                halo: 0.34, bevel: 0.50, gearTeeth: 16,
                coreGlow: 0.58, fillBloom: 0.36, tealMix: 0.08, goldRim: 0.28
            )
        case .level7:
            return WheelChrome(
                discCenter: 0.95, discEdge: 0.98,
                track: 0.50, tickMinor: 0.48, tickMajor: 0.70, tickCardinal: 0.93,
                hubTop: 0.66, hubBottom: 0.50, hubStroke: 0.68,
                pointer: 0.98, plate: 0.86,
                halo: 0.38, bevel: 0.54, gearTeeth: 18,
                coreGlow: 0.64, fillBloom: 0.42, tealMix: 0.55, goldRim: 0.18
            )
        case .level8:
            return WheelChrome(
                discCenter: 0.96, discEdge: 0.99,
                track: 0.54, tickMinor: 0.52, tickMajor: 0.74, tickCardinal: 0.94,
                hubTop: 0.70, hubBottom: 0.54, hubStroke: 0.72,
                pointer: 0.99, plate: 0.90,
                halo: 0.46, bevel: 0.60, gearTeeth: 20,
                coreGlow: 0.70, fillBloom: 0.50, tealMix: 0.18, goldRim: 0.40
            )
        case .level9:
            return WheelChrome(
                discCenter: 0.96, discEdge: 0.99,
                track: 0.58, tickMinor: 0.56, tickMajor: 0.78, tickCardinal: 0.96,
                hubTop: 0.74, hubBottom: 0.58, hubStroke: 0.76,
                pointer: 0.99, plate: 0.92,
                halo: 0.54, bevel: 0.66, gearTeeth: 22,
                coreGlow: 0.78, fillBloom: 0.58, tealMix: 0.10, goldRim: 0.70
            )
        case .level10:
            return WheelChrome(
                discCenter: 0.97, discEdge: 1.0,
                track: 0.62, tickMinor: 0.60, tickMajor: 0.82, tickCardinal: 0.98,
                hubTop: 0.80, hubBottom: 0.64, hubStroke: 0.82,
                pointer: 1.0, plate: 0.95,
                halo: 0.66, bevel: 0.74, gearTeeth: 24,
                coreGlow: 0.90, fillBloom: 0.70, tealMix: 0.12, goldRim: 0.92
            )
        }
    }

    /// Visual-only auto-tapper chrome. Strike point, arm length, and gears stay put.
    var tapperChrome: TapperChrome {
        switch self {
        case .level1:
            return TapperChrome(polish: 0, halo: 0, goldTrim: 0, tealMix: 0, hammerBloom: 0, lamp: 0, extraSparks: 0)
        case .level2:
            return TapperChrome(polish: 0.12, halo: 0.14, goldTrim: 0, tealMix: 0, hammerBloom: 0.10, lamp: 0, extraSparks: 0)
        case .level3:
            return TapperChrome(polish: 0.20, halo: 0.20, goldTrim: 0, tealMix: 0, hammerBloom: 0.16, lamp: 0.55, extraSparks: 1)
        case .level4:
            return TapperChrome(polish: 0.28, halo: 0.26, goldTrim: 0.18, tealMix: 0, hammerBloom: 0.22, lamp: 0.65, extraSparks: 1)
        case .level5:
            return TapperChrome(polish: 0.36, halo: 0.34, goldTrim: 0.28, tealMix: 0, hammerBloom: 0.32, lamp: 0.75, extraSparks: 2)
        case .level6:
            return TapperChrome(polish: 0.42, halo: 0.40, goldTrim: 0.34, tealMix: 0.08, hammerBloom: 0.40, lamp: 0.82, extraSparks: 2)
        case .level7:
            return TapperChrome(polish: 0.46, halo: 0.48, goldTrim: 0.18, tealMix: 0.55, hammerBloom: 0.48, lamp: 0.90, extraSparks: 3)
        case .level8:
            return TapperChrome(polish: 0.54, halo: 0.56, goldTrim: 0.48, tealMix: 0.18, hammerBloom: 0.56, lamp: 0.92, extraSparks: 3)
        case .level9:
            return TapperChrome(polish: 0.62, halo: 0.64, goldTrim: 0.72, tealMix: 0.10, hammerBloom: 0.66, lamp: 0.96, extraSparks: 4)
        case .level10:
            return TapperChrome(polish: 0.72, halo: 0.76, goldTrim: 0.92, tealMix: 0.12, hammerBloom: 0.82, lamp: 1.0, extraSparks: 5)
        }
    }
}

struct WheelChrome: Equatable {
    var discCenter: Double
    var discEdge: Double
    var track: Double
    var tickMinor: Double
    var tickMajor: Double
    var tickCardinal: Double
    var hubTop: Double
    var hubBottom: Double
    var hubStroke: Double
    var pointer: Double
    var plate: Double
    var halo: Double
    var bevel: Double
    var gearTeeth: Int
    var coreGlow: Double
    var fillBloom: Double
    var tealMix: Double
    var goldRim: Double
}

struct TapperChrome: Equatable {
    var polish: Double
    var halo: Double
    var goldTrim: Double
    var tealMix: Double
    var hammerBloom: Double
    var lamp: Double
    var extraSparks: Int
}
