import Foundation

enum APIError: LocalizedError {
    case message(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .http(let code, let s): return "\(code): \(s)"
        }
    }
}

final class APIClient {
    /// Change for device/simulator: simulator can use localhost; device needs your Mac LAN IP.
    static var baseURL = URL(string: ProcessInfo.processInfo.environment["ADPLAY_API_URL"] ?? "http://127.0.0.1:8787")!

    private var token: String?

    func setToken(_ token: String?) {
        self.token = token
    }

    func createSession(deviceId: String) async throws -> (token: String, userId: String) {
        struct Body: Encodable { let deviceId: String }
        struct Res: Decodable { let token: String; let userId: String }
        let res: Res = try await post("/auth/session", body: Body(deviceId: deviceId), auth: false)
        return (res.token, res.userId)
    }

    func createSession(appleSub: String, displayName: String?) async throws -> (token: String, userId: String) {
        struct Body: Encodable {
            let appleSub: String
            let displayName: String?
        }
        struct Res: Decodable { let token: String; let userId: String }
        let res: Res = try await post("/auth/session", body: Body(appleSub: appleSub, displayName: displayName), auth: false)
        return (res.token, res.userId)
    }

    func fetchState() async throws -> (GameState, Tunables?) {
        struct Res: Decodable {
            let state: GameState
            let tunables: Tunables?
        }
        let res: Res = try await get("/game/state")
        return (res.state, res.tunables)
    }

    func tap() async throws -> GameState {
        struct Res: Decodable { let state: GameState }
        let res: Res = try await post("/game/tap", body: Empty())
        return res.state
    }

    func mockComplete(boostType: BoostType) async throws -> GameState {
        struct Body: Encodable { let boostType: String }
        struct Res: Decodable { let state: GameState }
        let res: Res = try await post("/ads/mock/complete", body: Body(boostType: boostType.rawValue))
        return res.state
    }

    func requestWithdrawal(amountSats: Int, bolt11: String) async throws -> GameState {
        struct Body: Encodable {
            let amountSats: Int
            let bolt11: String
        }
        struct Res: Decodable { let state: GameState }
        let res: Res = try await post("/withdrawals", body: Body(amountSats: amountSats, bolt11: bolt11))
        return res.state
    }

    func debugReset() async throws -> GameState {
        struct Res: Decodable { let state: GameState }
        let res: Res = try await post("/game/debug/reset", body: Empty())
        return res.state
    }

    func myWithdrawals() async throws -> [Withdrawal] {
        struct Res: Decodable { let withdrawals: [Withdrawal] }
        let res: Res = try await get("/withdrawals/mine")
        return res.withdrawals
    }

    private struct Empty: Encodable {}

    private func url(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return APIClient.baseURL.appendingPathComponent(trimmed)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        applyAuth(&req)
        return try await send(req)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, auth: Bool = true) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        if auth { applyAuth(&req) }
        return try await send(req)
    }

    private func applyAuth(_ req: inout URLRequest) {
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw APIError.http(code, err)
            }
            throw APIError.http(code, String(data: data, encoding: .utf8) ?? "Error")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
