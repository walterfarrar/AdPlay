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
        if Auth.auth().currentUser != nil { return }
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                _ = try await Auth.auth().signInAnonymously()
                return
            } catch {
                lastError = error
                let text = error.localizedDescription.lowercased()
                guard text.contains("keychain"), attempt < 4 else { throw error }
                let delay = UInt64((attempt + 1) * 400_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError!
    }

    func fetchState() async throws -> (GameState, Tunables?, PlayerProgress?) {
        try await ensureSignedIn()
        let data = try await call("getState")
        let envelope: StateEnvelope = try decode(data)
        return (envelope.state, envelope.tunables, envelope.progress)
    }

    func tap() async throws -> (GameState, PlayerProgress?) {
        try await ensureSignedIn()
        let data = try await call("gameTap")
        let envelope: StateOnly = try decode(data)
        return (envelope.state, envelope.progress)
    }

    func mockComplete(boostType: BoostType) async throws -> (GameState, PlayerProgress?) {
        try await ensureSignedIn()
        let data = try await call(
            "mockCompleteBoost",
            data: ["boostType": boostType.rawValue],
        )
        let envelope: StateOnly = try decode(data)
        return (envelope.state, envelope.progress)
    }

    func buyAdSlot(transactionId: String) async throws -> (GameState, PlayerProgress?) {
        try await ensureSignedIn()
        let data = try await call(
            "buyAdSlot",
            data: ["transactionId": transactionId],
        )
        let envelope: StateOnly = try decode(data)
        return (envelope.state, envelope.progress)
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

    func debugReset() async throws -> (GameState, PlayerProgress?) {
        try await ensureSignedIn()
        let data = try await call("debugReset")
        let envelope: StateOnly = try decode(data)
        return (envelope.state, envelope.progress)
    }

    func deleteAccount() async throws {
        try await ensureSignedIn()
        _ = try await call("deleteAccount")
        try Auth.auth().signOut()
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
    let progress: PlayerProgress?
}

private struct StateOnly: Decodable {
    let state: GameState
    let progress: PlayerProgress?
}

private struct WithdrawalsEnvelope: Decodable {
    let withdrawals: [Withdrawal]
}
