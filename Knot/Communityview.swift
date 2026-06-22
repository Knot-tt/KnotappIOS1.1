import SwiftUI

// MARK: - Communities (Knots) View
struct CommunitiesView: View {
    @Environment(UserProfile.self) var profile
    @State private var searchText         = ""
    @FocusState private var isSearchFocused: Bool
    @State private var viewMode           : GroupViewMode = .all
    @State private var selectedCategories : Set<String>   = []
    @State private var filterAgeGroup     : AgeGroup?     = nil
    @State private var filterMaxSize      : Int?          = nil
    @State private var detailGroup        : CommunityGroup? = nil
    @State private var manageGroup        : CommunityGroup? = nil
    @State private var showFilterSheet    = false
    @State private var showCreateGroup    = false

    // All public knots from Supabase + any user-created knots not yet in the public list
    var allGroups: [CommunityGroup] {
        let publicIDs = Set(profile.publicKnots.map(\.id))
        let extraJoined = profile.createdGroups.filter { !publicIDs.contains($0.id) }
        return profile.publicKnots + extraJoined
    }

    var displayedGroups: [CommunityGroup] {
        let base: [CommunityGroup]
        switch viewMode {
        case .all:       base = allGroups
        case .yours:     base = allGroups.filter { profile.joinedGroupIDs.contains($0.id) }
        case .manage:    base = profile.createdGroups
        case .requested: base = allGroups.filter { profile.requestedGroupIDs.contains($0.id) }
        case .events:    base = allGroups.filter { $0.isEvent }
        }

        var result = searchText.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText) ||
            $0.location.localizedCaseInsensitiveContains(searchText)
        }
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }
        if let ag = filterAgeGroup {
            result = result.filter { $0.ageGroup == ag }
        }
        if let maxSize = filterMaxSize {
            result = result.filter { $0.memberCount <= maxSize }
        }
        return result
    }

    var filtersActive: Bool { !selectedCategories.isEmpty || filterAgeGroup != nil || filterMaxSize != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {

                // ── Header: "Knots" + dropdown ───────────────────────────
                HStack {
                    Menu {
                        ForEach(GroupViewMode.allCases, id: \.self) { mode in
                            Button(action: { viewMode = mode }) {
                                if viewMode == mode { Label(mode.rawValue, systemImage: "checkmark") }
                                else { Text(mode.rawValue) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Knots")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.knotMuted)
                        }
                    }
                    Spacer()
                    // Create button — top-right, same placement as the Hub tab.
                    Button(action: { showCreateGroup = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color.knotWell)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, viewMode == .all ? 6 : 2)

                // Active mode pill
                if viewMode != .all {
                    HStack {
                        Label(viewMode.rawValue, systemImage: modePillIcon)
                            .font(.caption).fontWeight(.medium).foregroundColor(Color.knotOnAccent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.knotAccent).cornerRadius(10)
                        Spacer()
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                }

                // ── Search + Filter ──────────────────────────────────────
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search Knots", text: $searchText)
                            .autocapitalization(.none)
                            .focused($isSearchFocused)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(Color.knotMuted)
                            }
                        }
                    }
                    .padding(10).background(Color.knotWell).cornerRadius(12)
                    .knotSurfaceBorder(cornerRadius: 12)

                    Button(action: { showFilterSheet = true }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18))
                            .foregroundColor(filtersActive ? Color.knotOnAccent : .primary)
                            .padding(10)
                            .background(filtersActive ? Color.knotAccent : Color.knotWell)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)

                // ── Content ──────────────────────────────────────────────
                if viewMode == .events && displayedGroups.isEmpty {
                    eventsPlaceholder
                } else if displayedGroups.isEmpty {
                    // Show a spinner — not "no knots" — until the first load lands.
                    if profile.hasLoadedKnots {
                        emptyState
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(displayedGroups) { group in
                                GroupCard(
                                    group              : group,
                                    isJoined           : profile.joinedGroupIDs.contains(group.id),
                                    isRequested        : profile.requestedGroupIDs.contains(group.id),
                                    isAdmin            : (profile.currentUserID.map { group.creatorID == $0 || group.coAdminIDs.contains($0) } ?? false),
                                    hasPendingRequests : (profile.currentUserID.map { group.creatorID == $0 || group.coAdminIDs.contains($0) } ?? false) && !(profile.joinRequests[group.id]?.filter { $0.status == .pending }.isEmpty ?? true)
                                ) {
                                    if viewMode == .manage { manageGroup = group }
                                    else { detailGroup = group }
                                }
                            }
                        }
                        .padding(.horizontal).padding(.top, 4).padding(.bottom, 100)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            // Tap anywhere outside the search bar dismisses the keyboard.
            // A downward swipe on non-scroll areas (header, empty state) also dismisses.
            .contentShape(Rectangle())
            .onTapGesture { isSearchFocused = false }
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation.height > 20 { isSearchFocused = false }
                    }
            )
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
        .sheet(item: $detailGroup)  { KnotDetailView(group: $0).environment(profile) }
        .onAppear {
            if let mode = profile.pendingKnotsViewMode {
                viewMode = mode
                profile.pendingKnotsViewMode = nil
            }
        }
        .task {
            await profile.loadKnots()
        }
        .task(id: profile.selectedTab) {
            guard profile.selectedTab == .groups else { return }
            await profile.loadKnots()
            while !Task.isCancelled && profile.selectedTab == .groups {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, profile.selectedTab == .groups else { break }
                await profile.loadKnots()
            }
        }
        .onChange(of: profile.pendingKnotsViewMode) { _, mode in
            if let mode {
                viewMode = mode
                profile.pendingKnotsViewMode = nil
            }
        }
        .sheet(item: $manageGroup)  { ManageGroupView(groupID: $0.id).environment(profile) }
        .sheet(isPresented: $showFilterSheet) {
            KnotFilterSheetView(
                selectedCategories: $selectedCategories,
                filterAgeGroup    : $filterAgeGroup,
                filterMaxSize     : $filterMaxSize
            )
        }
        .sheet(isPresented: $showCreateGroup) { CreateGroupView().environment(profile) }
    }

    private var modePillIcon: String {
        switch viewMode {
        case .all: return "globe"; case .yours: return "person.2.fill"
        case .manage: return "star.fill"; case .requested: return "clock.fill"; case .events: return "calendar"
        }
    }
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: emptyIcon).font(.system(size: 48)).foregroundColor(Color.knotMuted)
            Text(emptyTitle).font(.headline).foregroundColor(Color.knotMuted)
            Text(emptySubtitle).font(.caption).foregroundColor(Color.knotMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    private var eventsPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.clock").font(.system(size: 48)).foregroundColor(Color.knotMuted)
            Text("Knot Events").font(.headline).foregroundColor(Color.knotMuted)
            Text("Events will appear here once the feature is live.")
                .font(.caption).foregroundColor(Color.knotMuted).multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    private var emptyIcon: String {
        switch viewMode {
        case .all: return "magnifyingglass"; case .yours: return "person.2"
        case .manage: return "plus.circle"; case .requested: return "clock"; case .events: return "calendar"
        }
    }
    private var emptyTitle: String {
        switch viewMode {
        case .all: return "No Knots found"; case .yours: return "No Knots joined yet"
        case .manage: return "No Knots created yet"; case .requested: return "No pending requests"; case .events: return "No events"
        }
    }
    private var emptySubtitle: String {
        switch viewMode {
        case .all: return "Try a different search or filter"
        case .yours: return "Browse All Knots to find and join one"
        case .manage: return "Tap + to create your first Knot"
        case .requested: return "Knots you request to join will appear here"
        case .events: return ""
        }
    }
}

// MARK: - Group Card
struct GroupCard: View {
    let group      : CommunityGroup
    var isJoined           : Bool = false
    var isRequested        : Bool = false
    var isAdmin            : Bool = false
    var hasPendingRequests : Bool = false
    let onMoreInfo         : () -> Void

    private let cardHeight  : CGFloat = 185
    private let infoPercent : CGFloat = 0.33

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // Cover photo or fallback icon
                Group {
                    if let urlStr = group.imageURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure, .empty:
                                Color.knotSurface
                                    .overlay(Image(systemName: group.imageName).font(.system(size: 48)).foregroundColor(.primary))
                            @unknown default:
                                Color.knotSurface
                            }
                        }
                    } else {
                        Color.knotSurface
                            .overlay(Image(systemName: group.imageName).font(.system(size: 48)).foregroundColor(.primary))
                    }
                }
                .frame(height: cardHeight * (1 - infoPercent))
                .clipped()

                Rectangle()
                    .fill(Color.knotBorder)
                    .frame(height: 1.5)

                // Info strip — matches ShopItemCard exactly (56pt fixed height)
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(group.name).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                            .lineLimit(1)
                        if isAdmin {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        if isJoined {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                        } else if isRequested {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("by \(group.adminName)").font(.caption2).foregroundColor(Color.knotMuted)
                        .lineLimit(1)

                    if group.isPaid {
                        Text(group.price == 0 ? "Free" : "$\(group.price)")
                            .font(.caption2).foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight * infoPercent)
                .background(Color.knotSurface)
            }

            // Event badge top-right
            if group.isEvent {
                HStack {
                    Spacer()
                    Text("Event").font(.caption2).fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.knotAccent).cornerRadius(6)
                        .padding(6)
                }
            }
        }
        .frame(height: cardHeight + 1.5)
        .cornerRadius(14)
        // Adaptive 1pt stroke — `separator` is light-grey in light mode and a faint
        // off-black in dark mode, so the card stays distinct from the page background
        // in both. Shadow stays for depth in light mode (invisible in dark, fine).
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        .overlay(alignment: .topTrailing) {
            if hasPendingRequests {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .offset(x: 5, y: -5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onMoreInfo)
    }
}

// MARK: - Knot Detail View
struct KnotDetailView: View {
    let group: CommunityGroup
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile
    @State private var showAdminActions = false
    @State private var showUserProfile  : String? = nil  // admin name
    @State private var showMapPopup     = false
    @State private var showSendAlert    = false
    @State private var showManage              = false
    @State private var showLeaveConfirm        = false
    @State private var showDeleteConfirm       = false
    @State private var showTransferCreator     = false   // creator-leave flow
    @State private var selectedNewCreator    : String? = nil
    @State private var isJoining               = false
    @State private var joinError               : String? = nil
    @State private var showRateSheet           = false

    /// Always reads the freshest copy from profile so member count etc. stay live.
    var liveGroup: CommunityGroup {
        let gid = group.id
        if let g = profile.publicKnots.first(where: { $0.id == gid }) { return g }
        if let g = profile.createdGroups.first(where: { $0.id == gid }) { return g }
        return group
    }

    var isRequested : Bool { profile.requestedGroupIDs.contains(liveGroup.id) }
    var isJoined    : Bool { profile.joinedGroupIDs.contains(liveGroup.id) }
    var isCreator   : Bool {
        // UUID compare — survives profile renames. Name compare is a fallback for
        // legacy data where creatorID wasn't populated yet.
        if let cid = liveGroup.creatorID, let me = profile.currentUserID {
            return cid == me
        }
        return liveGroup.adminName == profile.name
    }
    var isCoAdmin   : Bool {
        // UUID compare — name renames can't grant or revoke admin power.
        guard let me = profile.currentUserID else { return false }
        return liveGroup.coAdminIDs.contains(me)
    }
    var isAdmin     : Bool { isCreator || isCoAdmin }

    /// Whether the current user is already connected to the knot admin (creator).
    private var adminIsConnected: Bool {
        guard let me = profile.currentUserID, let cid = liveGroup.creatorID else { return false }
        return profile.dbConnections.contains { c in
            c.status == "accepted" &&
            ((c.requesterId == me && c.recipientId == cid) ||
             (c.requesterId == cid && c.recipientId == me))
        }
    }

    /// Whether there is an outgoing pending connection request to the knot admin.
    private var adminConnectionPending: Bool {
        guard let me = profile.currentUserID, let cid = liveGroup.creatorID else { return false }
        return profile.dbConnections.contains { c in
            c.status == "pending" && c.requesterId == me && c.recipientId == cid
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Banner
                    ZStack {
                        if let urlStr = liveGroup.imageURL, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                        .frame(height: 220).clipped()
                                case .failure, .empty:
                                    Rectangle().fill(Color.knotSurface).frame(height: 220)
                                        .overlay(Image(systemName: liveGroup.imageName).font(.system(size: 80)).foregroundColor(.primary))
                                @unknown default:
                                    Rectangle().fill(Color.knotSurface).frame(height: 220)
                                }
                            }
                            .frame(height: 220)
                        } else {
                            Rectangle().fill(Color.knotSurface).frame(height: 220)
                            Image(systemName: liveGroup.imageName).font(.system(size: 80)).foregroundColor(.primary)
                        }
                        if liveGroup.isEvent {
                            VStack {
                                HStack {
                                    Spacer()
                                    Text("Knot Event").font(.caption).fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.knotAccent).cornerRadius(8)
                                        .padding(12)
                                }
                                Spacer()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {

                        // Name
                        Text(liveGroup.name).font(.system(size: 26, weight: .bold)).foregroundColor(.primary)

                        // Average star rating (rounded to nearest 0.5) + rater count
                        KnotStarRow(rating: liveGroup.roundedRating, count: liveGroup.ratingCount)

                        // Admin row — tappable
                        Button(action: { if !isAdmin { showAdminActions = true } }) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(Color.knotAccent).frame(width: 28, height: 28)
                                    Text(String(liveGroup.adminName.prefix(1)))
                                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Created by").font(.caption).foregroundColor(.secondary)
                                    Text(liveGroup.adminName).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                                }
                                if !isAdmin {
                                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color.knotMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Metadata chips
                        FlowLayout(spacing: 8) {
                            metaChip(icon: "tag", text: liveGroup.category)
                            metaChip(icon: "person.2", text: "\(liveGroup.memberCount) members")
                            Button(action: { showMapPopup = true }) {
                                let canSeeFullLocation = isJoined || isAdmin
                                let displayLocation: String = {
                                    if liveGroup.hideLocationFromNonMembers && !canSeeFullLocation {
                                        // Show city only (last meaningful component)
                                        return liveGroup.location.components(separatedBy: ", ").last ?? liveGroup.location
                                    }
                                    return liveGroup.location
                                }()
                                metaChip(
                                    icon: liveGroup.hideLocationFromNonMembers && !canSeeFullLocation
                                        ? "mappin.slash" : "mappin.and.ellipse",
                                    text: displayLocation
                                )
                            }
                            .buttonStyle(.plain)
                            if let max = liveGroup.maxMembers {
                                metaChip(icon: "person.badge.plus", text: "Max \(max)")
                            }
                            if liveGroup.ageGroup != .any {
                                metaChip(icon: "person.crop.circle", text: ageLabel(liveGroup))
                            }
                            if liveGroup.requiresApproval {
                                metaChip(icon: "lock.fill", text: "Approval required", color: .orange)
                            }
                        }

                        Divider()

                        Text("About this Knot").font(.headline).foregroundColor(.primary)
                        Text(liveGroup.description).font(.body).foregroundColor(.primary.opacity(0.85)).lineSpacing(5)

                        // ── Join / Status ────────────────────────────────
                        if isAdmin {
                            VStack(spacing: 10) {
                            Label(isCreator ? "You manage this Knot" : "You're an admin", systemImage: "star.fill")
                                .fontWeight(.semibold).foregroundColor(Color.knotMuted)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.knotWell).cornerRadius(12)
                            Button(action: { showManage = true }) {
                                Label("Manage Knot", systemImage: "gearshape.fill")
                                    .fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.knotAccent).cornerRadius(12)
                            }
                            if isAdmin {
                            Button(action: { showSendAlert = true }) {
                                Label("Send Alert to Members", systemImage: "bell.badge.fill")
                                    .fontWeight(.semibold).foregroundColor(.primary)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.knotSurface).cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotAccent, lineWidth: 1.5))
                            }
                            }
                            }
                        } else if isJoined {
                            Label("You're a member", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold).foregroundColor(.green)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.green.opacity(0.1)).cornerRadius(12)
                        } else if isRequested {
                            Label("Requested", systemImage: "clock.fill")
                                .fontWeight(.semibold).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.knotWell).cornerRadius(12)
                        } else {
                            Button(action: {
                                guard !isJoining else { return }
                                isJoining = true
                                joinError = nil
                                Task {
                                    do {
                                        try await profile.joinKnot(liveGroup)
                                        await MainActor.run { isJoining = false }
                                    } catch {
                                        await MainActor.run {
                                            isJoining = false
                                            joinError = error.localizedDescription
                                        }
                                    }
                                }
                            }) {
                                let label: String = liveGroup.requiresApproval ? "Request to Join" : "Join Knot"
                                ZStack {
                                    if isJoining {
                                        ProgressView().tint(Color.knotOnAccent)
                                    } else {
                                        Text(label)
                                            .fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                                    }
                                }
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.knotAccent).cornerRadius(12)
                            }
                            .disabled(isJoining)
                            if let err = joinError {
                                Text(err).font(.caption).foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        // ── Group chat — members + admins only ───────────
                        // Non-members can't message the knot. They have to join first.
                        if isJoined || isAdmin {
                            Button(action: {
                                let knotID   = liveGroup.id
                                let knotName = liveGroup.name
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    profile.openKnotGroupChat(knotID: knotID, knotName: knotName)
                                }
                            }) {
                                Text("Open Knot Group Chat")
                                    .fontWeight(.semibold).foregroundColor(.primary)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.knotSurface).cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotAccent, lineWidth: 1.5))
                            }
                        }
                        // ── Leave / Delete Knot ──────────────────────────
                        if isJoined || isAdmin {
                            Button(action: {
                                if isCreator {
                                    // Always load fresh members — local memberCount can be stale
                                    Task { await profile.loadKnotMembers(for: liveGroup.id) }
                                    showTransferCreator = true
                                } else {
                                    showLeaveConfirm = true
                                }
                            }) {
                                Text("Leave Knot")
                                    .fontWeight(.semibold).foregroundColor(.red)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.red.opacity(0.08)).cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4), lineWidth: 1.5))
                            }
                        }
                        if isCreator {
                            Button(action: { showDeleteConfirm = true }) {
                                Label("Delete Knot", systemImage: "trash.fill")
                                    .fontWeight(.semibold).foregroundColor(.red)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.red.opacity(0.12)).cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.top, 20).padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle(liveGroup.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                // 3-dot menu — only members/admins (people "part of" the knot) can rate.
                if isJoined || isAdmin {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showRateSheet = true } label: {
                                Label("Rate this Knot", systemImage: "star")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showRateSheet) {
                RateKnotSheet(group: liveGroup).environment(profile)
            }
            .sheet(isPresented: $showManage) {
                ManageGroupView(groupID: liveGroup.id).environment(profile)
            }
            .confirmationDialog(liveGroup.adminName, isPresented: $showAdminActions, titleVisibility: .visible) {
                Button("Message \(liveGroup.adminName)") {
                    // Prefer the UUID-based opener — name-based search fails silently
                    // on rename/casing and could hit the wrong person.
                    if let cid = liveGroup.creatorID {
                        profile.openConversation(withUserID: cid,
                                                 name: liveGroup.adminName,
                                                 sourceKnotID: liveGroup.id,
                                                 sourceKnotName: liveGroup.name)
                    } else {
                        profile.openConversation(with: liveGroup.adminName,
                                                 sourceKnotID: liveGroup.id,
                                                 sourceKnotName: liveGroup.name)
                    }
                    dismiss()
                }
                Button("View Profile") { showUserProfile = liveGroup.adminName }
                if !isAdmin && !adminIsConnected && !adminConnectionPending {
                    Button("Add as Connection") {
                        if let cid = liveGroup.creatorID {
                            Task { await profile.sendConnectionRequest(to: cid) }
                        }
                    }
                } else if !isAdmin && adminConnectionPending {
                    Button("Request Sent") {}  // informational — disabled appearance
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("What would you like to do?") }
            .sheet(item: $showUserProfile) { name in UserProfileView(name: name, userID: liveGroup.creatorID).environment(profile) }
            .sheet(isPresented: $showSendAlert) { AdminSendAlertView(group: liveGroup).environment(profile) }
            .confirmationDialog("Leave Knot", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                Button("Leave Knot", role: .destructive) {
                    // Don't dismiss — stay on the knot detail so the user can see
                    // it as a "joinable" knot now (Leave button → Join/Request).
                    Task { await profile.leaveKnot(groupID: liveGroup.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You'll be removed from this Knot. You can rejoin from this screen if it's still public.") }
            .sheet(isPresented: $showTransferCreator) {
                TransferCreatorSheet(
                    group: liveGroup,
                    selectedNewCreator: $selectedNewCreator,
                    onConfirm: { newCreatorName in
                        // Look up UUID from the LIVE group (publicKnots updated by loadKnotMembers)
                        let live = profile.publicKnots.first(where: { $0.id == liveGroup.id })
                                ?? profile.createdGroups.first(where: { $0.id == liveGroup.id })
                                ?? liveGroup
                        guard let newCreatorID = live.memberUUIDs[newCreatorName] else {
                            print("[KnotDetailView] TransferCreator: NO UUID for \(newCreatorName), keys=\(live.memberUUIDs.keys)")
                            return
                        }
                        Task {
                            await profile.transferCreatorAndLeave(groupID: liveGroup.id, newCreatorID: newCreatorID)
                        }
                        dismiss()
                    },
                    onDelete: {
                        Task { await profile.deleteKnot(groupID: liveGroup.id) }
                        dismiss()
                    }
                )
                .environment(profile)
            }
            .confirmationDialog("Delete Knot", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Knot", role: .destructive) {
                    Task { await profile.deleteKnot(groupID: liveGroup.id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This is irreversible. The knot, its group chat, and all membership data will be permanently deleted. An alert will be sent to all members.") }
            .confirmationDialog(liveGroup.location, isPresented: $showMapPopup, titleVisibility: .visible) {
                Button("View in Maps") {
                    let query = liveGroup.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "maps://?q=\(query)") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task(id: liveGroup.id) {
                // Refresh members + memberCount whenever this view opens (or the knot id changes)
                if isAdmin { await profile.loadKnotMembers(for: liveGroup.id) }
            }
        }
    }

    private func metaChip(icon: String, text: String, color: Color = .gray) -> some View {
        Label(text, systemImage: icon)
            .font(.caption).foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.knotSurface).cornerRadius(10)
    }

    private func ageLabel(_ g: CommunityGroup) -> String {
        g.ageGroup == .custom ? "\(g.minAge)–\(g.maxAge)" : g.ageGroup.rawValue
    }
}

// MARK: - Knot Star Rating (read-only display)

/// Renders a 5-star template for a knot's average rating. `rating` is expected
/// to already be snapped to the nearest 0.5 (see `CommunityGroup.roundedRating`).
/// Filled / half stars use the app's accent green; empties are a faint accent.
struct KnotStarRow: View {
    let rating: Double
    let count: Int
    var starSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { position in
                Image(systemName: symbol(for: position))
                    .font(.system(size: starSize))
                    .foregroundColor(isEmpty(position) ? Color.knotAccent.opacity(0.25)
                                                       : Color.knotAccent)
            }
            Text("(\(count))")
                .font(.system(size: max(11, starSize - 3)))
                .foregroundColor(.secondary)
                .padding(.leading, 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 0
            ? "Not rated yet"
            : "Rated \(String(format: "%.1f", rating)) out of 5 stars by \(count) \(count == 1 ? "person" : "people")")
    }

    private func symbol(for position: Int) -> String {
        let p = Double(position)
        if rating >= p { return "star.fill" }
        if rating >= p - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    private func isEmpty(_ position: Int) -> Bool {
        rating < Double(position) - 0.5
    }
}

// MARK: - Rate Knot Sheet (interactive)

/// Tap-to-pick star rating. Pre-fills the user's existing rating if they've
/// already rated, so submitting again updates rather than duplicates.
struct RateKnotSheet: View {
    let group: CommunityGroup
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    @State private var selected     = 0
    @State private var existing     : Int? = nil
    @State private var isSubmitting = false
    @State private var errorText    : String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Rate this Knot")
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.primary)
                    Text(group.name)
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= selected ? "star.fill" : "star")
                            .font(.system(size: 40))
                            .foregroundColor(i <= selected ? Color.knotAccent
                                                           : Color.knotAccent.opacity(0.25))
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.12)) { selected = i }
                            }
                            .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    }
                }

                Text(selected == 0 ? "Tap a star to rate" : "\(selected) of 5 stars")
                    .font(.footnote).foregroundColor(.secondary)

                if let errorText {
                    Text(errorText).font(.caption).foregroundColor(.red)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                Spacer()

                Button(action: submit) {
                    ZStack {
                        if isSubmitting {
                            ProgressView().tint(Color.knotOnAccent)
                        } else {
                            Text(existing == nil ? "Submit" : "Update Rating")
                                .fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(selected == 0 ? Color.knotAccent.opacity(0.4) : Color.knotAccent)
                    .cornerRadius(12)
                }
                .disabled(selected == 0 || isSubmitting)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                existing = try? await KnotRatingService.fetchMine(knotID: group.id)
                if let e = existing { selected = e }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard selected > 0, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task {
            do {
                try await profile.submitKnotRating(knotID: group.id, rating: selected)
                isSubmitting = false
                dismiss()
            } catch {
                isSubmitting = false
                errorText = error.localizedDescription
            }
        }
    }
}

// Make String Identifiable for sheet(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - User Profile View (viewing another user)
struct UserProfileView: View {
    let name        : String
    var userID      : UUID? = nil
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    @State private var loadedProfile : DBProfile? = nil
    @State private var listingCount  : Int? = nil
    @State private var knotCount     : Int? = nil
    @State private var showReportConfirm = false
    @State private var reportSubmitted   = false
    @State private var showRemoveConfirm = false

    private var effectivePrivacy: UserProfile.OtherUserPrivacy {
        guard let p = loadedProfile else { return profile.privacy(for: name) }
        return UserProfile.OtherUserPrivacy(
            isPrivate    : p.isPrivate,
            showKnots    : p.showKnots,
            showListings : p.showListings
        )
    }
    private var isConnected: Bool {
        guard let me = profile.currentUserID else { return false }
        // Prefer UUID-based check (accurate even right after connection removal)
        if let uid = userID {
            return profile.dbConnections.contains { c in
                c.status == "accepted" &&
                ((c.requesterId == me && c.recipientId == uid) ||
                 (c.requesterId == uid && c.recipientId == me))
            }
        }
        // Fall back to name check when no UUID is available
        return profile.connections.contains(name)
    }

    /// UUID-based pending check — reliable immediately after sending a request,
    /// without waiting for `connectionProfiles` to be hydrated with the target's name.
    private var isPendingConnection: Bool {
        guard let me = profile.currentUserID else { return false }
        if let uid = userID {
            return profile.dbConnections.contains { c in
                c.status == "pending" && c.requesterId == me && c.recipientId == uid
            }
        }
        return profile.sentConnectionRequests.contains(name)
    }
    private var showRestricted: Bool { effectivePrivacy.isPrivate && !isConnected }

    var knots: [CommunityGroup] {
        profile.publicKnots.filter { $0.adminName == name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar
                    ZStack {
                        Circle().fill(Color.knotAccent).frame(width: 90, height: 90)
                        if let urlString = loadedProfile?.profileImage,
                           let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                        .frame(width: 90, height: 90)
                                        .clipShape(Circle())
                                } else {
                                    Text(String(name.prefix(1)).uppercased())
                                        .font(.system(size: 36, weight: .semibold))
                                        .foregroundColor(Color.knotOnAccent)
                                }
                            }
                        } else {
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(Color.knotOnAccent)
                        }
                    }
                    .padding(.top, 32)

                    Text(name).font(.system(size: 22, weight: .bold))

                    // Bio
                    let bio = loadedProfile?.bio ?? ""
                    if !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }

                    // Stats strip
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("—").font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            Text("Connections").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 32)
                        VStack(spacing: 2) {
                            if effectivePrivacy.showListings {
                                Text(listingCount.map(String.init) ?? "—")
                                    .font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            } else {
                                Text("—").font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            }
                            Text("Listings").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 32)
                        VStack(spacing: 2) {
                            if effectivePrivacy.showKnots {
                                Text(knotCount.map(String.init) ?? "—")
                                    .font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            } else {
                                Text("—").font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                            }
                            Text("Knots").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    .background(Color.knotSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotBorder, lineWidth: 1))
                    .padding(.horizontal)

                    if showRestricted {
                        // Private account — restricted view
                        VStack(spacing: 8) {
                            Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(Color.knotMuted)
                            Text("This account is private")
                                .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.knotMuted)
                            Text("Connect with \(name) to see their profile.")
                                .font(.caption).foregroundColor(Color.knotMuted)
                                .multilineTextAlignment(.center).padding(.horizontal, 32)
                            if !isPendingConnection {
                                Button(action: {
                                    if let uid = userID {
                                        Task { await profile.sendConnectionRequest(to: uid) }
                                    }
                                }) {
                                    Text("Add as Connection")
                                        .fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                                        .padding(.horizontal, 24).padding(.vertical, 10)
                                        .background(Color.knotAccent).cornerRadius(12)
                                }
                            } else {
                                Text("Request Sent")
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        // Primary actions — surfaced here instead of buried in the ⋯ menu.
                        HStack(spacing: 12) {
                            if isConnected || !effectivePrivacy.isPrivate {
                                Button(action: messageUser) {
                                    Label("Message", systemImage: "message.fill")
                                        .fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                                        .background(Color.knotAccent).cornerRadius(12)
                                }
                            }
                            connectionActionButton
                        }
                        .padding(.horizontal)

                        Divider().padding(.horizontal)

                        // Their listings
                        let theirListings = profile.allListings.filter { $0.sellerName == name }
                        if !theirListings.isEmpty && effectivePrivacy.showListings {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Listings").font(.headline).padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(theirListings) { listing in
                                            VStack(alignment: .leading, spacing: 4) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 10).fill(Color.knotSurface)
                                                        .frame(width: 100, height: 80)
                                                    if let img = listing.images.first {
                                                        Image(uiImage: img).resizable().scaledToFill()
                                                            .frame(width: 100, height: 80).clipped().cornerRadius(10)
                                                    } else {
                                                        Image(systemName: listing.type.icon)
                                                            .font(.system(size: 28)).foregroundColor(Color.knotMuted)
                                                    }
                                                }
                                                Text(listing.name).font(.caption).fontWeight(.semibold)
                                                    .lineLimit(1).frame(width: 100, alignment: .leading)
                                                Text(listing.price == 0 ? "Free" : "$\(listing.price)")
                                                    .font(.caption2).foregroundColor(listing.price == 0 ? .green : .gray)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        Divider().padding(.horizontal)

                        // Their knots
                        if effectivePrivacy.showKnots {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Knots").font(.headline).padding(.horizontal)

                            if knots.isEmpty {
                                Text("Not part of any Knots yet.")
                                    .font(.caption).foregroundColor(.secondary).padding(.horizontal)
                            } else {
                                ForEach(knots) { knot in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8).fill(Color.knotSurface).frame(width: 40, height: 40)
                                            Image(systemName: knot.imageName).font(.system(size: 18)).foregroundColor(.primary)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(knot.name).font(.subheadline).fontWeight(.semibold)
                                            Text(knot.category).font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if knot.adminName == name {
                                            Text("Admin").font(.caption2).foregroundColor(Color.knotOnAccent)
                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                .background(Color.knotAccent).cornerRadius(6)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                        } // if privacy.showKnots
                    }
                }
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .task { await loadProfile() }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                // Message & connection actions now live as buttons in the profile
                // body. The ⋯ menu keeps only the less-common Report / Block actions,
                // and only when we know the target's UUID (can't action by name alone).
                if let uid = userID, uid != profile.currentUserID {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive, action: { showReportConfirm = true }) {
                                Label("Report \(name)", systemImage: "flag.fill")
                            }
                            if profile.blockedUserIDs.contains(uid) {
                                Button(action: {
                                    Task { await profile.unblockUser(userID: uid) }
                                }) {
                                    Label("Unblock \(name)", systemImage: "hand.raised.slash")
                                }
                            } else {
                                Button(role: .destructive, action: {
                                    Task { await profile.blockUser(userID: uid) }
                                }) {
                                    Label("Block \(name)", systemImage: "hand.raised.fill")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Report \(name)?", isPresented: $showReportConfirm, titleVisibility: .visible) {
                Button("Report Inappropriate Behaviour", role: .destructive) { submitReport() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Our team reviews all reports within 24 hours. The user will not be notified.")
            }
            .alert("Report Submitted", isPresented: $reportSubmitted) {
                Button("OK") {}
            } message: {
                Text("Thank you. Our team will review this report within 24 hours.")
            }
            .confirmationDialog("Remove \(name) as a connection?",
                                isPresented: $showRemoveConfirm, titleVisibility: .visible) {
                Button("Remove Connection", role: .destructive) { removeConnection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll no longer be connected. You can send a new request later.")
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private var connectionActionButton: some View {
        if isConnected {
            Button(action: { showRemoveConfirm = true }) {
                Label("Remove", systemImage: "person.fill.xmark")
                    .fontWeight(.semibold).foregroundColor(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Color.red.opacity(0.1)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.35), lineWidth: 1.5))
            }
        } else if isPendingConnection {
            Label("Requested", systemImage: "clock")
                .fontWeight(.semibold).foregroundColor(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color.knotWell).cornerRadius(12)
        } else if userID != nil {
            Button(action: addConnection) {
                Label("Connect", systemImage: "person.badge.plus")
                    .fontWeight(.semibold).foregroundColor(Color.knotAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Color.knotAccent.opacity(0.12)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotAccent, lineWidth: 1.5))
            }
        }
    }

    private func messageUser() {
        dismiss()
        // Delay so this sheet finishes dismissing before we push the chat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            // UUID-based opener is more reliable — name search can hit the wrong
            // person on name collisions.
            if let uid = userID {
                profile.openConversation(withUserID: uid, name: name)
            } else {
                profile.openConversation(with: name)
            }
        }
    }

    private func addConnection() {
        guard let uid = userID else { return }
        Task { await profile.sendConnectionRequest(to: uid) }
    }

    private func removeConnection() {
        Task {
            if let uid = userID {
                await profile.removeConnection(with: uid)
            } else {
                await profile.removeConnection(withName: name)
            }
        }
    }

    private func submitReport() {
        guard let uid = userID else { return }
        Task {
            try? await ReportService.report(userID: uid, reason: "inappropriate_behaviour", details: nil)
            reportSubmitted = true
        }
    }

    private func loadProfile() async {
        // Try UUID first (most reliable)
        if let uid = userID {
            loadedProfile = try? await ProfileService.fetch(userID: uid)
        }
        // Fall back to name search
        if loadedProfile == nil {
            loadedProfile = try? await ProfileService.search(query: name, limit: 1).first
        }

        // Pull accurate stats straight from the server for this user, rather than
        // counting whatever happens to be in the viewer's capped local cache.
        if let uid = userID ?? loadedProfile?.id {
            async let listings = try? ShopService.countActive(sellerID: uid)
            async let knots    = try? KnotService.countMemberships(userID: uid)
            listingCount = await listings ?? 0
            knotCount    = await knots ?? 0
        }
    }
}

// MARK: - Knot Filter Sheet
struct KnotFilterSheetView: View {
    @Binding var selectedCategories : Set<String>
    @Binding var filterAgeGroup     : AgeGroup?
    @Binding var filterMaxSize      : Int?
    @Environment(\.dismiss) var dismiss

    @State private var maxSizeText = ""

    let categories = ["Photography","Food","Fitness","Reading","Gaming","Arts",
                      "Music","Education","Gardening","Entertainment","Technology","Outdoors","Other"]

    var body: some View {
        NavigationStack {
            List {

                // Category
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        FlowLayout(spacing: 10) {
                            ForEach(categories, id: \.self) { cat in
                                let sel = selectedCategories.contains(cat)
                                Button(action: {
                                    if sel { selectedCategories.remove(cat) }
                                    else   { selectedCategories.insert(cat) }
                                }) {
                                    Text(cat).font(.subheadline)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(sel ? Color.knotAccent : Color.knotWell)
                                        .foregroundColor(sel ? Color.knotOnAccent : .primary)
                                        .cornerRadius(20)
                                        .overlay(RoundedRectangle(cornerRadius: 20)
                                            .stroke(sel ? Color.knotAccent : Color.knotBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // Age Group
                Section("Age Group") {
                    Picker("Age Group", selection: $filterAgeGroup) {
                        Text("Any").tag(Optional<AgeGroup>.none)
                        ForEach(AgeGroup.allCases.filter { $0 != .custom }, id: \.self) { ag in
                            Text(ag.rawValue).tag(Optional(ag))
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Knot Size
                Section {
                    Picker("Knot Size", selection: $filterMaxSize) {
                        Text("Any size").tag(Optional<Int>.none)
                        Text("Under 10").tag(Optional(10))
                        Text("Under 25").tag(Optional(25))
                        Text("Under 50").tag(Optional(50))
                        Text("Under 100").tag(Optional(100))
                    }
                    .pickerStyle(.menu)
                } header: { Text("Knot Size") }
                  footer: { Text("Shows Knots with fewer members than selected.") }
            }
            .navigationTitle("Filter Knots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedCategories.removeAll()
                        filterAgeGroup = nil
                        filterMaxSize  = nil
                    }
                    .foregroundColor(noFilters ? .gray : .primary)
                    .disabled(noFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var noFilters: Bool { selectedCategories.isEmpty && filterAgeGroup == nil && filterMaxSize == nil }
}

// MARK: - Admin Send Alert View
struct AdminSendAlertView: View {
    private enum Field: Hashable {
        case title
        case message
    }

    let group: CommunityGroup
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    @State private var alertTitle = ""
    @State private var alertBody  = ""
    @State private var sent       = false
    @State private var selectedImages: [UIImage] = []
    @State private var showPhotoPicker = false
    @State private var isSending = false
    @State private var showSendError = false
    @FocusState private var focusedField: Field?

    private var canSend: Bool {
        !alertTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !alertBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alert Title") {
                    TextField("e.g. Meeting this Saturday", text: $alertTitle)
                        .focused($focusedField, equals: .title)
                }
                Section("Message") {
                    TextEditor(text: $alertBody)
                        .frame(minHeight: 120)
                        .focused($focusedField, equals: .message)
                }
                Section("Photos") {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label(
                            selectedImages.isEmpty ? "Add Photos" : "Add More Photos",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }

                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))

                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                                .shadow(radius: 4)
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Text("\(selectedImages.count) / 5 photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    Button(action: sendAlert) {
                        Text(isSending ? "Sending..." : "Send to \(group.memberCount) Members")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                            .foregroundColor(canSend ? .white : .gray)
                    }
                    .listRowBackground(canSend ? Color.knotAccent : Color.knotSurface)
                    .disabled(!canSend || isSending)
                }
            }
            .navigationTitle("Send Alert")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardOnTap()
            .sheet(isPresented: $showPhotoPicker) {
                MultiImagePicker(maxSelectionCount: 5) { images in
                    showPhotoPicker = false
                    if !images.isEmpty {
                        selectedImages = Array((selectedImages + images).prefix(5))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Alert Sent", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your alert has been sent to members of \(group.name).")
            }
            .alert("Couldn’t Send Alert", isPresented: $showSendError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try again in a moment. If you added photos, try sending fewer photos or sending the alert without photos first.")
            }
        }
    }

    private func sendAlert() {
        guard !isSending else { return }
        let t   = alertTitle.trimmingCharacters(in: .whitespaces)
        let b   = alertBody.trimmingCharacters(in: .whitespaces)
        let images = selectedImages
        isSending = true
        Task {
            let didSend = await profile.sendAnnouncement(
                knotID: group.id,
                title: t,
                body: b,
                isPinned: false,
                images: images
            )
            await MainActor.run {
                isSending = false
                if didSend {
                    sent = true
                } else {
                    showSendError = true
                }
            }
        }
    }
}

// MARK: - Transfer Creator Sheet
struct TransferCreatorSheet: View {
    let group              : CommunityGroup
    @Binding var selectedNewCreator: String?
    let onConfirm          : (String) -> Void
    let onDelete           : () -> Void    // called when sole creator chooses to delete
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile
    @State private var showDeleteConfirm = false
    @State private var isLoadingMembers  = true

    /// Live group from profile state — picks up loadKnotMembers updates
    private var liveGroup: CommunityGroup {
        profile.createdGroups.first(where: { $0.id == group.id }) ?? group
    }

    /// All members except the current creator
    private var candidates: [String] {
        let all = liveGroup.coAdminNames + liveGroup.memberNames
        return all.filter { $0 != profile.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header explanation
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 36)).foregroundColor(.primary)
                    Text("Transfer Ownership")
                        .font(.title2).fontWeight(.bold)
                    Text("Choose a member to become the new creator of \"\(group.name)\". You will leave the knot after transferring.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 24)

                if isLoadingMembers {
                    Spacer()
                    ProgressView("Loading members…")
                    Spacer()
                } else if candidates.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("You're the only member.")
                            .font(.headline)
                        Text("There's no one to pass ownership to. You can delete this Knot instead.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button(action: { showDeleteConfirm = true }) {
                            Text("Delete Knot")
                                .fontWeight(.semibold).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.red).cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    }
                    Spacer()
                } else {
                    List(candidates, id: \.self) { name in
                        Button(action: { selectedNewCreator = name }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.knotAccent).frame(width: 36, height: 36)
                                    Text(String(name.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                                }
                                Text(name).font(.subheadline).foregroundColor(.primary)
                                Spacer()
                                if liveGroup.coAdminNames.contains(name) {
                                    Text("Admin").font(.caption2).foregroundColor(.secondary)
                                }
                                if selectedNewCreator == name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)

                    VStack(spacing: 8) {
                        Button(action: {
                            guard let chosen = selectedNewCreator else { return }
                            dismiss()
                            onConfirm(chosen)
                        }) {
                            Text("Transfer & Leave")
                                .fontWeight(.semibold).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding()
                                .background(selectedNewCreator == nil ? Color.gray : Color.red)
                                .cornerRadius(12)
                        }
                        .disabled(selectedNewCreator == nil)

                        // Auto-pick: prefer co-admin, fall back to random member
                        Button(action: {
                            let auto = liveGroup.coAdminNames.filter { $0 != profile.name }.randomElement()
                                    ?? liveGroup.memberNames.filter { $0 != profile.name }.randomElement()
                            guard let chosen = auto else { return }
                            dismiss()
                            onConfirm(chosen)
                        }) {
                            Text("Leave Knot (auto-pick new owner)")
                                .fontWeight(.semibold).foregroundColor(.red)
                                .frame(maxWidth: .infinity).padding()
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4), lineWidth: 1.5))
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 24)
                }
            }
            .navigationTitle("Transfer Ownership")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Delete Knot", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Knot", role: .destructive) {
                    dismiss()
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This will permanently delete the knot and all its data.") }
            .task {
                // Always fetch fresh members when the sheet opens — local memberCount/names
                // can be stale if the trigger ran for another user
                isLoadingMembers = true
                await profile.loadKnotMembers(for: group.id)
                isLoadingMembers = false
            }
        }
    }
}

#Preview {
    CommunitiesView().environment(UserProfile(name: "Ruhaan"))
}
