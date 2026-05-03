import SwiftUI

// MARK: - Dashboard View
struct DashboardView: View {
    let onLogout: () -> Void
    @Environment(UserProfile.self) var profile
    @State private var selectedGroup        : CommunityGroup? = nil
    @State private var navigateToCommunities = false
    @State private var showProfile           = false
    @State private var showSearch            = false
    @State private var showOrders            = false

    private var activeOrders: [KnotOrder] {
        profile.orders.filter { $0.status != .complete && $0.status != .cancelled }
    }

    var yourKnots: [CommunityGroup] {
        profile.publicKnots.filter { profile.joinedGroupIDs.contains($0.id) }
        + profile.createdGroups.filter { !profile.joinedGroupIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header — profile circle + name + search icon
                HStack(alignment: .center) {
                    HStack(spacing: 12) {
                        Button(action: { showProfile = true }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 42, height: 42)
                                if let img = profile.profileImage {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(Circle())
                                } else {
                                    Text(profile.initial)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        Text("Hello, \(profile.name).")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Button(action: { showSearch = true }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 24)

                // ── Active Orders Banner ──────────────────────────────
                if !activeOrders.isEmpty {
                    Button(action: { showOrders = true }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 38, height: 38)
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You have \(activeOrders.count) active order\(activeOrders.count == 1 ? "" : "s")")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("Tap to view your orders")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                }

                // Your Knots Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your Knots")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    if yourKnots.isEmpty {
                        Text("You haven't joined any Knots yet.")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(yourKnots.prefix(2)) { group in
                                GroupCard(
                                    group              : group,
                                    isJoined           : profile.joinedGroupIDs.contains(group.id),
                                    isAdmin            : group.adminName == profile.name,
                                    hasPendingRequests : (group.adminName == profile.name || group.coAdminNames.contains(profile.name)) && !(profile.joinRequests[group.id]?.filter { $0.status == .pending }.isEmpty ?? true)
                                ) { selectedGroup = group }
                            }
                        }
                        if yourKnots.count > 2 {
                            HStack {
                                Spacer()
                                Button(action: {
                                    profile.pendingKnotsViewMode = .yours
                                    profile.selectedTab = .groups
                                }) {
                                    Text("See more")
                                        .font(.caption).foregroundColor(.gray).underline()
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1))
                .padding(.horizontal)

                // Available Knots Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Available Knots")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(profile.publicKnots.filter { !profile.joinedGroupIDs.contains($0.id) }.prefix(2)) { group in
                            GroupCard(group: group) {
                                selectedGroup = group
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button(action: { navigateToCommunities = true }) {
                            Text("See more")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .underline()
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1))
                .padding(.horizontal)

                // Alerts Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("Alerts")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    VStack(spacing: 0) {
                        ForEach(profile.announcements.prefix(3)) { announcement in
                            AnnouncementRow(announcement: announcement)
                            if announcement.id != profile.announcements.prefix(3).last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 1))

                    HStack {
                        Spacer()
                        Button(action: { profile.selectedTab = .alerts }) {
                            Text("See more")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .underline()
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1))
                .padding(.horizontal)
            }
            .padding(.bottom, 100)
        }
        .background(Color(.systemGray6).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToCommunities) {
            CommunitiesView().environment(profile)
        }
        .sheet(item: $selectedGroup) { group in KnotDetailView(group: group).environment(profile) }
        .sheet(isPresented: $showProfile) { ProfileView(onLogout: onLogout).environment(profile) }
        .sheet(isPresented: $showSearch) { SearchView().environment(profile) }
        .sheet(isPresented: $showOrders) { NavigationStack { MyOrdersView() }.environment(profile) }
        .task { await profile.loadOrders() }
    }
}

#Preview {
    NavigationStack {
        DashboardView(onLogout: {})
            .environment(UserProfile(name: "Ruhaan"))
    }
}
