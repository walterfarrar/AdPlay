import Foundation
import GoogleMobileAds
import UIKit

enum AdMobConfig {
    static let appId = "ca-app-pub-1524015618608684~3874360461"
    /// Google sample rewarded unit — safe for Debug / TestFlight while debugReset is on.
    static let sampleRewardedUnitId = "ca-app-pub-3940256099942544/1712485313"
    static let productionRewardedUnitId = "ca-app-pub-1524015618608684/6403169508"

    /// When true (DEBUG, or server `debugReset`), load Google's sample creatives.
    /// Codemagic/TestFlight is Release, so we cannot rely on `#if DEBUG` alone.
    static var useSampleAds: Bool = true

    static var rewardedUnitId: String {
        useSampleAds ? sampleRewardedUnitId : productionRewardedUnitId
    }
}

/// Ensures MobileAds.start finished before any load/present (avoids silent no-fills).
enum AdMobBootstrap {
    private static var started = false
    private static var startTask: Task<Void, Never>?

    @MainActor
    static func ensureStarted() async {
        if started { return }
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in
                    cont.resume()
                }
            }
            started = true
        }
        startTask = task
        await task.value
    }
}

enum AdFillResult {
    /// User watched and earned the reward.
    case earned
    /// No inventory / load or present failed — safe to try the next network.
    case unavailable
    /// Ad was shown; user closed without earning — do not fall through.
    case declined
}

/// Preloads one AdMob rewarded ad and presents it on demand.
@MainActor
final class AdMobRewardedPresenter: NSObject, FullScreenContentDelegate {
    static let shared = AdMobRewardedPresenter()

    private var continuation: CheckedContinuation<AdFillResult, Never>?
    private var rewardedAd: RewardedAd?
    private var earned = false
    private var didPresent = false
    private var isLoading = false
    private var isShowing = false
    /// Continuations waiting on an in-flight preload (present called while loading).
    private var loadWaiters: [CheckedContinuation<RewardedAd?, Never>] = []
    private var loadedUnitId: String?

    /// Apply sample vs production unit (from tunables / DEBUG). Reloads if the unit changed.
    func configure(useSampleAds: Bool) {
        let changed = AdMobConfig.useSampleAds != useSampleAds
        AdMobConfig.useSampleAds = useSampleAds
        if changed {
            rewardedAd = nil
            loadedUnitId = nil
        }
        preload()
    }

    /// Warm a rewarded ad in the background. Safe to call often.
    func preload() {
        guard !isLoading, !isShowing else { return }
        if rewardedAd != nil, loadedUnitId == AdMobConfig.rewardedUnitId { return }
        rewardedAd = nil
        isLoading = true
        let unit = AdMobConfig.rewardedUnitId
        Task {
            await AdMobBootstrap.ensureStarted()
            let ad = await Self.loadAd(unitId: unit)
            isLoading = false
            if let ad, rewardedAd == nil, !isShowing {
                ad.fullScreenContentDelegate = self
                rewardedAd = ad
                loadedUnitId = unit
            }
            let waiters = loadWaiters
            loadWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: ad)
            }
        }
    }

    func present() async -> AdFillResult {
        await withCheckedContinuation { cont in
            self.continuation?.resume(returning: .unavailable)
            self.continuation = cont
            self.earned = false
            self.didPresent = false
            Task { await self.showReadyOrLoad() }
        }
    }

    private func showReadyOrLoad() async {
        isShowing = true
        await AdMobBootstrap.ensureStarted()

        let unit = AdMobConfig.rewardedUnitId
        var ad = rewardedAd
        if loadedUnitId != unit {
            ad = nil
            rewardedAd = nil
        }
        rewardedAd = nil
        loadedUnitId = nil

        if ad == nil {
            if isLoading {
                ad = await withCheckedContinuation { cont in
                    loadWaiters.append(cont)
                }
            } else {
                isLoading = true
                ad = await Self.loadAd(unitId: unit)
                isLoading = false
                let waiters = loadWaiters
                loadWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume(returning: ad)
                }
            }
        }

        guard let ad else {
            print("AdPlayAds: AdMob load failed unit=\(unit)")
            finish(.unavailable)
            return
        }
        guard let root = Self.topViewController() else {
            print("AdPlayAds: AdMob present failed — no root VC")
            finish(.unavailable)
            return
        }
        ad.fullScreenContentDelegate = self
        ad.present(from: root) { [weak self] in
            self?.earned = true
        }
    }

    private func finish(_ result: AdFillResult) {
        guard let cont = continuation else {
            isShowing = false
            preload()
            return
        }
        continuation = nil
        isShowing = false
        cont.resume(returning: result)
        preload()
    }

    private static func loadAd(unitId: String) async -> RewardedAd? {
        do {
            let ad = try await RewardedAd.load(
                with: unitId,
                request: Request(),
            )
            print("AdPlayAds: AdMob loaded unit=\(unitId)")
            return ad
        } catch {
            print("AdPlayAds: AdMob load error unit=\(unitId) err=\(error.localizedDescription)")
            return nil
        }
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: FullScreenContentDelegate

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        didPresent = true
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if earned {
            finish(.earned)
        } else if didPresent {
            finish(.declined)
        } else {
            finish(.unavailable)
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error,
    ) {
        print("AdPlayAds: AdMob present error \(error.localizedDescription)")
        finish(.unavailable)
    }
}
