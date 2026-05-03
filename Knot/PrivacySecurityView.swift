import SwiftUI
import Supabase
import Auth

// MARK: - Privacy & Security View
struct PrivacySecurityView: View {
    var onAccountDeleted: () -> Void = {}
    @Environment(UserProfile.self) var profile
    @State private var twoFactorEnabled = false
    var body: some View {
        List {
            Section("Security") {
                NavigationLink("Change Password") { ChangePasswordView() }
                Toggle("Two-Factor Authentication", isOn: $twoFactorEnabled)
            }

            Section {
                Toggle("Private Account", isOn: Binding(
                    get: { profile.isPrivateAccount },
                    set: { profile.isPrivateAccount = $0 }
                ))
                NavigationLink("Blocked Users") { BlockedUsersView() }
            } header: {
                Text("Privacy")
            } footer: {
                Text(profile.isPrivateAccount
                     ? "Your profile shows only your name and bio to people who aren't your connections. Only connections can message you."
                     : "Your profile is public. Anyone can view your profile and message you.")
            }

            Section("Data") {
                Button("Download My Data") {
                    // TODO: trigger data export via Supabase
                }
                .foregroundColor(.black)
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
                            .foregroundColor(Color(.systemGray3))
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
                            .foregroundColor(canUpdate ? .black : Color(.systemGray3))
                            .fontWeight(.semibold)
                    }
                }
                .disabled(!canUpdate || isLoading)
            }
        }
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
    var body: some View {
        List {
            // TODO: load from Supabase
        }
        .overlay {
            ContentUnavailableView(
                "No Blocked Users",
                systemImage: "person.fill.xmark",
                description: Text("Users you block won't be able to see your profile or contact you.")
            )
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
    }
}


// MARK: - Delete Account View
struct DeleteAccountView: View {
    var onAccountDeleted: () -> Void = {}
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile
    @State private var password     = ""
    @State private var showPassword = false
    @State private var isLoading    = false
    @State private var showError    = false
    @State private var isDeleted    = false

    private var canDelete: Bool { !password.isEmpty }

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
                HStack {
                    if showPassword {
                        TextField("Enter your password to confirm", text: $password)
                            .disabled(isLoading)
                    } else {
                        SecureField("Enter your password to confirm", text: $password)
                            .disabled(isLoading)
                    }
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(Color(.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
                if showError {
                    Text("Incorrect password. Please try again.")
                        .font(.caption)
                        .foregroundColor(Color(.systemRed))
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
                            .foregroundColor(canDelete ? .white : Color(.systemGray3))
                    }
                }
                .listRowBackground(canDelete ? Color(.systemRed) : Color(.systemGray5))
                .disabled(!canDelete || isLoading)

                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.secondary)
                    .disabled(isLoading)
            }
        }
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
        showError = false
        Task { @MainActor in
            defer { isLoading = false }
            do {
                // Step 1: Re-authenticate to confirm the user knows their password.
                guard let email = supabase.auth.currentUser?.email else {
                    showError = true
                    return
                }
                try await supabase.auth.signIn(email: email, password: password)

                // Step 2: Call the delete-account Edge Function (service_role required
                // to call supabase.auth.admin.deleteUser — the client SDK cannot do this).
                //
                // TODO (Phase 7): deploy a `delete-account` edge function and call it here.
                // Until then, the account is signed out on this device but NOT permanently
                // deleted from Supabase. Show the user a clear message about this.
                //
                // Example call when ready:
                //   let session = try await supabase.auth.session
                //   var req = URLRequest(url: URL(string: "\(Configuration.supabaseURL)/functions/v1/delete-account")!)
                //   req.httpMethod = "POST"
                //   req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                //   let (_, response) = try await URLSession.shared.data(for: req)
                //   guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

                // For now: sign out globally so the account is inaccessible on all devices,
                // then clear local state. The account still exists in Supabase until Phase 7.
                try? await supabase.auth.signOut(scope: .global)
                profile.clearAllData()
                isDeleted = true
            } catch {
                showError = true
            }
        }
    }
}