import SwiftUI

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

struct MinerStageBackdrop: View {
    let stage: MinerStage

    var body: some View {
        ZStack {
            stageGlow
            HStack(alignment: .bottom, spacing: 10) {
                rig(height: stage.rawValue >= 0 ? 28 : 16, lit: stage.rawValue >= 0)
                rig(height: stage.rawValue >= 1 ? 40 : 18, lit: stage.rawValue >= 1)
                rig(height: stage.rawValue >= 2 ? 52 : 22, lit: stage.rawValue >= 2)
                if stage == .rig {
                    rig(height: 64, lit: true)
                }
            }
            .opacity(0.55)
        }
        .allowsHitTesting(false)
    }

    private var stageGlow: some View {
        Circle()
            .fill(Color("BrandAccent").opacity(stage == .rig ? 0.22 : 0.10))
            .frame(width: 220, height: 220)
            .blur(radius: 36)
    }

    private func rig(height: CGFloat, lit: Bool) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color("BrandInk").opacity(lit ? 0.35 : 0.12))
                .frame(width: 22, height: height)
            Capsule()
                .fill((lit ? Color("BrandFill") : Color("BrandMuted")).opacity(lit ? 0.7 : 0.25))
                .frame(width: 16, height: 4)
        }
    }
}
