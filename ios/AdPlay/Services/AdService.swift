import Foundation
import SwiftUI
import WebKit

struct AdCredit {
    var state: GameState
    var progress: PlayerProgress?
}

protocol AdServing {
    func showBoostAd(type: BoostType) async throws -> AdCredit
}

/// Low-level network that reports fill outcome without calling the game API.
protocol AdNetwork {
    func attempt() async -> AdFillResult
}

final class MockAdService: AdServing {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func showBoostAd(type: BoostType) async throws -> AdCredit {
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let (state, progress) = try await api.mockComplete(boostType: type)
        return AdCredit(state: state, progress: progress)
    }
}

final class AdMobNetwork: AdNetwork {
    func attempt() async -> AdFillResult {
        await AdMobRewardedPresenter.shared.present()
    }
}

final class AdsBitvexNetwork: AdNetwork {
    func attempt() async -> AdFillResult {
        let ok = await AdsBitvexPresenter.shared.present()
        return ok ? .earned : .unavailable
    }
}

/// Single network: attempt → credit on earn.
final class NetworkAdService: AdServing {
    private let api: APIClient
    private let network: AdNetwork

    init(api: APIClient, network: AdNetwork) {
        self.api = api
        self.network = network
    }

    func showBoostAd(type: BoostType) async throws -> AdCredit {
        if DebugAdBypass.available, DebugAdBypass.isEnabled {
            return try await MockAdService(api: api).showBoostAd(type: type)
        }
        switch await network.attempt() {
        case .earned:
            let (state, progress) = try await api.mockComplete(boostType: type)
            return AdCredit(state: state, progress: progress)
        case .declined, .unavailable:
            throw APIError.message("Ad not completed")
        }
    }
}

/// AdMob first, then AdsBitvex on no-fill only (not after a declined watch).
final class WaterfallAdService: AdServing {
    private let api: APIClient
    private let networks: [AdNetwork]

    init(api: APIClient, networks: [AdNetwork]) {
        self.api = api
        self.networks = networks
    }

    func showBoostAd(type: BoostType) async throws -> AdCredit {
        if DebugAdBypass.available, DebugAdBypass.isEnabled {
            return try await MockAdService(api: api).showBoostAd(type: type)
        }
        for network in networks {
            switch await network.attempt() {
            case .earned:
                let (state, progress) = try await api.mockComplete(boostType: type)
                return AdCredit(state: state, progress: progress)
            case .declined:
                throw APIError.message("Ad not completed")
            case .unavailable:
                continue
            }
        }
        throw APIError.message("Ad not completed")
    }
}

enum AdServiceFactory {
    static func make(api: APIClient, provider: String) -> AdServing {
        switch provider.lowercased() {
        case "mock":
            #if DEBUG
            return MockAdService(api: api)
            #else
            // Never ship the mock provider in Release — fall through to waterfall.
            return WaterfallAdService(
                api: api,
                networks: [AdMobNetwork(), AdsBitvexNetwork()],
            )
            #endif
        case "admob":
            return NetworkAdService(api: api, network: AdMobNetwork())
        case "adsbitvex_only":
            return NetworkAdService(api: api, network: AdsBitvexNetwork())
        // Older backends returned "adsbitvex"; treat as waterfall so AdMob is tried first.
        case "waterfall", "adsbitvex":
            return WaterfallAdService(
                api: api,
                networks: [AdMobNetwork(), AdsBitvexNetwork()],
            )
        default:
            return WaterfallAdService(
                api: api,
                networks: [AdMobNetwork(), AdsBitvexNetwork()],
            )
        }
    }
}

@MainActor
final class AdsBitvexPresenter: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = AdsBitvexPresenter()

    private var continuation: CheckedContinuation<Bool, Never>?
    private var host: UIViewController?

    func present() async -> Bool {
        await AppTracking.requestIfNeeded()
        return await withCheckedContinuation { cont in
            self.continuation?.resume(returning: false)
            self.continuation = cont
            presentWebAd()
        }
    }

    private func presentWebAd() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            finish(false)
            return
        }

        let presenter = root.presentedViewController ?? root
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = self
        web.configuration.userContentController.add(self, name: "AdPlayBridge")
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black

        let vc = UIViewController()
        vc.view.backgroundColor = .black
        web.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: vc.view.topAnchor),
            web.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
        ])
        vc.modalPresentationStyle = .fullScreen
        host = vc
        presenter.present(vc, animated: true)

        let html = Self.htmlPage(appId: "000241")
        web.loadHTMLString(html, baseURL: URL(string: "https://sdk.adsbitvex.com/"))
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
    ) {
        guard message.name == "AdPlayBridge" else { return }
        let body = message.body as? [String: Any]
        let status = body?["status"] as? String ?? ""
        finish(status == "ok")
    }

    private func finish(_ ok: Bool) {
        guard let cont = continuation else { return }
        continuation = nil
        if let host {
            host.dismiss(animated: true) {
                self.host = nil
                cont.resume(returning: ok)
            }
        } else {
            cont.resume(returning: ok)
        }
    }

    private static func htmlPage(appId: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
          <script src="https://sdk.adsbitvex.com/functions/v1/ad-script?appid=\(appId)"></script>
        </head>
        <body style="margin:0;background:#000;color:#ccc;font-family:sans-serif;
          display:flex;align-items:center;justify-content:center;height:100vh;text-align:center">
          <p id="status">Loading ad…</p>
          <script>
            function notify(ok, msg) {
              try {
                window.webkit.messageHandlers.AdPlayBridge.postMessage({
                  status: ok ? 'ok' : 'err',
                  message: msg || ''
                });
              } catch (e) {}
            }
            function run(tries) {
              if (typeof window.showadsbitvex === 'function') {
                document.getElementById('status').textContent = 'Watch to unlock boost…';
                window.showadsbitvex()
                  .then(function () { notify(true, ''); })
                  .catch(function (e) {
                    notify(false, (e && e.message) ? e.message : String(e));
                  });
                return;
              }
              if (tries > 50) {
                document.getElementById('status').textContent = 'Ad SDK failed to load';
                notify(false, 'SDK timeout');
                return;
              }
              setTimeout(function () { run(tries + 1); }, 200);
            }
            run(0);
          </script>
        </body>
        </html>
        """
    }
}
