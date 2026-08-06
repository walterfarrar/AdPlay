import Foundation
import GoogleMobileAds
import UIKit

enum AdMobConfig {
    static let appId = "ca-app-pub-1524015618608684~3874360461"
    /// Google sample rewarded unit — Debug builds only.
    static let sampleRewardedUnitId = "ca-app-pub-3940256099942544/1712485313"
    static let productionRewardedUnitId = "ca-app-pub-1524015618608684/6403169508"

    /// When true, load Google's sample creatives. Release / TestFlight always use
    /// the production unit — sample ads are Debug-only.
    static var useSampleAds: Bool = false

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
            // ATT before Mobile Ads init so personalized / tracking-capable ads match ASC labels.
            await AppTracking.requestIfNeeded()
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
            #if DEBUG
            print("AdPlayAds: AdMob load failed unit=\(unit)")
            #endif
            finish(.unavailable)
            return
        }
        guard let root = Self.topViewController() else {
            #if DEBUG
            print("AdPlayAds: AdMob present failed — no root VC")
            #endif
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
            #if DEBUG
            print("AdPlayAds: AdMob loaded unit=\(unitId)")
            #endif
            return ad
        } catch {
            #if DEBUG
            print("AdPlayAds: AdMob load error unit=\(unitId) err=\(error.localizedDescription)")
            #endif
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
        #if DEBUG
        print("AdPlayAds: AdMob present error \(error.localizedDescription)")
        #endif
        finish(.unavailable)
    }
}
