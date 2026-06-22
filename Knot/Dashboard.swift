import SwiftUI

// MARK: - Dashboard View
struct DashboardView: View {
    let onLogout: () -> Void
    @Environment(UserProfile.self) var profile
    @State private var selectedGroup        : CommunityGroup? = nil
    @State private var showProfile           = false
    @State private var showSearch            = false
    @State private var showOrders            = false
    @State private var showWelcome           = false

    private var activeOrders: [KnotOrder] {
        profile.orders.filter { $0.status != .complete && $0.status != .cancelled }
    }

    var yourKnots: [CommunityGroup] {
        profile.publicKnots.filter { profile.joinedGroupIDs.contains($0.id) }
        + profile.createdGroups
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
                                    .fill(Color.knotAccent)
                                    .frame(width: 42, height: 42)
                                if let img = profile.profileImage {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(Circle())
                                } else {
                                    Text(profile.initial)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color(.systemBackground))
                                }
                            }
                        }
                        Text("Hello, \(profile.name).")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Button(action: { showSearch = true }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(Color.knotWell)
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
                                    .fill(Color.knotAccent)
                                    .frame(width: 38, height: 38)
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.knotOnAccent)
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
                        .background(Color.knotSurface)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.knotBorder, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                }

                // Your Knots Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your Knots")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

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
                                    isAdmin            : group.creatorID == profile.currentUserID,
                                    hasPendingRequests : (profile.currentUserID.map { group.creatorID == $0 || group.coAdminIDs.contains($0) } ?? false) && !(profile.joinRequests[group.id]?.filter { $0.status == .pending }.isEmpty ?? true)
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
                                        .font(.caption).foregroundColor(.secondary).underline()
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.knotSurface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.knotBorder, lineWidth: 1))
                .padding(.horizontal)

                // Available Knots Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Available Knots")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(profile.publicKnots.filter { !profile.joinedGroupIDs.contains($0.id) }.prefix(2)) { group in
                            GroupCard(group: group) {
                                selectedGroup = group
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button(action: { profile.selectedTab = .groups }) {
                            Text("See more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .underline()
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.knotSurface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.knotBorder, lineWidth: 1))
                .padding(.horizontal)

                // Alerts Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Alerts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(profile.announcements.prefix(3)) { announcement in
                            AnnouncementRow(announcement: announcement)
                            if announcement.id != profile.announcements.prefix(3).last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.knotSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotBorder, lineWidth: 1))

                    HStack {
                        Spacer()
                        Button(action: { profile.selectedTab = .alerts }) {
                            Text("See more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .underline()
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.knotSurface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.knotBorder, lineWidth: 1))
                .padding(.horizontal)
            }
            .padding(.bottom, 100)
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $selectedGroup) { group in KnotDetailView(group: group).environment(profile) }
        .sheet(isPresented: $showProfile) { ProfileView(onLogout: onLogout).environment(profile) }
        .sheet(isPresented: $showSearch) { SearchView().environment(profile) }
        .sheet(isPresented: $showOrders) { NavigationStack { MyOrdersView() }.environment(profile) }
        .sheet(isPresented: $showWelcome) { WelcomeToKnotSheet(isPresented: $showWelcome) }
        .task { await profile.loadOrders() }
        .onChange(of: profile.hasSeenWelcome) { _, seen in
            // Show the welcome sheet exactly once per account (state stored in Supabase),
            // regardless of which device the user signs in on.
            if !seen && !showWelcome {
                showWelcome = true
                profile.markWelcomeSeen()
            }
        }
        .onAppear {
            // Also handle the case where the profile was already loaded before this view appeared
            // (e.g. tab switch back to Home after first sign-in).
            if !profile.hasSeenWelcome && !showWelcome && !profile.name.isEmpty {
                showWelcome = true
                profile.markWelcomeSeen()
            }
        }
    }
}

// MARK: - Welcome to Knot Sheet

struct WelcomeToKnotSheet: View {
    @Binding var isPresented: Bool

    private let features: [(icon: String, title: String, description: String)] = [
        ("person.3.fill",      "Knots",    "Join or create groups for your neighbourhood, school, or community."),
        ("tag.fill",           "Hub",      "Buy and sell items locally — only within the Knots you belong to."),
        ("bell.fill",          "Alerts",   "Stay informed with announcements from your Knots and admins."),
        ("message.fill",       "Messages", "Chat directly with members across your communities."),
    ]

    var body: some View {
        VStack(spacing: 0) {

            // Handle
            Capsule()
                .fill(Color.knotBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 32) {

                    // Header
                    VStack(spacing: 12) {
                        Text("Welcome to Knot")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Your local community, all in one place.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)

                    // Feature list
                    VStack(spacing: 0) {
                        ForEach(features, id: \.title) { feature in
                            HStack(alignment: .top, spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.knotAccent)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: feature.icon)
                                        .font(.system(size: 17))
                                        .foregroundColor(Color.knotOnAccent)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feature.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text(feature.description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal)

                            if feature.title != features.last?.title {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 1))
                    .padding(.horizontal)

                    // CTA
                    Button(action: { isPresented = false }) {
                        Text("Get Started")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.knotAccent)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color.knotBackground.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack {
        DashboardView(onLogout: {})
            .environment(UserProfile(name: "Ruhaan"))
    }
}
