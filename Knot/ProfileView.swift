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
                        Circle().fill(Color.black).frame(width: 90, height: 90)
                        if let img = profile.profileImage {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                        } else {
                            Text(profile.initial)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 32)

                    Text(profile.name).font(.system(size: 22, weight: .bold)).foregroundColor(.black)

                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Stats strip
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("\(profile.connections.count)")
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                            Text("Connections")
                                .font(.caption).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().frame(height: 32)

                        VStack(spacing: 2) {
                            Text("\(profile.myListings.count)")
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                            Text("Listings")
                                .font(.caption).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().frame(height: 32)

                        VStack(spacing: 2) {
                            Text("\(profile.joinedGroupIDs.count)")
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                            Text("Knots")
                                .font(.caption).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
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
                                                Text("$\(listing.price)").font(.caption2).foregroundColor(.gray)
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
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: NotificationsSettingsView()) {
                            ProfileRowLabel(icon: "bell.fill", label: "Notifications")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)

                        // Quick private account toggle
                        HStack(spacing: 14) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15)).foregroundColor(.black).frame(width: 24)
                            Text("Private Account").font(.subheadline).foregroundColor(.black)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { profile.isPrivateAccount },
                                set: { profile.isPrivateAccount = $0 }
                            )).labelsHidden()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: ProfileDisplaySettingsView()) {
                            ProfileRowLabel(icon: "eye.fill", label: "Profile Display")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: PrivacySecurityView(onAccountDeleted: onLogout)) {
                            ProfileRowLabel(icon: "shield.fill", label: "Privacy & Security")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: WalletPaymentsView()) {
                            ProfileRowLabel(icon: "creditcard.fill", label: "Wallet & Payments")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)

                        NavigationLink(destination: HelpSupportView()) {
                            ProfileRowLabel(icon: "questionmark.circle.fill", label: "Help & Support")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)

                        Button(action: { showLogoutConfirm = true }) {
                            ProfileRowLabel(icon: "rectangle.portrait.and.arrow.right", label: "Log Out", isDestructive: true)
                        }
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
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1))
                    .padding(.horizontal)
                }
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
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
                    set: { profile.showKnotsOnProfile = $0 }
                ))
                Toggle("Show Listings", isOn: Binding(
                    get: { profile.showListingsOnProfile },
                    set: { profile.showListingsOnProfile = $0 }
                ))
                Toggle("Show Connections", isOn: Binding(
                    get: { profile.showConnectionsOnProfile },
                    set: { profile.showConnectionsOnProfile = $0 }
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

// MARK: - Profile Row Label (visual layer used inside NavigationLink and Button)
struct ProfileRowLabel: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isDestructive ? .red : .black)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundColor(isDestructive ? .red : .black)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(.systemGray3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
