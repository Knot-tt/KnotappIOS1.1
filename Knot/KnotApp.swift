//
//  KnotApp.swift
//  Knot
//
//  Created by Ruhaan Kumar on 22/3/26.
//

import SwiftUI
import Auth
import Supabase
import StripePaymentSheet

@main
struct KnotApp: App {
    @StateObject private var authManager = AuthManager()

    init() {
        STPAPIClient.shared.publishableKey = "pk_test_51TS7Z09YQ1NZSRifYgt02s8sahVKCroAoSCXq16wnMIGCS8LCyPVesUWHuh935NY85yBeLuzBJNs7QhRlXcDcBxt00b5CHQKZq"
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isCheckingSession {
                // Blank white screen while we confirm the session with Supabase.
                Color.white.ignoresSafeArea()

            } else if authManager.isLoggedIn && authManager.isBanned {
                // Account is banned. Show nothing useful and force sign-out.
                BannedAccountView()

            } else if authManager.isLoggedIn && authManager.isPasswordRecovery {
                // User opened the app via a password-reset link.
                // Show a dedicated screen so they can set a new password.
                PasswordResetView()

            } else if authManager.isLoggedIn && !authManager.isEmailVerified && !authManager.isVerificationBypassed {
                EmailVerificationGateView()

            } else if authManager.isLoggedIn && !authManager.isOnboardingComplete {
                OnboardingFlowView()

            } else if authManager.isLoggedIn {
                MainTabView(name: "", onLogout: {
                    Task { await authManager.signOut() }
                })

            } else {
                LoginView()
            }
        }
        // Handles the knot://auth/callback redirect from Google and Facebook OAuth.
        // AuthManager validates the scheme AND host before processing.
        .onOpenURL { url in
            Task { await authManager.handleCallbackURL(url) }
        }
    }
}

// MARK: - Onboarding Flow (birthday + interests, shown once for every new user)

struct OnboardingFlowView: View {
    @EnvironmentObject var authManager: AuthManager

    private var userName: String {
        let meta = authManager.currentUser?.userMetadata
        if case let .string(n) = meta?["name"], !n.isEmpty { return n }
        if case let .string(n) = meta?["full_name"], !n.isEmpty { return n }
        return ""
    }

    var body: some View {
        NavigationStack {
            BirthdayView(name: userName)
        }
    }
}

// MARK: - Email Verification Gate View (shown when logged-in user hasn't confirmed email)

struct EmailVerificationGateView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var isResending = false
    @State private var resentAt: Date? = nil

    private var canResend: Bool {
        guard let last = resentAt else { return true }
        return Date().timeIntervalSince(last) > 60 // one resend per minute
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "envelope.badge")
                .font(.system(size: 64))
                .foregroundColor(.black)

            VStack(spacing: 12) {
                Text("Verify your email")
                    .font(.system(size: 26, weight: .bold))

                if let email = authManager.currentUser?.email {
                    Text("We sent a confirmation link to\n**\(email)**")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                } else if authManager.currentUser?.phone != nil {
                    Text("We sent a verification code to your phone number.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                Text("Open the link in the email to activate your account.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                // Resend button (throttled to 1 per minute)
                Button(action: resendEmail) {
                    if isResending {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text(canResend ? "Resend confirmation email" : "Email sent — check your inbox")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(canResend ? Color.black : Color.gray)
                .cornerRadius(12)
                .disabled(!canResend || isResending)

                Button(action: {
                    Task {
                        try? await ProfileService.completeOnboarding()
                        authManager.isEmailVerified = true
                    }
                }) {
                    Text("Skip verification (testing only)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Button(action: { Task { await authManager.signOut() } }) {
                    Text("Sign out")
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(Color.white.ignoresSafeArea())
    }

    private func resendEmail() {
        isResending = true
        Task {
            await authManager.resendVerificationEmail()
            resentAt   = Date()
            isResending = false
        }
    }
}

// MARK: - Password Reset View

struct PasswordResetView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var newPassword     = ""
    @State private var confirmPassword = ""
    @State private var isLoading       = false
    @State private var errorMessage    : String?
    @State private var isComplete      = false
    @State private var showPassword    = false

    private var passwordIssue: String? {
        let result = PasswordPolicy.validate(newPassword)
        return result.isEmpty ? nil : result.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.rotation")
                    .font(.system(size: 56))
                    .foregroundColor(.black)

                Text("Set a new password")
                    .font(.system(size: 26, weight: .bold))

                if isComplete {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.green)
                        Text("Password updated!")
                            .font(.headline)
                        Text("You're now signed in with your new password.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 12) {
                        PasswordField(label: "New password",     text: $newPassword,     show: $showPassword)
                        PasswordField(label: "Confirm password", text: $confirmPassword, show: $showPassword)
                        PasswordStrengthIndicator(password: newPassword)

                        if let err = errorMessage {
                            Text(err).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                        }

                        Button(action: { Task { await updatePassword() } }) {
                            if isLoading {
                                ProgressView().tint(.white).frame(maxWidth: .infinity)
                            } else {
                                Text("Update password")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(Color.black)
                        .cornerRadius(12)
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func updatePassword() async {
        guard passwordIssue == nil else {
            errorMessage = passwordIssue
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await supabase.auth.update(user: UserAttributes(password: newPassword))
            authManager.isPasswordRecovery = false
            isComplete = true
        } catch {
            errorMessage = "Failed to update password. Please request a new reset link."
        }
    }
}

// MARK: - Banned Account View

struct BannedAccountView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)
            Text("Account suspended")
                .font(.system(size: 26, weight: .bold))
            Text("Your account has been suspended. If you believe this is an error, contact support.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { Task { await authManager.signOut() } }) {
                Text("Sign out")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - Shared Password UI Components

struct PasswordField: View {
    let label: String
    @Binding var text: String
    @Binding var show: Bool

    var body: some View {
        HStack {
            if show {
                TextField(label, text: $text).autocapitalization(.none)
            } else {
                SecureField(label, text: $text)
            }
            Button(action: { show.toggle() }) {
                Image(systemName: show ? "eye.slash" : "eye").foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PasswordStrengthIndicator: View {
    let password: String

    private var checks: [(String, Bool)] {
        PasswordPolicy.checks(for: password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(checks, id: \.0) { label, passing in
                HStack(spacing: 6) {
                    Image(systemName: passing ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(passing ? .green : .gray)
                    Text(label).font(.caption).foregroundColor(passing ? .primary : .gray)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
