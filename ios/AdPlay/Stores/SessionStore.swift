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
    private var lastUpdatedAt: String?

    func start() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await refresh(force: true)
            adService = AdServiceFactory.make(api: api, provider: tunables?.adProvider ?? "adsbitvex")
            isReady = true
            startPolling()
        } catch {
            isReady = false
            errorMessage = error.localizedDescription
        }
    }

    func refresh(force: Bool = false) async throws {
        let (s, t) = try await api.fetchState()
        if !force, let incoming = s.updatedAt, let last = lastUpdatedAt, incoming < last {
            return
        }
        if let u = s.updatedAt {
            lastUpdatedAt = u
        }
        state = s
        tunables = t
        if let provider = t?.adProvider {
            adService = AdServiceFactory.make(api: api, provider: provider)
        }
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
        if !force, let incoming = next.updatedAt, let last = lastUpdatedAt, incoming < last {
            return
        }
        if let u = next.updatedAt {
            lastUpdatedAt = u
        }
        state = next
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
}
