import AuthenticationServices
import CryptoKit
import FirebaseAuth
import SwiftUI
import UIKit

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
///
/// The authorization controller is kept on this singleton. Settings observes
/// `SessionStore`, which publishes play state about once a second; a SwiftUI
/// `SignInWithAppleButton` rebuilt in that tree drops Apple’s controller and
/// Apple reports “Sign Up Not Completed” / 1000.
@MainActor
final class AppleAccountCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleAccountCoordinator()

    private var rawNonce = ""
    private var controller: ASAuthorizationController?
    private var completion: ((Result<ASAuthorization, Error>) -> Void)?
    private weak var presentationWindow: UIWindow?

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        rawNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func startSignIn(from window: UIWindow?, completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
        presentationWindow = window
        let request = ASAuthorizationAppleIDProvider().createRequest()
        configure(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        self.controller = nil
        let done = completion
        completion = nil
        done?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.controller = nil
        let done = completion
        completion = nil
        done?(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let presentationWindow, presentationWindow.windowScene != nil {
            return presentationWindow
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        if let key = windows.first(where: \.isKeyWindow) {
            return key
        }
        return windows.first(where: { !$0.isHidden }) ?? UIWindow()
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
                return "Apple sign-in failed. Try again."
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

/// System Apple button. The request itself is owned by `AppleAccountCoordinator`.
struct AppleSignInButton: UIViewRepresentable {
    var isEnabled: Bool = true
    var onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .white
        )
        button.cornerRadius = 8
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.onCompletion = onCompletion
        uiView.isUserInteractionEnabled = isEnabled
        uiView.alpha = isEnabled ? 1 : 0.5
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator {
        var onCompletion: (Result<ASAuthorization, Error>) -> Void

        init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        @objc func tapped(_ sender: UIView) {
            AppleAccountCoordinator.shared.startSignIn(from: sender.window, completion: onCompletion)
        }
    }
}
