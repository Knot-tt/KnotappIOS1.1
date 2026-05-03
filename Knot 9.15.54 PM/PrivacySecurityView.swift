import SwiftUI

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
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                SecureField("Current password", text: $currentPassword)
                SecureField("New password", text: $newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
            }
            Section {
                Button("Update Password") {
                    // TODO: update via Supabase
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.black)
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
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

    private let correctPassword = "Ruhaan08"   // TODO: verify via Supabase
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isLoading = false
            if password == correctPassword {
                profile.clearAllData()
                isDeleted = true
                // TODO: call Supabase delete user API here
            } else {
                showError = true
            }
        }
    }
}