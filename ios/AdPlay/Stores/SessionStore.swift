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
    /// True while Skip Time is animating display toward the new server snapshot.
    private var skipAnimating = false
    private var skipLerpTask: Task<Void, Never>?
    private static let skipLerpSeconds: TimeInterval = 3

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
            adService = AdServiceFactory.make(api: api, provider: tunables?.adProvider ?? "waterfall")
            configureAdMobUnit()
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
        configureAdMobUnit()
        Task { try? await refresh(force: true) }
        ensureTicker()
    }

    /// App backgrounded: stop the local animation loop.
    func onBackground() {
        foreground = false
        tickTask?.cancel()
        tickTask = nil
        if skipAnimating {
            skipLerpTask?.cancel()
            skipLerpTask = nil
            skipAnimating = false
            anchorDate = Date()
            windowEndHandled = false
            state = project(serverState, now: Date())
        }
        // Keep Boost Ad refill / auto-end reminders aligned when leaving the app.
        GameReminderScheduler.sync(project(serverState, now: Date()))
    }

    func refresh(force: Bool = false) async throws {
        let (s, t) = try await api.fetchState()
        tunables = t
        if let provider = t?.adProvider {
            adService = AdServiceFactory.make(api: api, provider: provider)
        }
        configureAdMobUnit()
        setServerState(s, force: force)
    }

    /// TestFlight is Release (`#if DEBUG` is false). Use Google sample units while
    /// `debugReset` is on so AdMob fills instead of falling through to AdsBitvex.
    private func configureAdMobUnit() {
        #if DEBUG
        let useSample = true
        #else
        let useSample = tunables?.debugReset != false
        #endif
        AdMobRewardedPresenter.shared.configure(useSampleAds: useSample)
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
        do {
            guard let adService else {
                throw APIError.message("Ad service not ready")
            }
            let from = state
            let to = try await adService.showBoostAd(type: boost)
            isLoading = false
            if boost == .skipTime {
                await playSkipLerp(from: from, to: to)
            } else {
                apply(to, force: true)
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            try? await refresh(force: true)
        }
    }

    /// Lerp progress / sats / auto timer / regen over a few seconds after Skip Time.
    private func playSkipLerp(from: GameState, to: GameState) async {
        skipLerpTask?.cancel()
        tickTask?.cancel()
        tickTask = nil
        skipAnimating = true

        if let u = to.updatedAt {
            lastUpdatedAt = u
        }
        serverState = to
        GameReminderScheduler.sync(to)

        let duration = Self.skipLerpSeconds
        let start = Date()
        let units = max(1, to.unitsPerSat)
        let fromAbs = Double(from.satsBalance) * Double(units) + from.progress
        let toAbs = Double(to.satsBalance) * Double(units) + to.progress
        let fromAuto = Double(remainingSeconds(untilIso: from.autoFillUntil))
        let toAuto = Double(remainingSeconds(untilIso: to.autoFillUntil))
        let fromRegen = Double(from.adRegenSecondsLeft ?? 0)
        let toRegen = Double(to.adRegenSecondsLeft ?? 0)
        let fromAds = from.adsRemainingToday
        let toAds = to.adsRemainingToday

        let task = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let u = min(1, elapsed / duration)
                // Ease-out cubic
                let e = 1 - pow(1 - u, 3)

                var d = to
                // Freeze normal fill overlay so we only show the lerp.
                d.fillRate = 0

                let absProg = fromAbs + (toAbs - fromAbs) * e
                let sats = Int(floor(absProg / Double(units)))
                var prog = absProg - Double(sats) * Double(units)
                if prog < 0 { prog = 0 }
                if prog >= Double(units) { prog = Double(units) - 0.0001 }
                d.satsBalance = sats
                d.progress = prog
                d.satsEarnedToday = from.satsEarnedToday + max(0, sats - from.satsBalance)

                let autoLeft = max(0, fromAuto + (toAuto - fromAuto) * e)
                if autoLeft > 0.05 {
                    d.autoFillActive = true
                    d.autoFillUntil = iso8601String(Date().addingTimeInterval(autoLeft))
                } else {
                    d.autoFillActive = to.autoFillActive && toAuto > 0
                    d.autoFillUntil = to.autoFillUntil
                }

                let regenLeft = max(0, fromRegen + (toRegen - fromRegen) * e)
                d.adRegenSecondsLeft = Int(regenLeft.rounded())
                if regenLeft > 0.5 {
                    d.nextAdChargeAt = iso8601String(Date().addingTimeInterval(regenLeft))
                } else {
                    d.nextAdChargeAt = to.nextAdChargeAt
                }

                // Reveal unlocked charges near the end of the animation.
                d.adsRemainingToday = e < 0.85 ? fromAds : toAds

                self.state = d
                if u >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
        skipLerpTask = task
        await task.value

        skipAnimating = false
        skipLerpTask = nil
        guard !Task.isCancelled else { return }
        anchorDate = Date()
        windowEndHandled = false
        state = project(to, now: Date())
        ensureTicker()
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
        GameReminderScheduler.sync(state)
        ensureTicker()
    }

    /// Local, network-free animation loop. While an auto window runs everything is
    /// deterministic, so we project from the last snapshot instead of polling. When the
    /// window ends we hit the server once for the authoritative reset (ads refilled).
    private func ensureTicker() {
        guard foreground, tickTask == nil, !skipAnimating else { return }
        tickTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.foreground && !self.skipAnimating {
                self.state = self.project(self.serverState, now: Date())

                if self.serverState.autoFillActive, !self.windowEndHandled,
                   let until = parseIso8601(self.serverState.autoFillUntil ?? ""),
                   Date() >= until {
                    self.windowEndHandled = true
                    try? await self.refresh(force: true)
                }

                let regenLeft = self.state.adRegenSecondsLeft ?? 0
                let adsMax = self.tunables?.adsPerCycle ?? 10
                let waitingRegen = regenLeft > 0 && self.state.adsRemainingToday < adsMax
                if !self.state.autoFillActive
                    && self.state.adCooldownSecondsLeft <= 0
                    && !waitingRegen {
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
        let (adsLeft, regenLeft) = projectAdCharges(s, now: now)

        guard s.autoFillActive, s.fillRate > 0, s.unitsPerSat > 0, let until else {
            var c = s
            c.adCooldownSecondsLeft = cooldown
            c.autoFillActive = autoActive
            c.adsRemainingToday = adsLeft
            c.adRegenSecondsLeft = regenLeft
            if !autoActive {
                c.durationBoostActive = false
                c.speedBoostActive = false
                c.tapStrengthActive = false
                c.durationBoostCount = 0
                c.speedBoostCount = 0
                c.tapStrengthBoostCount = 0
            }
            return c
        }

        let earnUntil = min(now, until)
        let earnSec = max(0, earnUntil.timeIntervalSince(anchorDate))
        let total = s.progress + s.fillRate * earnSec
        var bars = max(0, Int(floor(total / Double(s.unitsPerSat))))
        // dailySatsEarnCap <= 0 means unlimited
        if s.dailySatsEarnCap > 0 {
            bars = min(bars, max(0, s.dailySatsEarnCap - s.satsEarnedToday))
        }
        let newProgress = min(Double(s.unitsPerSat), max(0, total - Double(bars) * Double(s.unitsPerSat)))

        var c = s
        c.progress = newProgress
        c.satsBalance = s.satsBalance + bars
        c.satsEarnedToday = s.satsEarnedToday + bars
        c.adCooldownSecondsLeft = cooldown
        c.autoFillActive = autoActive
        c.adsRemainingToday = adsLeft
        c.adRegenSecondsLeft = regenLeft
        if !autoActive {
            c.durationBoostActive = false
            c.speedBoostActive = false
            c.tapStrengthActive = false
            c.durationBoostCount = 0
            c.speedBoostCount = 0
            c.tapStrengthBoostCount = 0
        }
        return c
    }

    /// Local display of banked charges + regen countdown from the server anchor.
    private func projectAdCharges(_ s: GameState, now: Date) -> (Int, Int) {
        let maxCharges = tunables?.adsPerCycle ?? max(s.adsRemainingToday, 1)
        let regenSec = tunables?.adRegenSeconds ?? 0
        var charges = s.adsRemainingToday
        var regenLeft = s.adRegenSecondsLeft ?? 0

        guard regenSec > 0, charges < maxCharges else {
            return (min(charges, maxCharges), 0)
        }

        if let next = parseIso8601(s.nextAdChargeAt ?? "") {
            if now >= next {
                let gained = 1 + Int(floor(now.timeIntervalSince(next) / Double(regenSec)))
                charges = min(maxCharges, s.adsRemainingToday + gained)
                if charges >= maxCharges {
                    regenLeft = 0
                } else {
                    let into = now.timeIntervalSince(next).truncatingRemainder(dividingBy: Double(regenSec))
                    regenLeft = max(0, Int(ceil(Double(regenSec) - into)))
                }
            } else {
                regenLeft = max(0, Int(ceil(next.timeIntervalSince(now))))
            }
        } else if regenLeft > 0 {
            let elapsed = max(0, now.timeIntervalSince(anchorDate))
            let left = Int(ceil(Double(regenLeft) - elapsed))
            if left <= 0 {
                let overdue = -left
                let gained = 1 + overdue / regenSec
                charges = min(maxCharges, s.adsRemainingToday + gained)
                regenLeft = charges >= maxCharges ? 0 : regenSec - (overdue % regenSec)
            } else {
                regenLeft = left
            }
        }
        return (charges, regenLeft)
    }
}

private func iso8601String(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}
