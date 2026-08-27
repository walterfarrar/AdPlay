enum MinerStage: Int, CaseIterable {
    case garage = 0
    case bench = 1
    case farm = 2
    case rig = 3

    static func from(lifetimeSats: Int) -> MinerStage {
        if lifetimeSats >= 500 { return .rig }
        if lifetimeSats >= 50 { return .farm }
        if lifetimeSats >= 1 { return .bench }
        return .garage
    }

    var title: String {
        switch self {
        case .garage: return "Spark"
        case .bench: return "Satoshi Scout"
        case .farm: return "Farm Hand"
        case .rig: return "Rig Boss"
        }
    }

    var subtitle: String {
        switch self {
        case .garage: return "Garage"
        case .bench: return "Workbench"
        case .farm: return "Small farm"
        case .rig: return "Mining farm"
        }
    }
}
