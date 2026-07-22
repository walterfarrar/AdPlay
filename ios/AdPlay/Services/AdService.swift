import Foundation

/// Ad partner abstraction.
/// Production: replace mock path with partner SDK show → rely on S2S for boosts.
/// Dev (`AD_PROVIDER=mock`): call `/ads/mock/complete` after a short simulated watch.
protocol AdServing {
    func showBoostAd(type: BoostType) async throws -> GameState
}

final class MockAdService: AdServing {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func showBoostAd(type: BoostType) async throws -> GameState {
        // Simulate rewarded video length
        try await Task.sleep(nanoseconds: 1_200_000_000)
        return try await api.mockComplete(boostType: type)
    }
}

/// Placeholder for BitLabs (or other) once written approval is obtained.
/// Wire SDK show; do NOT credit locally — wait for state refresh after S2S.
final class PartnerAdService: AdServing {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func showBoostAd(type: BoostType) async throws -> GameState {
        // TODO: Present partner rewarded unit for `type` placement id.
        // On client reward callback, poll `/game/state` until boost applied via S2S.
        throw APIError.message("Partner SDK not configured. Set AD_PROVIDER=mock or integrate partner SDK.")
    }
}

enum AdServiceFactory {
    static func make(api: APIClient, provider: String) -> AdServing {
        if provider == "mock" {
            return MockAdService(api: api)
        }
        return PartnerAdService(api: api)
    }
}
