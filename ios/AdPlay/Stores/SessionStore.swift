import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var state: GameState = .empty
    @Published var tunables: Tunables?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isReady = false

    let api = APIClient()
    private var adService: AdServing?
    private var pollTask: Task<Void, Never>?
    private let deviceKey = "adplay.deviceId"
    private let tokenKey = "adplay.token"

    func start() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let saved = UserDefaults.standard.string(forKey: tokenKey) {
                api.setToken(saved)
            } else {
                let deviceId = Self.deviceId(key: deviceKey)
                let session = try await api.createSession(deviceId: deviceId)
                api.setToken(session.token)
                UserDefaults.standard.set(session.token, forKey: tokenKey)
            }
            try await refresh()
            adService = AdServiceFactory.make(api: api, provider: tunables?.adProvider ?? "mock")
            isReady = true
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async throws {
        let (s, t) = try await api.fetchState()
        state = s
        tunables = t
        if let provider = t?.adProvider {
            adService = AdServiceFactory.make(api: api, provider: provider)
        }
    }

    func tap() async {
        guard state.tapsRemaining > 0 else { return }
        do {
            state = try await api.tap()
        } catch {
            // Out of taps / transient — stay quiet
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
            state = try await adService.showBoostAd(type: boost)
        } catch {
            errorMessage = error.localizedDescription
            try? await refresh()
        }
    }

    func withdraw(amountSats: Int, bolt11: String) async -> Bool {
        errorMessage = nil
        do {
            state = try await api.requestWithdrawal(amountSats: amountSats, bolt11: bolt11)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func debugReset() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            state = try await api.debugReset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let busy = state.autoFillActive || state.adCooldownSecondsLeft > 0
                let ns: UInt64 = busy ? 400_000_000 : 2_000_000_000
                try? await Task.sleep(nanoseconds: ns)
                try? await refresh()
            }
        }
    }

    private static func deviceId(key: String) -> String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
