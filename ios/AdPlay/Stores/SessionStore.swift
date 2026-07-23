import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var state: GameState = .empty
    @Published var tunables: Tunables?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isReady = false
    @Published var bypassAds: Bool = DebugAdBypass.isEnabled

    let api = APIClient()
    private var adService: AdServing?
    private var tickTask: Task<Void, Never>?
    private var lastUpdatedAt: String?

    /// Last authoritative snapshot and when it arrived. While an auto window runs we
    /// project the display from this anchor locally, so Firebase is only hit on real
    /// changes (start, foreground, a mutation, or once when a window ends).
    private var serverState: GameState = .empty
    private var anchorDate: Date = .now
    private var windowEndHandled = false
    private var foreground = false

    /// Same gate as Reset — server `debugReset` (TestFlight/Release included).
    var bypassAdsAvailable: Bool {
        tunables?.debugReset != false
    }

    func start() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            GameReminderScheduler.requestPermissionIfNeeded()
            try await refresh(force: true)
            adService = AdServiceFactory.make(api: api, provider: tunables?.adProvider ?? "adsbitvex")
            isReady = true
            foreground = true
            ensureTicker()
        } catch {
            isReady = false
            errorMessage = error.localizedDescription
        }
    }

    /// App came to the foreground: re-sync once, then animate locally.
    func onForeground() {
        foreground = true
        guard isReady else { return }
        Task { try? await refresh(force: true) }
        ensureTicker()
    }

    /// App backgrounded: stop the local animation loop.
    func onBackground() {
        foreground = false
        tickTask?.cancel()
        tickTask = nil
    }

    func refresh(force: Bool = false) async throws {
        let (s, t) = try await api.fetchState()
        tunables = t
        if let provider = t?.adProvider {
            adService = AdServiceFactory.make(api: api, provider: provider)
        }
        setServerState(s, force: force)
    }

    func tap() async {
        guard state.tapsRemaining > 0 else { return }
        do {
            let next = try await api.tap()
            apply(next, force: true)
        } catch {
            // Out of taps / transient
        }
    }

    func watch(boost: BoostType) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            guard let adService else {
                throw APIError.message("Ad service not ready")
            }
            apply(try await adService.showBoostAd(type: boost), force: true)
        } catch {
            errorMessage = error.localizedDescription
            try? await refresh(force: true)
        }
    }

    func withdraw(amountSats: Int, bolt11: String) async -> Bool {
        errorMessage = nil
        do {
            apply(try await api.requestWithdrawal(amountSats: amountSats, bolt11: bolt11), force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setBypassAds(_ enabled: Bool) {
        guard bypassAdsAvailable else { return }
        DebugAdBypass.isEnabled = enabled
        bypassAds = enabled
    }

    func debugReset() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await api.debugReset(), force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ next: GameState, force: Bool) {
        setServerState(next, force: force)
    }

    /// Adopt an authoritative server snapshot. It always overrides locally projected
    /// values, so a tampered client can never keep fake progress or balance.
    private func setServerState(_ next: GameState, force: Bool) {
        if !force, let incoming = next.updatedAt, let last = lastUpdatedAt, incoming < last {
            return
        }
        if let u = next.updatedAt {
            lastUpdatedAt = u
        }
        serverState = next
        anchorDate = Date()
        windowEndHandled = false
        state = project(next, now: anchorDate)
        GameReminderScheduler.sync(next)
        ensureTicker()
    }

    /// Local, network-free animation loop. While an auto window runs everything is
    /// deterministic, so we project from the last snapshot instead of polling. When the
    /// window ends we hit the server once for the authoritative reset (ads refilled).
    private func ensureTicker() {
        guard foreground, tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.foreground {
                self.state = self.project(self.serverState, now: Date())

                if self.serverState.autoFillActive, !self.windowEndHandled,
                   let until = parseIso8601(self.serverState.autoFillUntil ?? ""),
                   Date() >= until {
                    self.windowEndHandled = true
                    try? await self.refresh(force: true)
                }

                if !self.state.autoFillActive && self.state.adCooldownSecondsLeft <= 0 {
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self.tickTask = nil
        }
    }

    /// Project a server snapshot forward by wall-clock elapsed time (display only).
    private func project(_ s: GameState, now: Date) -> GameState {
        let elapsed = max(0, now.timeIntervalSince(anchorDate))
        let cooldown = max(0, Int(ceil(Double(s.adCooldownSecondsLeft) - elapsed)))
        let until = parseIso8601(s.autoFillUntil ?? "")
        let autoActive = s.autoFillActive && (until.map { $0 > now } ?? false)

        guard s.autoFillActive, s.fillRate > 0, s.unitsPerSat > 0, let until else {
            var c = s
            c.adCooldownSecondsLeft = cooldown
            c.autoFillActive = autoActive
            return c
        }

        let earnUntil = min(now, until)
        let earnSec = max(0, earnUntil.timeIntervalSince(anchorDate))
        let total = s.progress + s.fillRate * earnSec
        var bars = Int(floor(total / Double(s.unitsPerSat)))
        let maxBars = max(0, s.dailySatsEarnCap - s.satsEarnedToday)
        bars = max(0, min(bars, maxBars))
        let newProgress = min(Double(s.unitsPerSat), max(0, total - Double(bars) * Double(s.unitsPerSat)))

        var c = s
        c.progress = newProgress
        c.satsBalance = s.satsBalance + bars
        c.satsEarnedToday = s.satsEarnedToday + bars
        c.adCooldownSecondsLeft = cooldown
        c.autoFillActive = autoActive
        return c
    }
}
