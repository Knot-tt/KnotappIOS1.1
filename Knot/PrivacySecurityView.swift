import SwiftUI
import Supabase
import Auth

// MARK: - Privacy & Security View
struct PrivacySecurityView: View {
    var onAccountDeleted: () -> Void = {}
    @Environment(UserProfile.self) var profile
    var body: some View {
        List {
            Section("Security") {
                NavigationLink("Change Password") { ChangePasswordView() }
                // Two-factor authentication will return when we wire Supabase MFA enrollment.
                // Removed for now because the toggle didn't do anything — it misled users.
            }

            Section {
                Toggle("Private Account", isOn: Binding(
                    get: { profile.isPrivateAccount },
                    set: {
                        profile.isPrivateAccount = $0
                        profile.saveProfilePreferencesToSupabase()
                    }
                ))
                NavigationLink("Blocked Users") { BlockedUsersView() }
            } header: {
                Text("Privacy")
            } footer: {
                Text(profile.isPrivateAccount
                     ? "Your profile shows only your name and bio to people who aren't your connections. Only connections can message you."
                     : "Your profile is public. Anyone can view your profile and message you.")
            }

            Section {
                NavigationLink(destination: DeleteAccountView(onAccountDeleted: onAccountDeleted)) {
                    Text("Delete Account").foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Change Password View
struct ChangePasswordView: View {
    @State private var currentPassword = ""
    @State private var newPassword     = ""
    @State private var confirmPassword = ""
    @State private var isLoading       = false
    @State private var errorMessage    : String? = nil
    @State private var isComplete      = false
    @State private var showNewPw       = false
    @Environment(\.dismiss) var dismiss

    private var canUpdate: Bool {
        !currentPassword.isEmpty
        && PasswordPolicy.validate(newPassword).isEmpty
        && newPassword == confirmPassword
    }

    var body: some View {
        List {
            Section {
                SecureField("Current password", text: $currentPassword)

                HStack {
                    if showNewPw {
                        TextField("New password", text: $newPassword).autocapitalization(.none)
                    } else {
                        SecureField("New password", text: $newPassword)
                    }
                    Button(action: { showNewPw.toggle() }) {
                        Image(systemName: showNewPw ? "eye.slash" : "eye")
                            .foregroundColor(Color.knotMuted)
                    }.buttonStyle(.plain)
                }

                SecureField("Confirm new password", text: $confirmPassword)

                PasswordStrengthIndicator(password: newPassword)
                    .padding(.vertical, 4)
            }

            if let err = errorMessage {
                Section {
                    Text(err).font(.caption).foregroundColor(.red)
                }
            }

            if isComplete {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Password updated successfully.")
                    }
                }
            }

            Section {
                Button(action: { Task { await changePassword() } }) {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("Update Password")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(canUpdate ? .primary : Color.knotMuted)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(!canUpdate || isLoading)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func changePassword() async {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        guard PasswordPolicy.validate(newPassword).isEmpty else {
            errorMessage = PasswordPolicy.errorMessage(for: newPassword)
            return
        }
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Re-authenticate first to confirm the user knows their current password.
            guard let email = supabase.auth.currentUser?.email else {
                errorMessage = "Could not determine account email. Please sign out and back in."
                return
            }
            try await supabase.auth.signIn(email: email, password: currentPassword)
            // Now update to the new password.
            try await supabase.auth.update(user: UserAttributes(password: newPassword))
            isComplete      = true
            currentPassword = ""
            newPassword     = ""
            confirmPassword = ""
        } catch {
            errorMessage = "Could not update password. Check your current password and try again."
        }
    }
}

// MARK: - Blocked Users View
struct BlockedUsersView: View {
    @Environment(UserProfile.self) var profile
    @State private var blockedIDs : [UUID] = []
    @State private var isLoading  = true

    var body: some View {
        List {
            if !blockedIDs.isEmpty {
                Section {
                    ForEach(blockedIDs, id: \.self) { uid in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.knotAccent).frame(width: 36, height: 36)
                                Text(String((profile.connectionProfiles[uid] ?? "?").prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.knotOnAccent)
                            }
                            Text(profile.connectionProfiles[uid] ?? "Unknown user")
                                .font(.subheadline)
                            Spacer()
                            Button("Unblock") {
                                Task {
                                    try? await SettingsService.unblock(userID: uid)
                                    blockedIDs.removeAll { $0 == uid }
                                }
                            }
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.knotSurface)
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Blocked users can't see your profile, message you, or send connection requests.")
                }
            }
        }
        .overlay {
            if !isLoading && blockedIDs.isEmpty {
                ContentUnavailableView(
                    "No Blocked Users",
                    systemImage: "person.fill.xmark",
                    description: Text("Users you block won't be able to see your profile or contact you. Open someone's profile and tap Block to add them here.")
                )
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let ids = try? await SettingsService.fetchBlockedUserIDs() {
                blockedIDs = ids
            }
            isLoading = false
        }
    }
}


// MARK: - Delete Account View
struct DeleteAccountView: View {
    var onAccountDeleted: () -> Void = {}
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile
    @State private var password         = ""
    @State private var showPassword     = false
    @State private var typedConfirm     = ""        // OAuth users type "DELETE" instead
    @State private var isLoading        = false
    @State private var errorMessage     : String? = nil
    @State private var isDeleted        = false

    /// True iff the user has an email/password identity on their auth account.
    /// OAuth-only users (Google, Apple) have no password to re-enter.
    private var hasPasswordIdentity: Bool {
        let identities = supabase.auth.currentUser?.identities ?? []
        return identities.contains { $0.provider == "email" }
    }

    private var canDelete: Bool {
        if hasPasswordIdentity { return !password.isEmpty }
        return typedConfirm.uppercased() == "DELETE"
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(.systemRed))
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permanently delete your account")
                            .fontWeight(.semibold)
                            .foregroundColor(Color(.systemRed))
                        Text("This will permanently delete your account, listings, messages, and personal data. This cannot be undone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if hasPasswordIdentity {
                    HStack {
                        if showPassword {
                            TextField("Enter your password to confirm", text: $password)
                                .disabled(isLoading)
                                .autocapitalization(.none)
                        } else {
                            SecureField("Enter your password to confirm", text: $password)
                                .disabled(isLoading)
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(Color.knotMuted)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                } else {
                    // OAuth-only accounts (Google / Apple sign-in) have no password.
                    // Use a typed confirmation instead.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type DELETE to confirm")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("DELETE", text: $typedConfirm)
                            .disabled(isLoading)
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled()
                    }
                }
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(Color(.systemRed))
                }
            } footer: {
                if !hasPasswordIdentity {
                    Text("You signed in with Google or Apple, so we ask you to type DELETE instead of a password.")
                }
            }

            Section {
                Button(action: deleteAccount) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("Delete My Account")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                            .foregroundColor(canDelete ? .white : Color.knotMuted)
                    }
                }
                .listRowBackground(canDelete ? Color(.systemRed) : Color.knotSurface)
                .disabled(!canDelete || isLoading)

                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.secondary)
                    .disabled(isLoading)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isLoading)
        .alert("Account Deleted", isPresented: $isDeleted) {
            Button("OK") { onAccountDeleted() }
        } message: {
            Text("Your account has been permanently deleted.")
        }
    }

    private func deleteAccount() {
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            defer { isLoading = false }

            // 1. Re-authenticate (password users only).
            if hasPasswordIdentity {
                guard let email = supabase.auth.currentUser?.email else {
                    errorMessage = "Couldn't read your account email. Please sign out and back in, then try again."
                    return
                }
                do {
                    try await supabase.auth.signIn(email: email, password: password)
                } catch {
                    // Bad credentials are the most common cause here. Distinguish from
                    // network failures so the message matches the actual problem.
                    let s = (error as NSError).localizedDescription.lowercased()
                    if s.contains("invalid") || s.contains("credentials") || s.contains("password") {
                        errorMessage = "Incorrect password. Please try again."
                    } else {
                        errorMessage = "Couldn't verify your password right now. Check your connection and try again."
                    }
                    return
                }
            }
            // OAuth users skip re-auth — their JWT is already proof of ownership.
            // The "Type DELETE" gate above is the extra-friction safeguard.

            // 2. Delete the user's knots and listings before removing the auth user.
            if let userID = supabase.auth.currentUser?.id {
                // Hard-delete all knots created by this user
                try? await supabase
                    .from("knots")
                    .delete()
                    .eq("creator_id", value: userID)
                    .execute()
                // Hard-delete all shop listings owned by this user
                try? await supabase
                    .from("shop_listings")
                    .delete()
                    .eq("seller_id", value: userID)
                    .execute()
            }

            // 3. Call the delete-account Edge Function to hard-delete the auth user.
            do {
                let session = try await supabase.auth.session
                var req = URLRequest(url: URL(string: "\(Configuration.supabaseURL)/functions/v1/delete-account")!)
                req.httpMethod = "POST"
                req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (_, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    errorMessage = "Account deletion failed on the server. Please try again."
                    return
                }
            } catch {
                errorMessage = "Network error while deleting your account. Please try again."
                return
            }

            // 4. Locally tear down state. The server already invalidated the user.
            try? await supabase.auth.signOut(scope: .local)
            profile.clearAllData()
            isDeleted = true
        }
    }
}
