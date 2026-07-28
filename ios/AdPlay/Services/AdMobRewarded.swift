import Foundation
import GoogleMobileAds
import UIKit

enum AdMobConfig {
    static let appId = "ca-app-pub-1524015618608684~3874360461"

    /// Sample unit in DEBUG to avoid invalid traffic on the live unit.
    static var rewardedUnitId: String {
        #if DEBUG
        "ca-app-pub-3940256099942544/1712485313"
        #else
        "ca-app-pub-1524015618608684/6403169508"
        #endif
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

    /// Warm a rewarded ad in the background. Safe to call often.
    func preload() {
        guard !isLoading, !isShowing, rewardedAd == nil else { return }
        isLoading = true
        Task {
            let ad = await Self.loadAd()
            isLoading = false
            if let ad, rewardedAd == nil, !isShowing {
                ad.fullScreenContentDelegate = self
                rewardedAd = ad
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

        var ad = rewardedAd
        rewardedAd = nil

        if ad == nil {
            if isLoading {
                ad = await withCheckedContinuation { cont in
                    loadWaiters.append(cont)
                }
            } else {
                isLoading = true
                ad = await Self.loadAd()
                isLoading = false
                let waiters = loadWaiters
                loadWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume(returning: ad)
                }
            }
        }

        guard let ad else {
            finish(.unavailable)
            return
        }
        guard let root = Self.topViewController() else {
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

    private static func loadAd() async -> RewardedAd? {
        do {
            return try await RewardedAd.load(
                with: AdMobConfig.rewardedUnitId,
                request: Request(),
            )
        } catch {
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
        finish(.unavailable)
    }
}
