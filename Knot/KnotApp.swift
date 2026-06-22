//
//  KnotApp.swift
//  Knot
//
//  Created by Ruhaan Kumar on 22/3/26.
//

import SwiftUI
import Auth
import Supabase
import UserNotifications

// MARK: - App Delegate (receives APNs device token from iOS)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Register the window-key observer at launch so every window — including
        // ones created later for sheets, fullScreenCovers, etc. — gets the
        // tap-to-dismiss gesture.
        KeyboardDismiss.installGlobalTap()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await NotificationManager.shared.saveToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
    }
}

@main
struct KnotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthManager()

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
                Color.knotBackground.ignoresSafeArea()

            } else if authManager.isLoggedIn && authManager.isBanned {
                // Account is banned. Show nothing useful and force sign-out.
                BannedAccountView()

            } else if authManager.isLoggedIn && authManager.isPasswordRecovery {
                // User opened the app via a password-reset link.
                // Show a dedicated screen so they can set a new password.
                PasswordResetView()

            } else if authManager.isLoggedIn && authManager.needsNameEntry {
                // Apple sign-in gave us no usable name — let the user pick one
                // before entering the app (instead of a random email jumble).
                AppleNameEntryView()

            } else if authManager.isLoggedIn {
                MainTabView(name: "", onLogout: {
                    Task {
                        await NotificationManager.shared.clearToken()
                        await authManager.signOut()
                    }
                })
                .onAppear {
                    Task { await NotificationManager.shared.requestPermission() }
                }

            } else {
                LoginView()
            }
        }
        // Handles the knot://auth/callback redirect from Google and Facebook OAuth.
        // AuthManager validates the scheme AND host before processing.
        // Also handles knot://stripe-connect/return after Stripe Express onboarding.
        .onOpenURL { url in
            if url.host == "stripe-connect" { return } // just bring app to foreground
            Task { await authManager.handleCallbackURL(url) }
        }
        // App-wide: tap anywhere outside a text field to dismiss the keyboard.
        .onAppear { KeyboardDismiss.installGlobalTap() }
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
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                Text("Verify your email")
                    .font(.system(size: 26, weight: .bold))

                if let email = authManager.currentUser?.email {
                    Text("We sent a confirmation link to\n**\(email)**")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if authManager.currentUser?.phone != nil {
                    Text("We sent a verification code to your phone number.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Open the link in the email to activate your account.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
                            .foregroundColor(Color.knotOnAccent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(canResend ? Color.knotAccent : Color.gray)
                .cornerRadius(12)
                .disabled(!canResend || isResending)

                Button(action: { Task { await authManager.signOut() } }) {
                    Text("Sign out")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(Color.knotBackground.ignoresSafeArea())
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
    @AppStorage(passwordRecoveryNameKey) private var recoveryName = ""
    @AppStorage(passwordRecoveryContactKey) private var recoveryContact = ""
    @AppStorage(passwordRecoveryUsesPhoneKey) private var recoveryUsesPhone = false
    @State private var newPassword     = ""
    @State private var confirmPassword = ""
    @State private var isLoading       = false
    @State private var errorMessage    : String?
    @State private var isComplete      = false
    @State private var showPassword    = false
    @State private var currentAccountName = ""
    @State private var isResolvingIdentity = true

    private var passwordIssue: String? {
        let result = PasswordPolicy.validate(newPassword)
        return result.isEmpty ? nil : result.first
    }

    private var doesRecoveryMatchCurrentUser: Bool {
        guard !recoveryName.isEmpty, !recoveryContact.isEmpty else { return false }
        guard let user = authManager.currentUser else { return false }

        let expectedName = normalizeRecoveryName(recoveryName)
        let actualName = normalizeRecoveryName(currentAccountName)
        guard !actualName.isEmpty, actualName == expectedName else { return false }

        if recoveryUsesPhone {
            return normalizeRecoveryPhone("", number: user.phone ?? "") == recoveryContact
        }

        return normalizeRecoveryEmail(user.email ?? "") == recoveryContact
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.rotation")
                    .font(.system(size: 56))
                    .foregroundColor(.primary)

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
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if isResolvingIdentity {
                    ProgressView()
                        .tint(Color.knotAccent)
                        .padding(.horizontal, 32)
                } else if doesRecoveryMatchCurrentUser {
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
                                    .foregroundColor(Color.knotOnAccent)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(Color.knotAccent)
                        .cornerRadius(12)
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("We couldn't verify this reset request.")
                            .font(.headline)
                        Text("Start over from Forgot Password and make sure the name and email or phone number belong to the same account.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: startOver) {
                            Text("Start Over")
                                .fontWeight(.semibold)
                                .foregroundColor(Color.knotOnAccent)
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(Color.knotAccent)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await resolveCurrentAccountName()
            }
        }
    }

    private func updatePassword() async {
        guard doesRecoveryMatchCurrentUser else {
            errorMessage = "This reset request no longer matches the account."
            return
        }
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
            clearRecoveryContext()
            authManager.isPasswordRecovery = false
            isComplete = true
        } catch {
            errorMessage = "Failed to update password. Please request a new reset link."
        }
    }

    private func resolveCurrentAccountName() async {
        isResolvingIdentity = true
        defer { isResolvingIdentity = false }

        guard let user = authManager.currentUser else {
            currentAccountName = ""
            return
        }

        if let meta = user.userMetadata["name"], case let .string(value) = meta, !value.isEmpty {
            currentAccountName = value
            return
        }

        if let meta = user.userMetadata["full_name"], case let .string(value) = meta, !value.isEmpty {
            currentAccountName = value
            return
        }

        if let fetchedProfile = try? await ProfileService.fetch(userID: user.id) {
            currentAccountName = fetchedProfile.name
        } else {
            currentAccountName = ""
        }
    }

    private func startOver() {
        clearRecoveryContext()
        authManager.isPasswordRecovery = false
        Task { await authManager.signOut() }
    }

    private func clearRecoveryContext() {
        recoveryName = ""
        recoveryContact = ""
        recoveryUsesPhone = false
    }
}

// MARK: - Apple Name Entry (shown once when Apple sign-in gave us no name)

struct AppleNameEntryView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var name = ""
    @State private var isSaving = false
    @State private var saveFailed = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Text("What should we call you?")
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("This is the name other people on Knot will see. You can change it later in your profile.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Your name", text: $name)
                .padding()
                .background(Color.knotSurface)
                .cornerRadius(12)
                .knotSurfaceBorder(cornerRadius: 12)
                .submitLabel(.done)
                .onSubmit { save() }

            if saveFailed {
                Text("Couldn't save your name. Check your connection and try again.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: save) {
                if isSaving {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .foregroundColor(Color.knotOnAccent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(trimmed.isEmpty ? Color.knotMuted : Color.knotAccent)
            .cornerRadius(12)
            .disabled(isSaving || trimmed.isEmpty)

            Spacer()
        }
        .padding(.horizontal, 32)
        .background(Color.knotBackground.ignoresSafeArea())
    }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving   = true
        saveFailed = false
        Task {
            let ok = await authManager.saveChosenName(trimmed)
            // On success, needsNameEntry flips false and RootView advances; this
            // view goes away. On failure, show an inline error and let them retry.
            if !ok { saveFailed = true }
            isSaving = false
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
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { Task { await authManager.signOut() } }) {
                Text("Sign out")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.knotOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.knotAccent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .background(Color.knotBackground.ignoresSafeArea())
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
                Image(systemName: show ? "eye.slash" : "eye").foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.knotSurface)
        .cornerRadius(12)
        .knotSurfaceBorder(cornerRadius: 12)
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
