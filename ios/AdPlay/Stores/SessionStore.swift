import Foundation
import Combine
import os

@MainActor
final class SessionStore: ObservableObject {
    @Published var state: GameState = .empty
    @Published var tunables: Tunables?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isReady = false
    @Published var bypassAds: Bool = DebugAdBypass.isEnabled
    @Published var progress: PlayerProgress = .empty
    private var adsWatchedToday = 0
    /// True while a rewarded ad is on screen — skip lifecycle refresh so the watch is not dropped.
    @Published private(set) var watchingAd = false

    let api = APIClient()
    private var adService: AdServing?
    private var tickTask: Task<Void, Never>?
    private var lastUpdatedAt: String?

    /// Last authoritative snapshot and when it arrived. While an auto window runs we
    /// project the display from this anchor locally, so Firebase is only hit on real
    /// changes (start, foreground, a mutation, or once when a window ends).
    private var serverState: GameState = .empty
    /// Last fully-acked server snapshot (excludes optimistic taps still in flight).
    private var confirmedState: GameState = .empty
    /// Manual taps shown locally but not yet confirmed by `gameTap`.
    private var unackedTaps = 0
    private var tapFlushTask: Task<Void, Never>?
    private var tapFlushGeneration = 0
    /// True while `tapFlushTask` is sending `gameTap`s (avoids refresh awaiting itself).
    private var flushingTaps = false
    private var anchorDate: Date = .now
    private var windowEndHandled = false
    private var foreground = false
    /// True while Skip Time is animating display toward the new server snapshot.
    private var skipAnimating = false
    private var skipLerpTask: Task<Void, Never>?
    private static let skipLerpSeconds: TimeInterval = 3

    private static let log = Logger(subsystem: "com.adplay.app", category: "session")

    /// Debug builds only (`DEBUG_BYPASS_ADS`). Never available in Release / TestFlight.
    var bypassAdsAvailable: Bool {
        DebugAdBypass.available
    }

    /// True while an ad is showing or a boost credit is applying.
    var isBusy: Bool { isLoading || watchingAd }

    func start() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await refresh(force: true)
            adService = AdServiceFactory.make(api: api, provider: tunables?.adProvider ?? "waterfall")
            isReady = true
            foreground = true
            ensureTicker()
            GameCenterService.start()
            publishPlayPresence()
            Self.log.notice("AdPlay session ready")
            GameReminderScheduler.requestPermissionIfNeeded()
            // Warm AdMob after home is up so the ATT prompt is not under the splash.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard self.foreground, self.isReady else { return }
                self.configureAdMobUnit()
            }
        } catch {
            isReady = false
            errorMessage = error.localizedDescription
            Self.log.error("AdPlay session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// App came to the foreground: re-sync once, then animate locally.
    func onForeground() {
        foreground = true
        GameReminderScheduler.clearBadge()
        guard isReady else { return }
        // A full-screen ad returning to Play must not refresh mid-credit.
        guard !watchingAd else { return }
        configureAdMobUnit()
        Task { try? await refresh(force: true) }
        ensureTicker()
    }

    /// App backgrounded: stop the local animation loop.
    func onBackground() {
        if watchingAd { return }
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
        publishPlayPresence()
    }

    func refresh(force: Bool = false) async throws {
        // Daily Goals (and other getState pulls) must not race in-flight taps.
        // Opening that tab used to drop unacked taps, so the bar filled then snapped back.
        await drainPendingTaps()
        let (s, t, p) = try await api.fetchState()
        tunables = t
        if let provider = t?.adProvider {
            adService = AdServiceFactory.make(api: api, provider: provider)
        }
        configureAdMobUnit()
        setServerState(s, force: force, discardOptimisticTaps: false)
        applyProgress(p)
    }

    func buyAdSlot(transactionId: String) async throws {
        let (s, p) = try await api.buyAdSlot(transactionId: transactionId)
        apply(s, force: true)
        applyProgress(p)
    }

    func restoreAdSlots(transactionIds: [String]) async throws -> Int {
        let before = progress.iapAdsPurchased
        for id in transactionIds {
            try await buyAdSlot(transactionId: id)
        }
        return max(0, progress.iapAdsPurchased - before)
    }

    /// Sample creatives in Debug only. Release / TestFlight always use production units.
    /// Skipped until `isReady` so ATT is not shown under the splash.
    private func configureAdMobUnit() {
        guard isReady else { return }
        #if DEBUG
        let useSample = true
        #else
        let useSample = false
        #endif
        AdMobRewardedPresenter.shared.configure(useSampleAds: useSample)
    }

    /// Instant local feedback; Firebase catch-up is serialized in the background.
    func tap() async {
        guard !skipAnimating else { return }
        var probe = confirmedState
        for _ in 0..<unackedTaps {
            probe = probe.applyingManualTap(tunables: tunables)
        }
        guard probe.tapsRemaining > 0 else { return }

        unackedTaps += 1
        publishOptimisticTaps()
        ensureTapFlush()
    }

    /// Recompute display from confirmed server state + unacked optimistic taps.
    private func publishOptimisticTaps() {
        var s = confirmedState
        for _ in 0..<unackedTaps {
            s = s.applyingManualTap(tunables: tunables)
        }
        // Keep the auto-fill clock; only progress / taps change.
        serverState = s
        state = project(s, now: Date())
        replaceProgress(progress.syncedWith(state: state, tunables: tunables, adsWatched: adsWatchedToday))
        publishPlayPresence()
    }

    /// Finish uploading optimistic taps so the next getState includes them.
    private func drainPendingTaps() async {
        guard !flushingTaps else { return }
        await tapFlushTask?.value
    }

    private func ensureTapFlush() {
        guard tapFlushTask == nil else { return }
        let generation = tapFlushGeneration
        tapFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.flushingTaps = true
            defer {
                self.flushingTaps = false
                self.tapFlushTask = nil
            }
            while self.unackedTaps > 0 {
                guard generation == self.tapFlushGeneration else { return }
                do {
                    let (next, p) = try await self.api.tap()
                    guard generation == self.tapFlushGeneration else { return }
                    if let u = next.updatedAt {
                        self.lastUpdatedAt = u
                    }
                    let afterTap = self.confirmedState.applyingManualTap(tunables: self.tunables)
                    // Combo ring + live-tap units (Stronger × combo) must survive gameTap
                    // ACKs. Keep optimistic tap math; do not reset the auto-fill clock.
                    self.confirmedState = next.takingLiveTapUnits(from: afterTap)
                    self.unackedTaps = max(0, self.unackedTaps - 1)
                    self.windowEndHandled = false
                    self.publishOptimisticTaps()
                    self.applyProgress(p)
                    GameReminderScheduler.sync(self.state)
                    self.ensureTicker()
                } catch {
                    guard generation == self.tapFlushGeneration else { return }
                    self.unackedTaps = 0
                    try? await self.refresh(force: true)
                    return
                }
            }
        }
    }

    func watch(boost: BoostType) async {
        guard !watchingAd else { return }
        watchingAd = true
        defer { watchingAd = false }
        errorMessage = nil
        do {
            guard let adService else {
                throw APIError.message("Ad service not ready")
            }
            // Ensure ATT ran even if preload had not finished yet.
            await AppTracking.requestIfNeeded()
            let from = state
            let credit = try await adService.showBoostAd(type: boost)
            isLoading = true
            let to = credit.state
            adsWatchedToday += 1
            if boost == .skipTime {
                await playSkipLerp(from: from, to: to)
            } else {
                apply(to, force: true)
            }
            applyProgress(credit.progress)
            isLoading = false
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
        tapFlushGeneration += 1
        unackedTaps = 0
        confirmedState = to
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
        let fromSkip = from.effectiveSkipAdsRemaining
        let toSkip = to.effectiveSkipAdsRemaining
        let fromSkipRegen = Double(from.skipAdRegenSecondsLeft ?? 0)
        let toSkipRegen = Double(to.skipAdRegenSecondsLeft ?? 0)

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

                if fromSkip >= 0 && toSkip >= 0 {
                    d.skipAdsRemaining = e < 0.85 ? fromSkip : toSkip
                } else {
                    d.skipAdsRemaining = toSkip
                }
                let skipRegenLeft = max(0, fromSkipRegen + (toSkipRegen - fromSkipRegen) * e)
                d.skipAdRegenSecondsLeft = Int(skipRegenLeft.rounded())
                if skipRegenLeft > 0.5 {
                    d.nextSkipAdChargeAt = iso8601String(Date().addingTimeInterval(skipRegenLeft))
                } else {
                    d.nextSkipAdChargeAt = to.nextSkipAdChargeAt
                }

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
        guard tunables?.debugReset == true else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let (s, p) = try await api.debugReset()
            adsWatchedToday = 0
            apply(s, force: true, keepCombo: false)
            applyProgress(p)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ next: GameState, force: Bool, keepCombo: Bool = true) {
        setServerState(next, force: force, keepCombo: keepCombo)
    }

    private func applyProgress(_ server: PlayerProgress?) {
        if let server, let ads = server.dailyGoals.first(where: { $0.id == "ads" }) {
            adsWatchedToday = ads.current
        }
        let incoming = progress.takingServer(server)
        // Server remaining already includes tokens for this hold. Only grant slots
        // that local goal completion added on top (optimistic taps / this session).
        let grantAbove = server != nil ? incoming.adBank.max : progress.adBank.max
        replaceProgress(
            incoming.syncedWith(state: state, tunables: tunables, adsWatched: adsWatchedToday),
            grantAbove: grantAbove
        )
        GameCenterService.report(progress: progress)
        publishPlayPresence()
    }

    private func replaceProgress(_ next: PlayerProgress, grantAbove: Int? = nil) {
        let floor = grantAbove ?? progress.adBank.max
        let oldRemaining = state.adsRemainingToday
        progress = next
        let gained = max(0, next.adBank.max - floor)
        if gained > 0, state.adsRemainingToday <= oldRemaining {
            grantCharges(gained, cap: next.adBank.max)
        }
    }

    private func grantCharges(_ gained: Int, cap: Int) {
        func bump(_ s: GameState) -> GameState {
            var c = s
            c.adsRemainingToday = min(cap, max(0, c.adsRemainingToday + gained))
            if c.adsRemainingToday >= cap {
                c.adRegenSecondsLeft = 0
                c.nextAdChargeAt = nil
            }
            return c
        }
        state = bump(state)
        serverState = bump(serverState)
        confirmedState = bump(confirmedState)
    }

    /// Adopt an authoritative server snapshot. It always overrides locally projected
    /// values, so a tampered client can never keep fake progress or balance.
    ///
    /// `discardOptimisticTaps` is true for mutations that already include those taps
    /// (boost, reset, redeem). getState refresh keeps taps that landed during the fetch.
    private func setServerState(
        _ next: GameState,
        force: Bool,
        discardOptimisticTaps: Bool = true,
        keepCombo: Bool = true
    ) {
        if !force, let incoming = next.updatedAt, let last = lastUpdatedAt, incoming < last {
            return
        }
        if let u = next.updatedAt {
            lastUpdatedAt = u
        }
        var adopted = next
        let preserveLiveTaps = keepCombo && comboRecentlyTapped(state)
            if preserveLiveTaps {
                if discardOptimisticTaps {
                    adopted.comboMeter = state.comboMeter
                    adopted.comboLevel = state.comboLevel
                    adopted.comboContrib = state.comboContrib
                    adopted.comboMeter1 = state.comboMeter1
                    adopted.comboLevel1 = state.comboLevel1
                    adopted.comboContrib1 = state.comboContrib1
                    adopted.comboMeter2 = state.comboMeter2
                    adopted.comboLevel2 = state.comboLevel2
                    adopted.comboContrib2 = state.comboContrib2
                    adopted.lastManualTapAt = state.lastManualTapAt
                    adopted.comboMultiplier = state.comboMultiplier
                } else {
                    adopted = next.takingLiveTapUnits(from: confirmedState)
                }
            }
        if discardOptimisticTaps {
            // Invalidate any in-flight optimistic tap flush; those responses are stale
            // relative to this authoritative snapshot (boost / reset / redeem).
            tapFlushGeneration += 1
            unackedTaps = 0
            confirmedState = adopted
            serverState = adopted
            anchorDate = Date()
            windowEndHandled = false
            state = project(adopted, now: anchorDate)
        } else {
            confirmedState = adopted
            if !preserveLiveTaps {
                anchorDate = Date()
            }
            windowEndHandled = false
            publishOptimisticTaps()
        }
        GameReminderScheduler.sync(state)
        publishPlayPresence()
        ensureTicker()
    }

    private func comboRecentlyTapped(_ s: GameState) -> Bool {
        guard let last = parseIso8601(s.lastManualTapAt ?? "") else { return false }
        return Date().timeIntervalSince(last) < 15
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
                let adsMax = self.adsHoldMax(for: self.state)
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
        // When the shared auto window just ended, show a full ad bank until refresh lands.
        let windowExpired = s.autoFillActive && !autoActive
        let maxCharges = adsHoldMax(for: s)
        let adsLeft: Int
        let regenLeft: Int
        if windowExpired {
            adsLeft = maxCharges
            regenLeft = 0
        } else {
            (adsLeft, regenLeft) = projectChargeBank(
                charges: s.adsRemainingToday,
                regenLeft: s.adRegenSecondsLeft ?? 0,
                nextAt: s.nextAdChargeAt,
                maxCharges: maxCharges,
                now: now
            )
        }
        let skipMax = tunables?.skipAdsPerCycle
        let skipLeft: Int
        let skipRegenLeft: Int
        if let skipMax, skipMax < 0 {
            // Disabled
            skipLeft = 0
            skipRegenLeft = 0
        } else if windowExpired {
            skipLeft = skipMax == 0 ? -1 : (skipMax ?? s.effectiveSkipAdsRemaining)
            skipRegenLeft = 0
        } else if skipMax == 0 {
            skipLeft = -1
            skipRegenLeft = 0
        } else {
            let maxSkip = skipMax ?? max(s.effectiveSkipAdsRemaining, 0)
            if maxSkip <= 0 {
                skipLeft = s.effectiveSkipAdsRemaining
                skipRegenLeft = 0
            } else {
                (skipLeft, skipRegenLeft) = projectChargeBank(
                    charges: s.effectiveSkipAdsRemaining,
                    regenLeft: s.skipAdRegenSecondsLeft ?? 0,
                    nextAt: s.nextSkipAdChargeAt,
                    maxCharges: maxSkip,
                    now: now
                )
            }
        }

        guard s.autoFillActive, s.fillRate > 0, s.unitsPerSat > 0, let until else {
            var c = s
            c.adCooldownSecondsLeft = cooldown
            c.autoFillActive = autoActive
            c.adsRemainingToday = adsLeft
            c.adRegenSecondsLeft = regenLeft
            c.nextAdChargeAt = windowExpired ? nil : s.nextAdChargeAt
            c.skipAdsRemaining = skipLeft
            c.skipAdRegenSecondsLeft = skipRegenLeft
            c.nextSkipAdChargeAt = windowExpired || skipLeft < 0 ? nil : s.nextSkipAdChargeAt
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
        c.nextAdChargeAt = windowExpired ? nil : s.nextAdChargeAt
        c.skipAdsRemaining = skipLeft
        c.skipAdRegenSecondsLeft = skipRegenLeft
        c.nextSkipAdChargeAt = windowExpired || skipLeft < 0 ? nil : s.nextSkipAdChargeAt
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

    /// Hold size for regen / display. Never below the server remaining we just loaded,
    /// so a stale default bank of 5 cannot recap a full 13-token hold.
    private func adsHoldMax(for s: GameState) -> Int {
        max(progress.adBank.max, tunables?.adsPerCycle ?? 0, s.adsRemainingToday, 1)
    }

    /// Local display of banked charges + regen countdown from the server anchor.
    private func projectChargeBank(
        charges initialCharges: Int,
        regenLeft initialRegen: Int,
        nextAt: String?,
        maxCharges: Int,
        now: Date
    ) -> (Int, Int) {
        let regenSec = tunables?.adRegenSeconds ?? 0
        var charges = initialCharges
        var regenLeft = initialRegen

        guard regenSec > 0, charges < maxCharges else {
            return (min(charges, maxCharges), 0)
        }

        if let next = parseIso8601(nextAt ?? "") {
            if now >= next {
                let gained = 1 + Int(floor(now.timeIntervalSince(next) / Double(regenSec)))
                charges = min(maxCharges, initialCharges + gained)
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
                charges = min(maxCharges, initialCharges + gained)
                regenLeft = charges >= maxCharges ? 0 : regenSec - (overdue % regenSec)
            } else {
                regenLeft = left
            }
        }
        return (charges, regenLeft)
    }

    private func publishPlayPresence() {
        let comboT = ComboTunables.from(tunables)
        let live = ComboEngine.at(state.combo, now: Date(), tunables: comboT)
        let mult = comboT.multiplier(of: live)
        let stage = MinerStage.from(lifetimeSats: progress.lifetimeSats)
        PlaySnapshot.write(
            .init(
                satsBalance: state.satsBalance,
                progress: state.progress,
                unitsPerSat: max(1, state.unitsPerSat),
                autoFillUntil: parseIso8601(state.autoFillUntil ?? ""),
                comboMultiplier: mult,
                stageTitle: stage.title,
                updatedAt: Date()
            )
        )
        AutoTapperLiveActivity.sync(state: state, progress: progress, comboMultiplier: mult)
    }
}
