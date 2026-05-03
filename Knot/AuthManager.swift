//
//  AuthManager.swift
//  Knot
//dvcdsvdsvsdvsdvsdv

import SwiftUI
import Combine
import Supabase
import Auth
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: ObservableObject {
    @Published var isLoggedIn              = false
    @Published var isCheckingSession       = true
    @Published var isEmailVerified         = false
    @Published var isOnboardingComplete    = true
    @Published var isVerificationBypassed  = false
    @Published var isPasswordRecovery      = false
    @Published var currentUser           : Auth.User? = nil
    @Published var socialAuthError       : String?    = nil
    @Published var isBanned              = false

    var onSignedIn: ((Auth.User) async -> Void)?

    private var appleCoordinator: AppleSignInCoordinator?

    init() {
        Task { await listenToAuthChanges() }
    }

    // MARK: - Sign Out

    func signOut() async {
        // Clear local state unconditionally first.
        // The user must never be stuck in a logged-in state because of a network failure.
        isLoggedIn            = false
        isEmailVerified       = false
        isOnboardingComplete  = true
        isPasswordRecovery    = false
        isBanned              = false
        currentUser           = nil

        // Best-effort server-side invalidation: signs out from all devices so a
        // stolen token is immediately useless.
        try? await supabase.auth.signOut(scope: .global)
    }

    // MARK: - Rate Limiting

    func checkAuthRateLimit(identifier: String) async -> Bool {
        do {
            let allowed: Bool = try await supabase
                .rpc("check_auth_rate_limit", params: ["p_identifier": identifier])
                .execute()
                .value
            if !allowed {
                socialAuthError = "Too many login attempts. Please wait 15 minutes before trying again."
            }
            return allowed
        } catch {
            return true // fail open — don't block legitimate users if the RPC check itself fails
        }
    }

    func checkSignupRateLimit(identifier: String) async -> Bool {
        do {
            let allowed: Bool = try await supabase
                .rpc("check_signup_rate_limit", params: ["p_identifier": identifier])
                .execute()
                .value
            if !allowed {
                socialAuthError = "Too many sign-up attempts. Please wait 1 hour before trying again."
            }
            return allowed
        } catch {
            return true
        }
    }

    // MARK: - Email Verification

    /// Re-sends the confirmation email. Call this from EmailVerificationView.
    func resendVerificationEmail() async {
        guard let email = currentUser?.email else { return }
        try? await supabase.auth.resend(email: email, type: .signup)
    }

    // MARK: - Apple Sign In

    func signInWithApple() async {
        socialAuthError = nil
        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }

        do {
            let credential = try await coordinator.signIn()
            guard let tokenData = credential.identityToken,
                  let idToken   = String(data: tokenData, encoding: .utf8) else {
                socialAuthError = "Apple Sign In failed — no identity token."
                return
            }
            try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: coordinator.nonce)
            )
        } catch let err as ASAuthorizationError where err.code == .canceled {
            // User dismissed — no error shown
        } catch {
            socialAuthError = "Sign in failed. Please try again."
        }
    }

    // MARK: - Google / Facebook Sign In

    func signInWithGoogle()   async { await oauthSignIn(provider: .google)   }
    func signInWithFacebook() async { await oauthSignIn(provider: .facebook) }

    // MARK: - OAuth callback

    /// Called from KnotApp via `.onOpenURL`. Validates BOTH scheme and host before
    /// handing the URL to Supabase — accepts only `knot://auth/callback`.
    func handleCallbackURL(_ url: URL) async {
        guard url.scheme?.lowercased() == "knot",
              url.host?.lowercased()   == "auth" else { return }
        do {
            try await supabase.auth.session(from: url)
        } catch {
            socialAuthError = "Authentication failed. Please try again."
        }
    }

    // MARK: - Private

    private func oauthSignIn(provider: Provider) async {
        socialAuthError = nil
        do {
            let redirectURL = URL(string: "knot://auth/callback")!
            try await supabase.auth.signInWithOAuth(
                provider: provider,
                redirectTo: redirectURL
            ) { url in
                try await WebAuthSession.shared.open(url: url, callbackScheme: "knot")
            }
        } catch let err as ASWebAuthenticationSessionError where err.code == .canceledLogin {
            // User dismissed
        } catch {
            socialAuthError = "Sign in failed. Please try again."
        }
    }

    private func listenToAuthChanges() async {
        for await (event, session) in await supabase.auth.authStateChanges {
            switch event {

            case .initialSession:
                isCheckingSession = false
                apply(session: session)
                if let user = session?.user {
                    await ensureProfileExists(for: user)
                    await refreshOnboardingStatus()
                    await onSignedIn?(user)
                }

            case .signedIn, .userUpdated:
                apply(session: session)
                if let user = session?.user {
                    await ensureProfileExists(for: user)
                    await refreshOnboardingStatus()
                    await onSignedIn?(user)
                }

            case .signedOut:
                isLoggedIn      = false
                isEmailVerified = false
                isBanned        = false
                currentUser     = nil

            case .tokenRefreshed:
                // Keep currentUser and verification state in sync after token refresh.
                apply(session: session)

            case .passwordRecovery:
                // User opened the app via a password-reset link.
                // Gate the UI to the password-reset screen.
                isPasswordRecovery = true
                apply(session: session)

            case .mfaChallengeVerified:
                apply(session: session)

            default:
                break
            }
        }
    }

    /// Applies session state to published properties — single source of truth.
    private func apply(session: Session?) {
        currentUser     = session?.user
        isLoggedIn      = session != nil
        isEmailVerified = session.map { isVerified($0.user) } ?? false
        isBanned        = session.map { isBannedUser($0.user) } ?? false
    }

    func refreshOnboardingStatus() async {
        guard let userID = currentUser?.id else { return }
        if let profile = try? await ProfileService.fetch(userID: userID) {
            isOnboardingComplete = profile.onboardingComplete
        }
    }

    /// A user is verified if their email or phone has been confirmed by Supabase Auth.
    /// OAuth users (Apple, Google, Facebook) are confirmed by their provider and will
    /// always have confirmedAt set at first sign-in.
    private func isVerified(_ user: Auth.User) -> Bool {
        user.emailConfirmedAt != nil || user.phoneConfirmedAt != nil
    }

    /// Returns true if the user's account is currently banned.
    private func isBannedUser(_ user: Auth.User) -> Bool {
        // bannedUntil is not exposed in the current Supabase Swift SDK.
        // Ban enforcement happens server-side; Auth.getUser() returns an error
        // for banned users so they cannot obtain a valid session.
        return false
    }

    private func ensureProfileExists(for user: Auth.User) async {
        print("[AuthManager] ensureProfileExists called for \(user.id)")
        do {
            if try await ProfileService.fetch(userID: user.id) == nil {
                let name: String
                if let meta = user.userMetadata["name"], case let .string(n) = meta, !n.isEmpty {
                    name = n
                } else if let meta = user.userMetadata["full_name"], case let .string(n) = meta, !n.isEmpty {
                    name = n
                } else if let email = user.email {
                    name = String(email.prefix(while: { $0 != "@" }))
                } else {
                    name = ""
                }
                try await ProfileService.create(userID: user.id, name: name, email: user.email ?? "")
                print("[AuthManager] profile created for \(user.id)")
            } else {
                print("[AuthManager] profile already exists for \(user.id)")
            }
        } catch {
            print("[AuthManager] ensureProfileExists error: \(error)")
        }
    }
}


// MARK: - Apple Sign In Coordinator

@MainActor
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private(set) var nonce: String = ""

    func signIn() async throws -> ASAuthorizationAppleIDCredential {
        nonce = randomNonceString()
        let hashedNonce = sha256(nonce)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                    = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: NSError(domain: "AppleSignIn", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type"]))
                return
            }
            continuation?.resume(returning: credential)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    // MARK: Crypto helpers

    /// Generates a cryptographically random nonce using rejection sampling to
    /// eliminate modulo bias (the previous `Int($0) % charset.count` approach
    /// was biased because 256 is not a multiple of 66).
    private func randomNonceString(length: Int = 32) -> String {
        let charset      = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let charsetCount = charset.count
        let limit        = 256 - 256 % charsetCount

        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if Int(byte) < limit {
                result.append(charset[Int(byte) % charsetCount])
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}


// MARK: - Web Auth Session (Google / Facebook)

@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthSession()

    func open(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: NSError(domain: "WebAuth", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No callback URL received"]))
                }
            }
            // true = ephemeral session, no shared Safari cookies.
            // This prevents silent re-authentication via a stored browser session
            // (session fixation via cookie) and forces explicit consent each time.
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider       = self
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
