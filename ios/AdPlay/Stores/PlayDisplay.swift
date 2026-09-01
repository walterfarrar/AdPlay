import Foundation
import Combine

/// Wheel / BTC / combo fields. Separate from `SessionStore` so combo taps do not
/// rebuild header, boosts, or the tab shell.
struct PlayFrame: Equatable {
    var satsBalance: Int = 0
    var progress: Double = 0
    var unitsPerSat: Int = 1000
    var fillRate: Double = 0
    var tapPower: Double = 1
    var autoFillActive: Bool = false
    var autoFillUntil: String?
    var tapsRemaining: Int = 0
    var combo: ComboState = .empty
}

@MainActor
final class PlayDisplay: ObservableObject {
    @Published private(set) var frame = PlayFrame()
    @Published private(set) var tunables: Tunables?

    func apply(state: GameState, tunables: Tunables?) {
        let comboT = ComboTunables.from(tunables)
        let next = PlayFrame(
            satsBalance: state.satsBalance,
            progress: state.progress,
            unitsPerSat: max(1, state.unitsPerSat),
            fillRate: state.fillRate,
            tapPower: state.effectiveTapPower,
            autoFillActive: state.autoFillActive,
            autoFillUntil: state.autoFillUntil,
            tapsRemaining: state.tapsRemaining,
            combo: state.combo(tunables: comboT)
        )
        if frame != next {
            frame = next
        }
        if self.tunables != tunables {
            self.tunables = tunables
        }
    }
}
