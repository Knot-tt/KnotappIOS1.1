//
//  AuthManager.swift
//  Knot
//

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
    @Published var isOnboardingComplete    = false
    @Published var isPasswordRecovery      = false
    @Published var currentUser           : Auth.User? = nil
    @Published var socialAuthError       : String?    = nil
    @Published var isBanned              = false
    /// Set when a new Apple sign-in produced no usable name (e.g. Hide My Email
    /// with name not shared). RootView shows a one-time "choose your name" step.
    @Published var needsNameEntry        = false

    var onSignedIn  : ((Auth.User) async -> Void)?
    /// Fired before the auth state is cleared, so UserProfile can wipe in-memory state
    /// and any device-cached data. Account data lives in Supabase — this only clears local UI cache.
    var onSignOut   : (() -> Void)?

    init() {
        Task { await listenToAuthChanges() }
    }

    // MARK: - Sign Out

    func signOut() async {
        // Wipe in-memory + device-cached profile data BEFORE auth state flips.
        // Prevents the previous user's data leaking into the next sign-in.
        onSignOut?()

        // Clear local state unconditionally first.
        // The user must never be stuck in a logged-in state because of a network failure.
        isLoggedIn            = false
        isEmailVerified       = false
        isOnboardingComplete  = false
        isPasswordRecovery    = false
        isBanned              = false
        currentUser           = nil

        // Best-effort server-side invalidation: signs out from all devices so a
        // stolen token is immediately useless.
        try? await supabase.auth.signOut(scope: .global)
        // Also clear the local Supabase session so the next launch starts fresh
        // even if the global signOut failed (network error, etc.).
        try? await supabase.auth.signOut(scope: .local)
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

    // MARK: - Phone sign-up (no SMS / no OTP)

    /// Internal email used to register a phone-number account. The phone number is
    /// just an identifier — there is no SMS or OTP. This MUST stay in sync with the
    /// `phone-signup` edge function's `INTERNAL_EMAIL_DOMAIN`.
    static func phoneInternalEmail(forE164 e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        return "\(digits)@phone.knot.app"
    }

    /// Creates an auto-confirmed account keyed to a phone number via the
    /// `phone-signup` edge function (no SMS). Returns the internal email to sign
    /// in with. Throws a user-facing message (e.g. "account already exists").
    func phoneSignUp(e164Phone: String, password: String, name: String) async throws -> String {
        struct Body: Encodable { let phone: String; let password: String; let name: String }
        struct Success: Decodable { let email: String }
        do {
            let result: Success = try await supabase.functions.invoke(
                "phone-signup",
                options: .init(body: Body(phone: e164Phone, password: password, name: name))
            )
            return result.email
        } catch let FunctionsError.httpError(_, data) {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? "Could not create account. Please try again."
            throw NSError(domain: "PhoneSignUp", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    // MARK: - Email Verification

    /// Re-sends the confirmation email. Call this from EmailVerificationView.
    func resendVerificationEmail() async {
        guard let email = currentUser?.email else { return }
        try? await supabase.auth.resend(email: email, type: .signup)
    }

    // MARK: - Google / Facebook Sign In

    func signInWithGoogle()   async { await oauthSignIn(provider: .google)   }
    func signInWithFacebook() async { await oauthSignIn(provider: .facebook) }

    // MARK: - Apple Sign In
    //
    // Apple sign-in is a native iOS flow (not a web redirect). The button
    // (AppleSignInButton) generates an unhashed nonce, hashes it, sends the
    // hash with the request, and receives an identityToken back from Apple.
    // We then exchange (identityToken + original unhashed nonce) with Supabase
    // — Supabase validates against Apple's keys and returns a session.

    /// Holds the unhashed nonce between the request being created and the
    /// credential coming back. iOS calls these on the main thread sequentially.
    private var pendingAppleNonce: String?

    /// The name Apple gave us on this sign-in. Apple only provides `fullName` on
    /// the FIRST authorization, so we capture it here and let `ensureProfileExists`
    /// use it instead of falling back to the (random) email local-part.
    private var pendingAppleName: String?

    /// Generate a random nonce, store it, and return the SHA-256 hash that
    /// goes into the ASAuthorizationAppleIDRequest. The unhashed value is
    /// later sent to Supabase to verify the chain.
    func makeNonceForAppleRequest() -> String {
        let nonce = Self.randomNonceString()
        pendingAppleNonce = nonce
        return Self.sha256(nonce)
    }

    /// Called by the AppleSignInButton's onCompletion handler. Exchanges the
    /// Apple identity token for a Supabase session.
    func handleAppleAuthorization(_ authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            socialAuthError = "Apple sign-in returned an unexpected credential."
            print("[Apple Sign-In] Wrong credential type: \(type(of: authorization.credential))")
            return
        }
        guard let nonce = pendingAppleNonce else {
            socialAuthError = "Apple sign-in nonce was missing. Please try again."
            print("[Apple Sign-In] No pending nonce — button may have been initialised out of order")
            return
        }
        guard let tokenData = credential.identityToken,
              let idTokenString = String(data: tokenData, encoding: .utf8) else {
            socialAuthError = "Apple did not return an identity token."
            print("[Apple Sign-In] identityToken missing on credential. user=\(credential.user), email=\(credential.email ?? "nil")")
            return
        }
        // Apple only includes the name on the very first authorization — capture it
        // now so the profile gets a real name instead of the email jumble.
        if let fullName = credential.fullName {
            let joined = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            pendingAppleName = joined.isEmpty ? nil : joined
        }
        print("[Apple Sign-In] Got identity token (len=\(idTokenString.count)). Exchanging with Supabase…")
        print("[Apple Sign-In] Decoded `aud` claim: \(Self.decodeJWTAudience(idTokenString) ?? "couldn't decode")")
        do {
            try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idTokenString, nonce: nonce)
            )
            print("[Apple Sign-In] Supabase exchange OK — auth listener should now fire")
        } catch {
            let nsError = error as NSError
            print("[Apple Sign-In] Supabase exchange FAILED: \(nsError.localizedDescription)")
            print("[Apple Sign-In] Full error: \(error)")
            // Surface the real reason instead of a generic "try again".
            let msg = nsError.localizedDescription
            if msg.lowercased().contains("audience") || msg.lowercased().contains("invalid client") {
                socialAuthError = "Apple sign-in isn't configured for this app's bundle ID. Add it to Supabase → Auth → Providers → Apple → Authorized Client IDs."
            } else {
                socialAuthError = "Apple sign-in failed: \(msg)"
            }
        }
        pendingAppleNonce = nil
    }

    /// Decode the `aud` claim from a JWT (header.payload.signature) — used for
    /// debugging "Apple sign-in works in Supabase but not in iOS" issues, where
    /// the audience usually doesn't match the configured Client IDs.
    private static func decodeJWTAudience(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["aud"] as? String
    }

    /// Cryptographically secure random nonce per Apple's recommended length (32 bytes).
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""; var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - OAuth callback

    /// Called from KnotApp via `.onOpenURL`. Validates BOTH scheme and host before
    /// handing the URL to Supabase — accepts only `knot://auth/callback`.
    func handleCallbackURL(_ url: URL) async {
        print("[OAuth] Callback URL received: \(url)")
        guard url.scheme?.lowercased() == "knot",
              url.host?.lowercased()   == "auth" else {
            print("[OAuth] Invalid scheme/host. Expected knot://auth")
            return
        }
        do {
            print("[OAuth] Processing auth session...")
            try await supabase.auth.session(from: url)
            print("[OAuth] Session established successfully")
        } catch {
            print("[OAuth] Auth session error: \(error)")
            socialAuthError = "Authentication failed. Please try again."
        }
    }

    // MARK: - Private

    private func oauthSignIn(provider: Provider) async {
        socialAuthError = nil
        do {
            print("[OAuth] Starting \(provider) sign-in...")
            let redirectURL = URL(string: "knot://auth/callback")!
            try await supabase.auth.signInWithOAuth(
                provider: provider,
                redirectTo: redirectURL
            ) { url in
                print("[OAuth] OAuth URL received: \(url.absoluteString)")
                if url.host == "localhost" {
                    print("[OAuth] WARNING: Got localhost URL — Supabase OAuth not configured!")
                }
                return try await WebAuthSession.shared.open(url: url, callbackScheme: "knot")
            }
            print("[OAuth] Successfully authenticated with Supabase")
        } catch let err as ASWebAuthenticationSessionError where err.code == .canceledLogin {
            // User dismissed
            print("[OAuth] User dismissed the browser")
        } catch {
            print("[OAuth] ERROR: \(error.localizedDescription)")
            print("[OAuth] Full error: \(error)")
            socialAuthError = "Sign in failed: \(error.localizedDescription)"
        }
    }

    private func listenToAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {

            case .initialSession:
                apply(session: session)
                if let user = session?.user {
                    await ensureProfileExists(for: user)
                    await refreshOnboardingStatus()
                    await onSignedIn?(user)
                }
                isCheckingSession = false

            case .signedIn, .userUpdated:
                // Resolve the profile (and the needsNameEntry flag) BEFORE flipping
                // isLoggedIn — otherwise RootView briefly shows MainTabView before
                // switching to the "choose your name" screen.
                if let user = session?.user {
                    await ensureProfileExists(for: user)
                }
                apply(session: session)
                if let user = session?.user {
                    await refreshOnboardingStatus()
                    await onSignedIn?(user)
                }

            case .signedOut:
                onSignOut?()
                isLoggedIn      = false
                isEmailVerified = false
                isOnboardingComplete = false
                isBanned        = false
                needsNameEntry  = false
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
        defer { pendingAppleName = nil }
        do {
            if let existing = try await ProfileService.fetch(userID: user.id) {
                // Profile already exists. If it somehow has no name — e.g. the user
                // closed the app on the name step last time — prompt again so they
                // never end up nameless.
                if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    needsNameEntry = true
                }
                return
            }
            let name: String
            if let appleName = pendingAppleName, !appleName.isEmpty {
                name = appleName
            } else if let meta = user.userMetadata["name"], case let .string(n) = meta, !n.isEmpty {
                name = n
            } else if let meta = user.userMetadata["full_name"], case let .string(n) = meta, !n.isEmpty {
                name = n
            } else {
                // No real name available (e.g. Apple Hide My Email without a
                // shared name). Leave it blank and prompt — never use the random
                // email local-part as a display name.
                name = ""
            }
            try await ProfileService.create(userID: user.id, name: name, email: user.email ?? "")
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                needsNameEntry = true
            }
        } catch {
            // Silently handle errors to avoid blocking auth flow
        }
    }

    /// Persist a name the user picked on the "choose your name" step. Returns
    /// true (and clears the prompt so RootView advances) only on success, so a
    /// failed save never drops the user into the app still nameless.
    @discardableResult
    func saveChosenName(_ rawName: String) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            try await ProfileService.updateName(name)
            needsNameEntry = false
            return true
        } catch {
            return false
        }
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
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
