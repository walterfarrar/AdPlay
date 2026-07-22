import Foundation
import FirebaseAuth
import FirebaseFunctions

enum APIError: LocalizedError {
    case message(String)
    case decode

    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .decode: return "Bad server response"
        }
    }
}

final class APIClient {
    private let functions = Functions.functions(region: "us-central1")

    func ensureSignedIn() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
    }

    func fetchState() async throws -> (GameState, Tunables?) {
        try await ensureSignedIn()
        let data = try await call("getState")
        let envelope: StateEnvelope = try decode(data)
        return (envelope.state, envelope.tunables)
    }

    func tap() async throws -> GameState {
        try await ensureSignedIn()
        let data = try await call("gameTap")
        let envelope: StateOnly = try decode(data)
        return envelope.state
    }

    func mockComplete(boostType: BoostType) async throws -> GameState {
        try await ensureSignedIn()
        let data = try await call(
            "mockCompleteBoost",
            data: ["boostType": boostType.rawValue],
        )
        let envelope: StateOnly = try decode(data)
        return envelope.state
    }

    func requestWithdrawal(amountSats: Int, bolt11: String) async throws -> GameState {
        try await ensureSignedIn()
        let data = try await call(
            "requestWithdrawal",
            data: [
                "amountSats": amountSats,
                "bolt11": bolt11,
            ],
        )
        let envelope: StateOnly = try decode(data)
        return envelope.state
    }

    func debugReset() async throws -> GameState {
        try await ensureSignedIn()
        let data = try await call("debugReset")
        let envelope: StateOnly = try decode(data)
        return envelope.state
    }

    func myWithdrawals() async throws -> [Withdrawal] {
        try await ensureSignedIn()
        let data = try await call("myWithdrawals")
        let envelope: WithdrawalsEnvelope = try decode(data)
        return envelope.withdrawals
    }

    private func call(_ name: String, data: [String: Any]? = nil) async throws -> Any {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            return result.data
        } catch {
            let ns = error as NSError
            let message =
                (ns.userInfo[NSLocalizedDescriptionKey] as? String)
                ?? ns.localizedDescription
            throw APIError.message(message)
        }
    }

    private func decode<T: Decodable>(_ data: Any) throws -> T {
        let json = try JSONSerialization.data(withJSONObject: data, options: [])
        return try JSONDecoder().decode(T.self, from: json)
    }
}

private struct StateEnvelope: Decodable {
    let state: GameState
    let tunables: Tunables?
}

private struct StateOnly: Decodable {
    let state: GameState
}

private struct WithdrawalsEnvelope: Decodable {
    let withdrawals: [Withdrawal]
}
