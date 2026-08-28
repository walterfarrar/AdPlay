import AuthenticationServices
import CryptoKit
import FirebaseAuth

enum AppleAccountError: LocalizedError {
    case canceled
    case noIdentityToken

    var errorDescription: String? {
        switch self {
        case .canceled: return nil
        case .noIdentityToken: return "Apple did not return a sign-in token."
        }
    }
}

enum AppleLinkOutcome: Equatable {
    case linked
    case restored
    case needsChoice
    case canceled
}

/// Sign in with Apple → Firebase credential. First launch stays anonymous.
@MainActor
final class AppleAccountCoordinator: NSObject {
    static let shared = AppleAccountCoordinator()

    private var rawNonce = ""

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        rawNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(nonce)
    }

    func firebaseCredential(from result: Result<ASAuthorization, Error>) throws -> AuthCredential {
        switch result {
        case .failure(let error):
            throw Self.mapAppleError(error)
        case .success(let authorization):
            return try firebaseCredential(from: authorization)
        }
    }

    func firebaseCredential(from authorization: ASAuthorization) throws -> AuthCredential {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAccountError.noIdentityToken
        }
        return try firebaseCredential(from: apple)
    }

    func firebaseCredential(from apple: ASAuthorizationAppleIDCredential) throws -> AuthCredential {
        guard let tokenData = apple.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AppleAccountError.noIdentityToken
        }
        return OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: apple.fullName
        )
    }

    static func authErrorMessage(_ error: Error) -> String {
        if let apple = error as? AppleAccountError {
            return apple.errorDescription ?? "Apple sign-in was canceled."
        }
        let ns = error as NSError
        if ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .operationNotAllowed:
                return "Apple sign-in is not enabled on the Firebase project."
            case .invalidCredential:
                return "Apple’s token was rejected (Firebase \(ns.code))."
            case .networkError:
                return "Network error while saving progress with Apple."
            case .userDisabled:
                return "That Apple-linked account is disabled."
            default:
                return "\(ns.localizedDescription) (Firebase \(ns.code))"
            }
        }
        if ns.domain == ASAuthorizationError.errorDomain {
            if ns.code == ASAuthorizationError.unknown.rawValue {
                return "Apple rejected sign-in (code 1000). Enable Sign in with Apple on App ID com.adplay.app (Identifiers, not only App Store Connect), refresh the Codemagic profile, and install that new TestFlight."
            }
            return "Apple sign-in failed (code \(ns.code))."
        }
        return ns.localizedDescription
    }

    static func mapAppleError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.canceled.rawValue {
            return AppleAccountError.canceled
        }
        return error
    }

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if status != errSecSuccess {
            randomBytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
