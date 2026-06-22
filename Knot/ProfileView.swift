import SwiftUI

// MARK: - Profile View
struct ProfileView: View {
    let onLogout: () -> Void
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        Circle().fill(Color.knotAccent).frame(width: 90, height: 90)
                        if let img = profile.profileImage {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                        } else {
                            Text(profile.initial)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(Color.knotOnAccent)
                        }
                    }
                    .padding(.top, 32)

                    Text(profile.name).font(.system(size: 22, weight: .bold)).foregroundColor(.primary)

                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Stats strip
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("\(profile.profileConnectionCount)")
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            Text("Connections")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().frame(height: 32)

                        VStack(spacing: 2) {
                            Text("\(profile.profileListingCount)")
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            Text("Listings")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().frame(height: 32)

                        VStack(spacing: 2) {
                            Text("\(profile.profileKnotCount)")
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            Text("Knots")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    .background(Color.knotSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotBorder, lineWidth: 1))
                    .padding(.horizontal)

                    Divider().padding(.horizontal)

                    // My Listings section
                    if profile.showListingsOnProfile && !profile.myListings.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("My Listings")
                                .font(.headline).padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(profile.myListings) { listing in
                                        VStack(alignment: .leading, spacing: 4) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5))
                                                    .frame(width: 100, height: 80)
                                                if let img = listing.images.first {
                                                    Image(uiImage: img).resizable().scaledToFill()
                                                        .frame(width: 100, height: 80).clipped()
                                                        .cornerRadius(10)
                                                } else {
                                                    Image(systemName: listing.type.icon)
                                                        .font(.system(size: 28)).foregroundColor(Color(.systemGray3))
                                                }
                                            }
                                            Text(listing.name).font(.caption).fontWeight(.semibold)
                                                .lineLimit(1).frame(width: 100, alignment: .leading)
                                            if listing.price > 0 {
                                                Text("$\(listing.price)").font(.caption2).foregroundColor(.secondary)
                                            } else {
                                                Text("Free").font(.caption2).foregroundColor(.green)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    VStack(spacing: 0) {
                        NavigationLink(destination: EditProfileView()) {
                            ProfileRowLabel(icon: "person.fill", label: "Edit Profile")
                        }
                        .buttonStyle(ProfileRowButtonStyle())

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: NotificationsSettingsView()) {
                            ProfileRowLabel(icon: "bell.fill", label: "Notifications")
                        }
                        .buttonStyle(ProfileRowButtonStyle())

                        Divider().padding(.leading, 48)

                        // Quick private account toggle
                        HStack(spacing: 14) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15)).foregroundColor(.primary).frame(width: 24)
                            Text("Private Account").font(.subheadline).foregroundColor(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { profile.isPrivateAccount },
                                set: {
                                    profile.isPrivateAccount = $0
                                    profile.saveProfilePreferencesToSupabase()
                                }
                            )).labelsHidden()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: ProfileDisplaySettingsView()) {
                            ProfileRowLabel(icon: "eye.fill", label: "Profile Display")
                        }
                        .buttonStyle(ProfileRowButtonStyle())

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: PrivacySecurityView(onAccountDeleted: onLogout)) {
                            ProfileRowLabel(icon: "shield.fill", label: "Privacy & Security")
                        }
                        .buttonStyle(ProfileRowButtonStyle())

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: WalletPaymentsView()) {
                            ProfileRowLabel(icon: "creditcard.fill", label: "Wallet & Payments")
                        }
                        .buttonStyle(ProfileRowButtonStyle())

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: HelpSupportView()) {
                            ProfileRowLabel(icon: "questionmark.circle.fill", label: "Help & Support")
                        }
                        .buttonStyle(ProfileRowButtonStyle())

                        Divider().padding(.leading, 48)

                        Button(action: { showLogoutConfirm = true }) {
                            ProfileRowLabel(icon: "rectangle.portrait.and.arrow.right", label: "Log Out", isDestructive: true)
                        }
                        .buttonStyle(ProfileRowButtonStyle())
                        .alert("Log Out", isPresented: $showLogoutConfirm) {
                            Button("Log Out", role: .destructive) {
                                dismiss()
                                onLogout()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to log out?")
                        }
                    }
                    .background(Color.knotSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.knotBorder, lineWidth: 1))
                    .padding(.horizontal)
                }
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await profile.loadConnections()
                await profile.loadKnots()
                await profile.loadListings()
            }
        }
    }
}

// MARK: - Profile Display Settings
struct ProfileDisplaySettingsView: View {
    @Environment(UserProfile.self) var profile

    var body: some View {
        List {
            Section {
                Toggle("Show Knots", isOn: Binding(
                    get: { profile.showKnotsOnProfile },
                    set: {
                        profile.showKnotsOnProfile = $0
                        profile.saveProfilePreferencesToSupabase()
                    }
                ))
                Toggle("Show Listings", isOn: Binding(
                    get: { profile.showListingsOnProfile },
                    set: {
                        profile.showListingsOnProfile = $0
                        profile.saveProfilePreferencesToSupabase()
                    }
                ))
                Toggle("Show Connections", isOn: Binding(
                    get: { profile.showConnectionsOnProfile },
                    set: {
                        profile.showConnectionsOnProfile = $0
                        profile.saveProfilePreferencesToSupabase()
                    }
                ))
            } header: {
                Text("What to show on your profile")
            } footer: {
                Text("Choose what other people can see when they visit your profile.")
            }
        }
        .navigationTitle("Profile Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile Row Button Style (press highlight)
/// Gives each profile row a visible pressed state so it's clear what you're
/// tapping. NavigationLink renders as a button too, so this works for both the
/// navigation rows and the plain action buttons (e.g. Log Out).
/// `Color.primary.opacity` reads as a dark wash in light mode and a light wash
/// in dark mode — visible against `knotSurface` either way.
struct ProfileRowButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
    }
}

// MARK: - Profile Row Label (visual layer used inside NavigationLink and Button)
struct ProfileRowLabel: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isDestructive ? .red : .primary)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundColor(isDestructive ? .red : .primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(.systemGray3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Profile Row (button wrapper)
struct ProfileRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ProfileRowLabel(icon: icon, label: label, isDestructive: isDestructive)
        }
    }
}
