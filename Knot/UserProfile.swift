import SwiftUI
import UIKit
import Observation
import Supabase

// MARK: - App Notification
struct AppNotification: Identifiable {
    enum NotifType { case connectionRequest }
    let id        = UUID()
    var type      : NotifType
    var fromName  : String
    var timestamp : Date = Date()
}

// MARK: - User Profile (shared observable state)
@MainActor
@Observable
class UserProfile {

    // ─── Supabase identity ────────────────────────────────────────────────
    /// Set immediately after sign-in. Every Supabase write is gated on this.
    var currentUserID: UUID? = nil

    // ─── Profile fields ───────────────────────────────────────────────────
    var name         : String    = ""
    var bio          : String    = ""
    var street       : String    = ""
    var city         : String    = ""
    var postalCode   : String    = ""
    var country      : String    = ""
    var profileImage : UIImage?  = nil
    /// Supabase Storage public URL for the profile image.
    var profileImageURL: String? = nil

    // Privacy
    var isPrivateAccount      : Bool = false
    var showKnotsOnProfile    : Bool = true
    var showListingsOnProfile : Bool = true
    var showConnectionsOnProfile: Bool = true

    // Mock privacy for other users (replaced by Supabase fetch in Phase 2)
    struct OtherUserPrivacy {
        var isPrivate    : Bool = false
        var showKnots    : Bool = true
        var showListings : Bool = true
    }
    var otherUserPrivacy: [String: OtherUserPrivacy] = [
        "Ahmad Khalid" : OtherUserPrivacy(isPrivate: true),
        "Lin Hui"      : OtherUserPrivacy(isPrivate: false, showKnots: false, showListings: true),
        "David Chen"   : OtherUserPrivacy(isPrivate: false, showKnots: true, showListings: false),
    ]
    func privacy(for name: String) -> OtherUserPrivacy { otherUserPrivacy[name] ?? .init() }

    // Tab navigation
    var selectedTab: AppTab = .home
    var pendingKnotsViewMode: GroupViewMode? = nil

    // Community membership state
    var requestedGroupIDs : Set<UUID>        = []
    var joinedGroupIDs    : Set<UUID>        = []
    var createdGroups     : [CommunityGroup] = []
    var publicKnots       : [CommunityGroup] = []   // all public knots for "All Knots" tab

    var joinRequests       : [UUID: [JoinRequest]] = [:]
    var pendingAdminActions: [AdminActionRequest]  = []

    // Phase 2 — UUID-based connections from Supabase
    var dbConnections      : [DBConnection] = []
    var connectionProfiles : [UUID: String] = [:]   // other user's UUID → their name
    private var realtimeTask   : Task<Void, Never>? = nil
    private var realtimeChannel: RealtimeChannelV2? = nil

    // Phase 4 — Messaging realtime (one channel per open ChatView)
    private var messagingRealtimeTask   : Task<Void, Never>? = nil
    private var messagingRealtimeChannel: RealtimeChannelV2? = nil

    // Phase 5 — Announcements realtime
    private var announcementRealtimeTask   : Task<Void, Never>? = nil
    private var announcementRealtimeChannel: RealtimeChannelV2? = nil

    // Computed string arrays for UI compatibility
    var connections: [String] {
        guard let me = currentUserID else { return [] }
        return dbConnections
            .filter { $0.status == "accepted" }
            .compactMap { c in
                let otherID = c.requesterId == me ? c.recipientId : c.requesterId
                return connectionProfiles[otherID]
            }
    }
    var sentConnectionRequests: [String] {
        guard let me = currentUserID else { return [] }
        return dbConnections
            .filter { $0.status == "pending" && $0.requesterId == me }
            .compactMap { connectionProfiles[$0.recipientId] }
    }
    var receivedConnectionRequests: [String] {
        guard let me = currentUserID else { return [] }
        return dbConnections
            .filter { $0.status == "pending" && $0.recipientId == me }
            .compactMap { connectionProfiles[$0.requesterId] }
    }
    /// Used by AnnouncementsView to accept/decline with a real connection ID.
    var pendingReceivedRequests: [(connectionID: UUID, name: String)] {
        guard let me = currentUserID else { return [] }
        return dbConnections
            .filter { $0.status == "pending" && $0.recipientId == me }
            .compactMap { c in
                guard let n = connectionProfiles[c.requesterId] else { return nil }
                return (connectionID: c.id, name: n)
            }
    }

    var notifications: [AppNotification] = []

    // Shop listings
    var allListings: [ShopListing] = []
    var myListings : [ShopListing] {
        guard let me = currentUserID else { return [] }
        return allListings.filter { $0.sellerID == me }
    }
    var orders     : [KnotOrder]   = []

    // Alerts / Announcements
    var announcements: [Announcement] = []

    // Conversations
    var conversations             : [Conversation] = []
    var pendingChatConversationID : UUID?           = nil

// MARK: - Init

    init(name: String) {
        self.name = name
        // Conversations and knots are loaded from Supabase in loadFromSupabase() after sign-in.
        // makeSampleConversations() kept in MessagesView.swift for #Preview only.
    }

    var initial: String { String(name.prefix(1)).uppercased() }


    // MARK: - Supabase: load profile

    /// Fetches the user's profile from Supabase and populates all local fields.
    /// Called by AuthManager.onSignedIn after every sign-in.
    func loadFromSupabase(userID: UUID) async {
        self.currentUserID = userID
        do {
            guard let db = try await ProfileService.fetch(userID: userID) else { return }
            name                   = db.name
            bio                    = db.bio
            street                 = db.street ?? ""
            city                   = db.city ?? ""
            postalCode             = db.postalCode ?? ""
            country                = db.country ?? ""
            isPrivateAccount       = db.isPrivate
            showKnotsOnProfile     = db.showKnots
            showListingsOnProfile  = db.showListings
            showConnectionsOnProfile = db.showConnections
            profileImageURL        = db.profileImage
            // Download the image for in-memory display if a URL exists.
            // Validate the URL is from the expected Supabase Storage domain before fetching —
            // prevents a compromised DB row from directing the app to an attacker-controlled host.
            if let urlString = db.profileImage,
               let url = URL(string: urlString),
               let host = url.host,
               host.hasSuffix(".supabase.co") || host.hasSuffix(".supabase.in") {
                let (data, _) = try await URLSession.shared.data(from: url)
                profileImage = UIImage(data: data)
            }
            await loadConnections()
            startConnectionRealtime()
            await loadKnots()
            await loadConversations()
            await loadAnnouncements()
            startAnnouncementRealtime()
            await loadListings()
            await loadOrders()
        } catch {
            print("[UserProfile] loadFromSupabase error: \(error)")
        }
    }


    // MARK: - Phase 2: Connections

    func loadConnections() async {
        guard let me = currentUserID else { return }
        do {
            let rows = try await ConnectionService.fetchAll()
            dbConnections = rows

            // Build name cache: fetch profiles of all other parties
            let otherIDs = Array(Set(rows.compactMap { c -> UUID? in
                c.requesterId == me ? c.recipientId : c.requesterId
            }))
            let profiles = try await ProfileService.fetchMultiple(userIDs: otherIDs)
            for p in profiles { connectionProfiles[p.id] = p.name }
        } catch {
            print("[UserProfile] loadConnections error: \(error)")
        }
    }

    func startConnectionRealtime() {
        guard let me = currentUserID else { return }
        // Cancel the listener loop first
        realtimeTask?.cancel()
        realtimeTask = nil
        // Remove the old channel so we can add callbacks before the next subscribe()
        let oldChannel = realtimeChannel
        realtimeChannel = nil
        realtimeTask = Task {
            if let old = oldChannel {
                await supabase.realtimeV2.removeChannel(old)
            }
            let channel = await supabase.realtimeV2.channel("connections:\(me)")
            let changes = await channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "connections"
            )
            await channel.subscribe()
            realtimeChannel = channel
            for await _ in changes {
                await loadConnections()
            }
        }
    }

    // MARK: - Phase 3: Knots

    func loadKnots() async {
        do {
            let (knots, members) = try await KnotService.fetchJoined()

            // Fetch all public knots for "All Knots" tab
            let allPublicDBKnots = try await KnotService.fetchPublic()

            // Collect all unique creator IDs across joined + public knots
            let allKnotsForNames = knots + allPublicDBKnots
            let creatorIDs = Array(Set(allKnotsForNames.map(\.creatorId)))
            let creatorProfiles = try await ProfileService.fetchMultiple(userIDs: creatorIDs)
            let creatorNames: [UUID: String] = Dictionary(uniqueKeysWithValues: creatorProfiles.map { ($0.id, $0.name) })

            // Build role lookup: knotID → role string
            let roleByKnot: [UUID: String] = Dictionary(uniqueKeysWithValues: members.map { ($0.knotId, $0.role) })

            func toCommunityGroup(_ knot: DBKnot) -> CommunityGroup {
                let ageGroup = AgeGroup(rawValue: knot.ageGroup) ?? .any
                let payType: KnotPaymentType = {
                    switch knot.paymentType {
                    case "per_session": return .perSession
                    case "one_time":    return .oneTime
                    default:            return .free
                    }
                }()
                var group = CommunityGroup(
                    id                         : knot.id,
                    name                       : knot.name,
                    imageName                  : categoryIcon(knot.category),
                    description                : knot.description,
                    memberCount                : knot.memberCount,
                    category                   : knot.category,
                    location                   : knot.location,
                    adminName                  : creatorNames[knot.creatorId] ?? "Unknown",
                    maxMembers                 : knot.maxMembers,
                    requiresApproval           : knot.requiresApproval,
                    isPublic                   : knot.isPublic,
                    isEvent                    : knot.isEvent,
                    isConnectionsOnly          : knot.isConnectionsOnly,
                    hideLocationFromNonMembers : knot.hideLocationFromNonMembers,
                    ageGroup                   : ageGroup,
                    minAge                     : knot.minAge,
                    maxAge                     : knot.maxAge,
                    isPaid                     : knot.isPaid,
                    paymentType                : payType,
                    price                      : knot.priceCents / 100
                )
                group.imageURL = knot.imageUrl
                return group
            }

            let joinedGroups = knots.map { toCommunityGroup($0) }
            let creatorKnotIDs = Set(members.filter { $0.role == "creator" }.map(\.knotId))
            createdGroups  = joinedGroups.filter { creatorKnotIDs.contains($0.id) }
            joinedGroupIDs = Set(joinedGroups.map(\.id))
            publicKnots    = allPublicDBKnots.map { toCommunityGroup($0) }
        } catch {
            print("[UserProfile] loadKnots error: \(error)")
        }
    }

    func addKnot(_ group: CommunityGroup) {
        createdGroups.append(group)
        joinedGroupIDs.insert(group.id)
    }

    func joinKnot(_ group: CommunityGroup) async {
        guard let me = currentUserID else { return }
        if group.requiresApproval {
            // Submit a join request — delete any stale rejected/cancelled row first
            // so the unique constraint on (knot_id, applicant_id) doesn't block re-submission.
            struct JoinRequestInsert: Encodable {
                let knot_id, applicant_id: UUID
            }
            do {
                try? await supabase
                    .from("knot_join_requests")
                    .delete()
                    .eq("knot_id", value: group.id)
                    .eq("applicant_id", value: me)
                    .neq("status", value: "pending")
                    .execute()
                try await supabase
                    .from("knot_join_requests")
                    .insert(JoinRequestInsert(knot_id: group.id, applicant_id: me))
                    .execute()
                requestedGroupIDs.insert(group.id)
            } catch {
                print("[UserProfile] joinKnot (request) error: \(error)")
            }
        } else {
            // Direct join — insert into knot_members
            struct MemberInsert: Encodable {
                let knot_id, user_id: UUID
                let role: String
            }
            do {
                try await supabase
                    .from("knot_members")
                    .insert(MemberInsert(knot_id: group.id, user_id: me, role: "member"))
                    .execute()
                joinedGroupIDs.insert(group.id)
                // Refresh public knots so member_count updates
                await loadKnots()
            } catch {
                print("[UserProfile] joinKnot error: \(error)")
            }
        }
    }

    func sendConnectionRequest(to userID: UUID) async {
        guard let me = currentUserID, userID != me else { return }
        guard !dbConnections.contains(where: {
            ($0.requesterId == me && $0.recipientId == userID) ||
            ($0.requesterId == userID && $0.recipientId == me)
        }) else { return }
        do {
            try await ConnectionService.send(to: userID)
            await loadConnections()
        } catch {
            print("[UserProfile] sendConnectionRequest error: \(error)")
        }
    }

    func acceptConnectionRequest(connectionID: UUID) async {
        do {
            try await ConnectionService.accept(connectionID: connectionID)
            if let idx = dbConnections.firstIndex(where: { $0.id == connectionID }) {
                dbConnections[idx] = DBConnection(
                    id: dbConnections[idx].id,
                    requesterId: dbConnections[idx].requesterId,
                    recipientId: dbConnections[idx].recipientId,
                    status: "accepted",
                    createdAt: dbConnections[idx].createdAt,
                    updatedAt: Date()
                )
            }
        } catch {
            print("[UserProfile] acceptConnectionRequest error: \(error)")
        }
    }

    func declineConnectionRequest(connectionID: UUID) async {
        do {
            try await ConnectionService.decline(connectionID: connectionID)
            dbConnections.removeAll { $0.id == connectionID }
        } catch {
            print("[UserProfile] declineConnectionRequest error: \(error)")
        }
    }

    func removeConnection(with userID: UUID) async {
        guard let me = currentUserID else { return }
        guard let conn = dbConnections.first(where: {
            ($0.requesterId == me && $0.recipientId == userID) ||
            ($0.requesterId == userID && $0.recipientId == me)
        }) else { return }
        do {
            try await ConnectionService.remove(connectionID: conn.id)
            dbConnections.removeAll { $0.id == conn.id }
        } catch {
            print("[UserProfile] removeConnection error: \(error)")
        }
    }

    func removeConnection(withName name: String) async {
        guard let uid = connectionProfiles.first(where: { $0.value == name })?.key else { return }
        await removeConnection(with: uid)
    }

    // MARK: - Supabase: save profile

    /// Persists current profile fields to Supabase. Call from EditProfileView on save.
    func saveProfileToSupabase() async {
        // currentUserID is kept for local state; ProfileService.save() derives the
        // real DB target from auth.currentUser internally (no IDOR possible).
        guard currentUserID != nil else { return }
        do {
            let update = DBProfileUpdate(
                name: name,
                bio: bio,
                profileImage: profileImageURL,
                street: street,
                city: city,
                postalCode: postalCode,
                country: country,
                isPrivate: isPrivateAccount,
                showKnots: showKnotsOnProfile,
                showListings: showListingsOnProfile,
                showConnections: showConnectionsOnProfile
            )
            try await ProfileService.save(update)
        } catch {
            print("[UserProfile] saveProfileToSupabase error: \(error.localizedDescription)")
        }
    }

    /// Uploads a new profile image and updates `profileImageURL`. Call from EditProfileView.
    func uploadProfileImage(_ image: UIImage) async {
        // ProfileService.uploadProfileImage() derives the storage path from
        // auth.currentUser internally (no IDOR possible).
        guard currentUserID != nil else {
            print("[UserProfile] uploadProfileImage: NO currentUserID")
            return
        }
        do {
            profileImage = image
            print("[UserProfile] uploadProfileImage: starting Storage upload …")
            let url = try await ProfileService.uploadProfileImage(image)
            print("[UserProfile] uploadProfileImage: Storage upload OK → \(url)")
            profileImageURL = url
            // Persist directly so we can surface any DB error
            do {
                try await ProfileService.save(DBProfileUpdate(
                    name: name, bio: bio,
                    profileImage: url,
                    street: street, city: city, postalCode: postalCode, country: country,
                    isPrivate: isPrivateAccount,
                    showKnots: showKnotsOnProfile,
                    showListings: showListingsOnProfile,
                    showConnections: showConnectionsOnProfile
                ))
                print("[UserProfile] uploadProfileImage: profile_image written to DB OK")
            } catch {
                print("[UserProfile] uploadProfileImage: DB write FAILED → \(error)")
            }
            // Cache-buster (file path is reused, AsyncImage needs a new URL)
            profileImageURL = url + "?t=\(Int(Date().timeIntervalSince1970))"
        } catch {
            print("[UserProfile] uploadProfileImage: Storage upload FAILED → \(error)")
        }
    }


    /// Upload a cover photo for a knot and persist its URL to Supabase.
    /// Mirrors uploadProfileImage — updates local state then writes to DB.
    func uploadKnotCoverImage(knotID: UUID, image: UIImage) async {
        print("[UserProfile] uploadKnotCoverImage CALLED for knotID=\(knotID)")
        guard currentUserID != nil else {
            print("[UserProfile] uploadKnotCoverImage: NO currentUserID")
            return
        }
        // 1) Upload to Storage
        let url: String
        do {
            url = try await ProfileService.uploadKnotCoverImage(knotID: knotID, image: image)
            print("[UserProfile] uploadKnotCoverImage: Storage upload OK → \(url)")
        } catch {
            print("[UserProfile] uploadKnotCoverImage: Storage upload FAILED → \(error)")
            return
        }
        // 2) Write the URL to the knots table
        do {
            try await KnotService.updateImageURL(knotID: knotID, url: url)
            print("[UserProfile] uploadKnotCoverImage: DB image_url write OK")
        } catch {
            print("[UserProfile] uploadKnotCoverImage: DB image_url write FAILED → \(error)")
            return
        }
        // 3) Update local state with cache-busted URL
        let busted = url + "?t=\(Int(Date().timeIntervalSince1970))"
        if let idx = createdGroups.firstIndex(where: { $0.id == knotID }) {
            createdGroups[idx].imageURL = busted
        }
        if let idx = publicKnots.firstIndex(where: { $0.id == knotID }) {
            publicKnots[idx].imageURL = busted
        }
    }

    // MARK: - Community helpers

    func addRequest(_ request: JoinRequest, toGroup groupID: UUID) {
        if joinRequests[groupID] == nil { joinRequests[groupID] = [] }
        joinRequests[groupID]!.append(request)
    }

    func updateRequest(id requestID: UUID, inGroup groupID: UUID, status: JoinRequest.Status) {
        guard let idx = joinRequests[groupID]?.firstIndex(where: { $0.id == requestID }) else { return }
        joinRequests[groupID]![idx].status = status
        if status == .approved {
            let applicantName = joinRequests[groupID]![idx].applicantName
            if let gi = createdGroups.firstIndex(where: { $0.id == groupID }) {
                if !createdGroups[gi].memberNames.contains(applicantName) {
                    createdGroups[gi].memberNames.append(applicantName)
                    createdGroups[gi].memberCount += 1
                }
            }
        }
    }

    func loadJoinRequests(for knotID: UUID) async {
        do {
            struct DBRow: Codable {
                let id: UUID
                let applicant_id: UUID
                let status: String
                let submitted_at: Date
            }
            let rows: [DBRow] = try await supabase
                .from("knot_join_requests")
                .select("id, applicant_id, status, submitted_at")
                .eq("knot_id", value: knotID)
                .eq("status", value: "pending")
                .execute()
                .value

            let applicantIDs = rows.map(\.applicant_id)
            let profiles = try await ProfileService.fetchMultiple(userIDs: applicantIDs)
            let nameByID: [UUID: String] = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })

            joinRequests[knotID] = rows.map { row in
                var r = JoinRequest(applicantName: nameByID[row.applicant_id] ?? "Unknown")
                r.dbID        = row.id
                r.applicantID = row.applicant_id
                r.submittedAt = row.submitted_at
                return r
            }
        } catch {
            print("[UserProfile] loadJoinRequests error: \(error)")
        }
    }

    func loadKnotMembers(for knotID: UUID) async {
        do {
            let members = try await KnotService.fetchMembers(knotID: knotID)
            let userIDs = members.map(\.userId)
            let profiles = try await ProfileService.fetchMultiple(userIDs: userIDs)
            let nameByID: [UUID: String] = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })

            let realCount = members.count
            let memberNames  = members.filter { $0.role == "member" }.compactMap { nameByID[$0.userId] }
            let coAdminNames = members.filter { $0.role == "co_admin" }.compactMap { nameByID[$0.userId] }
            let memberUUIDs = Dictionary(
                members.compactMap { m -> (String, UUID)? in
                    guard let name = nameByID[m.userId] else { return nil }
                    return (name, m.userId)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Update BOTH createdGroups and publicKnots so liveGroup (which reads publicKnots
            // first) has the correct memberUUIDs/names too.
            if let gi = createdGroups.firstIndex(where: { $0.id == knotID }) {
                createdGroups[gi].memberCount  = realCount
                createdGroups[gi].memberNames  = memberNames
                createdGroups[gi].coAdminNames = coAdminNames
                createdGroups[gi].memberUUIDs  = memberUUIDs
            }
            if let pi = publicKnots.firstIndex(where: { $0.id == knotID }) {
                publicKnots[pi].memberCount  = realCount
                publicKnots[pi].memberNames  = memberNames
                publicKnots[pi].coAdminNames = coAdminNames
                publicKnots[pi].memberUUIDs  = memberUUIDs
            }
        } catch {
            print("[UserProfile] loadKnotMembers error: \(error)")
        }
    }

    func approveJoinRequest(requestID: UUID, knotID: UUID, applicantID: UUID) async {
        guard let me = currentUserID else { return }
        struct StatusUpdate: Encodable { let status: String; let reviewed_at: Date; let reviewed_by: UUID }
        struct MemberInsert: Encodable { let knot_id, user_id: UUID; let role: String }
        do {
            try await supabase
                .from("knot_join_requests")
                .update(StatusUpdate(status: "approved", reviewed_at: Date(), reviewed_by: me))
                .eq("id", value: requestID)
                .execute()
            try await supabase
                .from("knot_members")
                .insert(MemberInsert(knot_id: knotID, user_id: applicantID, role: "member"))
                .execute()
            joinRequests[knotID]?.removeAll { $0.dbID == requestID }
            await loadKnotMembers(for: knotID)
        } catch {
            print("[UserProfile] approveJoinRequest error: \(error)")
        }
    }

    func rejectJoinRequest(requestID: UUID, knotID: UUID) async {
        struct StatusUpdate: Encodable { let status: String; let reviewed_at: Date }
        do {
            try await supabase
                .from("knot_join_requests")
                .update(StatusUpdate(status: "rejected", reviewed_at: Date()))
                .eq("id", value: requestID)
                .execute()
            joinRequests[knotID]?.removeAll { $0.dbID == requestID }
        } catch {
            print("[UserProfile] rejectJoinRequest error: \(error)")
        }
    }

    func updateCreatedGroup(_ updated: CommunityGroup) {
        if let idx = createdGroups.firstIndex(where: { $0.id == updated.id }) {
            createdGroups[idx] = updated
        }
        if let idx = publicKnots.firstIndex(where: { $0.id == updated.id }) {
            publicKnots[idx] = updated
        }
    }


    // MARK: - Admin Action helpers

    func requestAdminAction(groupID: UUID, groupName: String, requestingAdmin: String, target: String, action: AdminActionRequest.ActionType) {
        let req = AdminActionRequest(groupID: groupID, groupName: groupName, requestingAdminName: requestingAdmin, targetMemberName: target, actionType: action)
        pendingAdminActions.append(req)
        // TODO: Phase 3 — insert into knot_admin_action_requests
    }

    func approveAdminAction(id reqID: UUID) {
        guard let idx = pendingAdminActions.firstIndex(where: { $0.id == reqID }) else { return }
        let req = pendingAdminActions[idx]
        pendingAdminActions[idx].status = .approved
        guard let gi = createdGroups.firstIndex(where: { $0.id == req.groupID }) else { return }
        switch req.actionType {
        case .makeAdmin:
            if !createdGroups[gi].coAdminNames.contains(req.targetMemberName) {
                createdGroups[gi].coAdminNames.append(req.targetMemberName)
            }
        case .dismissAdmin:
            createdGroups[gi].coAdminNames.removeAll { $0 == req.targetMemberName }
        case .kick:
            createdGroups[gi].memberNames.removeAll  { $0 == req.targetMemberName }
            createdGroups[gi].coAdminNames.removeAll { $0 == req.targetMemberName }
        }
        // TODO: Phase 3 — call apply-admin-action Edge Function
    }

    func rejectAdminAction(id reqID: UUID) {
        guard let idx = pendingAdminActions.firstIndex(where: { $0.id == reqID }) else { return }
        pendingAdminActions[idx].status = .rejected
    }


    // MARK: - Connection helpers (string-name based — used by knot member views, Phase 3 will add UUIDs)

    func sendConnectionRequest(to targetName: String) {
        // Local optimistic update only — used from knot/group contexts that don't have UUIDs yet.
        // Phase 3 will replace with UUID-based flow when knot_members surfaces user IDs.
        guard !sentConnectionRequests.contains(targetName),
              !connections.contains(targetName)
        else { return }
        // No DB write here — use sendConnectionRequest(to userID:) when UUID is available.
    }


    // MARK: - Group Chat helpers

    func openKnotGroupChat(knotID: UUID, knotName: String) {
        if !conversations.contains(where: { $0.sourceKnotID == knotID && $0.isGroup }) {
            var c = Conversation(isGroup: true, groupName: "\(knotName) Chat", participants: [], messages: [])
            c.sourceKnotID   = knotID
            c.sourceKnotName = knotName
            c.adminNames     = [name]
            c.creatorName    = name
            conversations.insert(c, at: 0)
        }
        let id = conversations.first { $0.sourceKnotID == knotID && $0.isGroup }?.id
        selectedTab               = .messages
        pendingChatConversationID = id
        // TODO: Phase 4 — fetch/create conversation in Supabase
    }

    func renameConversation(id convID: UUID, to newName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupName = newName
        // TODO: Phase 4 — update conversations row
    }

    func updateConversationImage(id convID: UUID, image: UIImage?) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupImage = image
        // TODO: Phase 4 — upload image to Storage, update conversations.group_image_url
    }

    func makeAdminInConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        if !conversations[idx].adminNames.contains(memberName) {
            conversations[idx].adminNames.append(memberName)
        }
        Task {
            if let targetID = connectionProfiles.first(where: { $0.value == memberName })?.key {
                try? await MessagingService.updateParticipantAdmin(conversationID: convID, userID: targetID, isAdmin: true)
            }
        }
    }

    func demoteAdminInConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        guard conversations[idx].creatorName != memberName else { return }
        conversations[idx].adminNames.removeAll { $0 == memberName }
        Task {
            if let targetID = connectionProfiles.first(where: { $0.value == memberName })?.key {
                try? await MessagingService.updateParticipantAdmin(conversationID: convID, userID: targetID, isAdmin: false)
            }
        }
    }

    func kickFromConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].participants.removeAll { $0 == memberName }
        conversations[idx].adminNames.removeAll   { $0 == memberName }
        if let knotID = conversations[idx].sourceKnotID,
           let gi = createdGroups.firstIndex(where: { $0.id == knotID }) {
            createdGroups[gi].memberNames.removeAll  { $0 == memberName }
            createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
        }
        // TODO: Phase 4 — update conversation_participants.has_left = true; Phase 3 — remove from knot_members
    }

    func leaveConversation(id convID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        if conversations[idx].creatorName == name {
            let otherAdmins = conversations[idx].adminNames.filter { $0 != name }
            if let newCreator = otherAdmins.randomElement() {
                conversations[idx].creatorName = newCreator
            } else if let newCreator = conversations[idx].participants.filter({ $0 != name }).randomElement() {
                conversations[idx].creatorName = newCreator
                conversations[idx].adminNames.append(newCreator)
            }
        }
        conversations[idx].adminNames.removeAll  { $0 == name }
        conversations[idx].participants.removeAll { $0 == name }
        let systemMsg = ChatMessage(text: "\(name) left the group.", sender: "system", timestamp: Date(), isSystem: true)
        conversations[idx].messages.append(systemMsg)
        conversations[idx].hasLeft = true
        if let knotID = conversations[idx].sourceKnotID { joinedGroupIDs.remove(knotID) }
        Task {
            do { try await MessagingService.leaveConversation(conversationID: convID) }
            catch { print("[UserProfile] leaveConversation DB error: \(error)") }
        }
    }

    /// Creator transfers ownership to newCreatorID then leaves.
    func transferCreatorAndLeave(groupID: UUID, newCreatorID: UUID) async {
        do {
            try await KnotService.transferCreator(knotID: groupID, newCreatorID: newCreatorID)
        } catch {
            print("[UserProfile] transferCreator error: \(error)")
            return
        }
        // Clean up local state — creator is no longer a member
        joinedGroupIDs.remove(groupID)
        requestedGroupIDs.remove(groupID)
        createdGroups.removeAll { $0.id == groupID }
        // publicKnots stays — the knot still exists, just with a new creator
        if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
            leaveConversation(id: conversations[ci].id)
        }
        await loadKnots()
    }

    func leaveKnot(groupID: UUID) async {
        joinedGroupIDs.remove(groupID)
        requestedGroupIDs.remove(groupID)
        if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
            leaveConversation(id: conversations[ci].id)
        }
        do {
            try await KnotService.leaveKnot(knotID: groupID)
            print("[UserProfile] leaveKnot succeeded for \(groupID)")
            await loadKnots()
        } catch {
            print("[UserProfile] leaveKnot error: \(error)")
        }
    }

    func deleteConversation(id convID: UUID) {
        conversations.removeAll { $0.id == convID }
        // TODO: Phase 4 — delete conversation + all messages from Supabase
    }

    func deleteKnot(groupID: UUID) async {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = createdGroups[gi]
        do {
            try await KnotService.delete(knotID: groupID)
        } catch {
            print("[UserProfile] deleteKnot error: \(error)")
            return
        }
        let announcement = Announcement(
            title   : "\(group.name) has been deleted",
            body    : "The knot \"\(group.name)\" has been permanently deleted by the creator. You are no longer a member.",
            sender  : group.name,
            date    : "Just now",
            isRead  : false,
            knotName: group.name
        )
        announcements.insert(announcement, at: 0)
        conversations.removeAll { $0.sourceKnotID == groupID && $0.isGroup }
        joinedGroupIDs.remove(groupID)
        requestedGroupIDs.remove(groupID)
        createdGroups.remove(at: gi)
        publicKnots.removeAll { $0.id == groupID }
    }


    // MARK: - Knot Member helpers

    func kickMemberFromKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        createdGroups[gi].memberNames.removeAll  { $0 == memberName }
        createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
        if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
            conversations[ci].participants.removeAll { $0 == memberName }
            conversations[ci].adminNames.removeAll   { $0 == memberName }
        }
        // TODO: Phase 3 — delete knot_members row
    }

    func makeCoAdminInKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        if !createdGroups[gi].coAdminNames.contains(memberName) {
            createdGroups[gi].coAdminNames.append(memberName)
        }
        // TODO: Phase 3 — update knot_members.role = 'co_admin'
    }


    // MARK: - Phase 4: Conversations

    func loadConversations() async {
        guard let me = currentUserID else { return }
        do {
            let data = try await MessagingService.fetchConversations()

            // Resolve all participant user IDs we haven't seen before
            var unknownIDs: Set<UUID> = []
            for d in data {
                for p in d.participants where p.userId != me && connectionProfiles[p.userId] == nil {
                    unknownIDs.insert(p.userId)
                }
            }
            if !unknownIDs.isEmpty {
                let profiles = try await ProfileService.fetchMultiple(userIDs: Array(unknownIDs))
                for p in profiles { connectionProfiles[p.id] = p.name }
            }

            var built: [Conversation] = []
            for d in data {
                let otherParts = d.participants.filter { $0.userId != me }
                let isGroup    = d.conversation.isGroup

                let adminNames: [String] = d.participants
                    .filter { $0.isAdmin && !$0.isCreator }
                    .compactMap { connectionProfiles[$0.userId] }
                let creatorName: String = d.participants
                    .first { $0.isCreator }
                    .flatMap { connectionProfiles[$0.userId] } ?? ""

                var c = Conversation()
                c.id          = d.conversation.id
                c.isGroup     = isGroup
                c.isFavourite = d.myParticipant.isFavourite
                c.hasLeft     = d.myParticipant.hasLeft
                c.adminNames  = adminNames
                c.creatorName = creatorName
                c.sourceKnotID = d.conversation.sourceKnotId

                if isGroup {
                    c.groupName   = d.conversation.groupName ?? ""
                    c.participants = otherParts.compactMap { connectionProfiles[$0.userId] }
                } else {
                    c.participantName = otherParts.first.flatMap { connectionProfiles[$0.userId] } ?? ""
                }

                built.append(c)
            }

            conversations = built
        } catch {
            print("[UserProfile] loadConversations error: \(error)")
        }
    }

    func loadMessages(conversationID: UUID) async {
        guard let me = currentUserID else { return }
        do {
            let dbMessages = try await MessagingService.fetchMessages(conversationID: conversationID)
            guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

            // Collect any sender IDs we don't know yet
            let unknownIDs = Set(dbMessages.compactMap(\.senderId).filter {
                $0 != me && connectionProfiles[$0] == nil
            })
            if !unknownIDs.isEmpty {
                let profiles = try await ProfileService.fetchMultiple(userIDs: Array(unknownIDs))
                for p in profiles { connectionProfiles[p.id] = p.name }
            }

            conversations[idx].messages = dbMessages.map { dbMessageToChatMessage($0) }
        } catch {
            print("[UserProfile] loadMessages error: \(error)")
        }
    }

    func sendMessage(text: String, conversationID: UUID, replyToID: UUID? = nil) async {
        do {
            let dbMsg = try await MessagingService.send(text: text, conversationID: conversationID)
            guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            let msg = dbMessageToChatMessage(dbMsg)
            // Skip if realtime already delivered it
            if !conversations[idx].messages.contains(where: { $0.id == dbMsg.id }) {
                conversations[idx].messages.append(msg)
            }
        } catch {
            print("[UserProfile] sendMessage error: \(error)")
        }
    }

    func createGroupConversation(name: String, participantNames: [String], groupImage: UIImage?) async {
        let participantIDs = participantNames.compactMap { n in
            connectionProfiles.first(where: { $0.value == n })?.key
        }
        do {
            let conv = try await MessagingService.createConversation(
                isGroup       : true,
                groupName     : name,
                participantIDs: participantIDs,
                sourceKnotID  : nil
            )
            var c          = Conversation()
            c.id           = conv.id
            c.isGroup      = true
            c.groupName    = name
            c.participants = participantNames
            c.adminNames   = [self.name]
            c.creatorName  = self.name
            c.groupImage   = groupImage
            conversations.insert(c, at: 0)
            selectedTab               = .messages
            pendingChatConversationID = conv.id
        } catch {
            print("[UserProfile] createGroupConversation error: \(error)")
        }
    }

    func startMessagingRealtime(conversationID: UUID) {
        messagingRealtimeTask?.cancel()
        messagingRealtimeTask = nil
        let oldChannel = messagingRealtimeChannel
        messagingRealtimeChannel = nil
        messagingRealtimeTask = Task {
            if let old = oldChannel {
                await supabase.realtimeV2.removeChannel(old)
            }
            let channel = await supabase.realtimeV2.channel("messages:\(conversationID)")
            let changes = await channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table : "messages",
                filter: "conversation_id=eq.\(conversationID.uuidString.lowercased())"
            )
            await channel.subscribe()
            messagingRealtimeChannel = channel
            for await _ in changes {
                await loadMessages(conversationID: conversationID)
            }
        }
    }

    func stopMessagingRealtime() {
        messagingRealtimeTask?.cancel()
        messagingRealtimeTask = nil
        if let ch = messagingRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
            messagingRealtimeChannel = nil
        }
    }

    private func dbMessageToChatMessage(_ msg: DBMessage) -> ChatMessage {
        let senderName: String = {
            guard let sid = msg.senderId else { return "System" }
            if sid == currentUserID { return name }
            return connectionProfiles[sid] ?? "Unknown"
        }()
        let status: ReadStatus = {
            switch msg.status {
            case "read":      return .read
            case "delivered": return .delivered
            default:          return .sent
            }
        }()
        var cm        = ChatMessage(sender: senderName, timestamp: msg.createdAt, status: status)
        cm.id         = msg.id
        cm.text       = msg.text
        cm.isSystem   = msg.isSystem
        cm.isStarred  = msg.isStarred
        if let rid = msg.replyToId { cm.replyToID = rid }
        return cm
    }

    // MARK: - Phase 5: Announcements

    func loadAnnouncements() async {
        do {
            let rows = try await AnnouncementService.fetchForUser()
            guard !rows.isEmpty else {
                announcements = []
                return
            }
            let senderIDs = Array(Set(rows.map(\.announcement.senderId)))
            var senderNames: [UUID: String] = [:]
            if let profiles = try? await ProfileService.fetchMultiple(userIDs: senderIDs) {
                for p in profiles { senderNames[p.id] = p.name }
            }
            let allKnots = createdGroups + publicKnots
            let knotNameMap = Dictionary(allKnots.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

            announcements = rows.map { row in
                var a = Announcement(
                    title    : row.announcement.title,
                    body     : row.announcement.body,
                    sender   : senderNames[row.announcement.senderId] ?? "Unknown",
                    date     : Self.formatAnnouncementDate(row.announcement.createdAt),
                    isRead   : row.isRead,
                    knotName : row.announcement.knotId.flatMap { knotNameMap[$0] } ?? "Knot",
                    isPinned : row.isPinned
                )
                a.id     = row.announcement.id
                a.knotID = row.announcement.knotId
                return a
            }
        } catch {
            print("[UserProfile] loadAnnouncements error: \(error)")
        }
    }

    func sendAnnouncement(knotID: UUID, title: String, body: String, isPinned: Bool) async {
        print("[UserProfile] sendAnnouncement called — knotID: \(knotID), title: \(title)")
        do {
            try await AnnouncementService.send(knotID: knotID, title: title, body: body, isPinned: isPinned)
            print("[UserProfile] sendAnnouncement succeeded")
            await loadAnnouncements()
        } catch {
            print("[UserProfile] sendAnnouncement error: \(error)")
        }
    }

    func startAnnouncementRealtime() {
        announcementRealtimeTask?.cancel()
        let oldCh = announcementRealtimeChannel
        announcementRealtimeChannel = nil
        announcementRealtimeTask = Task {
            if let old = oldCh { await supabase.realtimeV2.removeChannel(old) }
            let ch = await supabase.realtimeV2.channel("announcements")
            let changes = await ch.postgresChange(AnyAction.self, schema: "public", table: "announcements")
            await ch.subscribe()
            announcementRealtimeChannel = ch
            for await _ in changes {
                await loadAnnouncements()
            }
        }
    }

    func stopAnnouncementRealtime() {
        announcementRealtimeTask?.cancel()
        announcementRealtimeTask = nil
        if let ch = announcementRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
            announcementRealtimeChannel = nil
        }
    }

    private static func formatAnnouncementDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: date))"
        } else if cal.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday, \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, h:mm a"
            return formatter.string(from: date)
        }
    }

    // MARK: - Phase 6: Shop

    func loadListings() async {
        do {
            let rows = try await ShopService.fetchActive()
            let sellerIDs = Array(Set(rows.map { $0.sellerId }))
            var sellerNames: [UUID: String] = [:]
            if let profiles = try? await ProfileService.fetchMultiple(userIDs: sellerIDs) {
                for p in profiles { sellerNames[p.id] = p.name }
            }
            allListings = rows.map { row in
                ShopListing(
                    id         : row.id,
                    type       : Self.listingTypeFromDB(row.listingType),
                    category   : ShopCategory.fromDB(row.category),
                    condition  : ItemCondition.fromDB(row.condition),
                    name       : row.name,
                    description: row.description,
                    link       : row.link,
                    price      : row.priceCents / 100,
                    sellerName : sellerNames[row.sellerId] ?? "Unknown",
                    sellerID   : row.sellerId,
                    imageURLs  : row.imageUrls,
                    date       : row.createdAt
                )
            }
        } catch {
            print("[UserProfile] loadListings error: \(error)")
        }
    }

    func createListing(
        type       : ListingType,
        category   : ShopCategory,
        condition  : ItemCondition,
        name       : String,
        description: String,
        link       : String,
        price      : Int,
        images     : [UIImage]
    ) async {
        do {
            let db = try await ShopService.create(
                type: type, category: category, condition: condition,
                name: name, description: description, link: link,
                price: price, images: images
            )
            let local = ShopListing(
                id         : db.id,
                type       : type,
                category   : category,
                condition  : condition,
                name       : name,
                description: description,
                link       : link,
                price      : price,
                sellerName : self.name,
                sellerID   : db.sellerId,
                images     : images,
                imageURLs  : db.imageUrls,
                date       : db.createdAt
            )
            allListings.insert(local, at: 0)
        } catch {
            print("[UserProfile] createListing error: \(error)")
        }
    }

    func deleteListing(listingID: UUID) async {
        do {
            try await ShopService.delete(listingID: listingID)
            allListings = allListings.filter { $0.id != listingID }
        } catch {
            print("[UserProfile] deleteListing error: \(error)")
        }
    }

    private static func listingTypeFromDB(_ value: String) -> ListingType {
        switch value.lowercased() {
        case "service":       return .service
        case "advertisement": return .advertisement
        default:              return .item
        }
    }


    // MARK: - Phase 7: Orders

    func loadOrders() async {
        do {
            let rows = try await OrderService.fetchAll()

            // Resolve listing objects from local cache; fall back to a stub if listing was deleted.
            var listingMap: [UUID: ShopListing] = [:]
            for l in allListings { listingMap[l.id] = l }

            // Resolve names for all buyers/sellers in one batch fetch.
            let userIDs = Array(Set(rows.flatMap { [$0.buyerId, $0.sellerId] }))
            var nameMap: [UUID: String] = [:]
            if !userIDs.isEmpty,
               let profiles = try? await ProfileService.fetchMultiple(userIDs: userIDs) {
                for p in profiles { nameMap[p.id] = p.name }
            }
            // Merge already-cached connection names.
            for (id, n) in connectionProfiles { nameMap[id] = n }
            if let me = currentUserID { nameMap[me] = name }

            orders = rows.compactMap { row in
                let listing = listingMap[row.listingId] ?? ShopListing(
                    id        : row.listingId,
                    name      : "Deleted Listing",
                    price     : row.subtotalCents / 100,
                    sellerName: nameMap[row.sellerId] ?? "Unknown",
                    sellerID  : row.sellerId
                )
                let buyerName  = nameMap[row.buyerId]  ?? "Unknown"
                let sellerName = nameMap[row.sellerId] ?? listing.sellerName

                var proposal: MeetupProposal? = nil
                if let loc = row.meetupLocation,
                   let date = row.meetupDate,
                   let by   = row.meetupProposedBy {
                    proposal = MeetupProposal(location: loc, date: date, proposedBy: by)
                }

                var stepDates: [String: Date] = [:]
                if let d = row.pendingAt               { stepDates["pending"]               = d }
                if let d = row.sellerAcceptedAt        { stepDates["seller_accepted"]        = d }
                if let d = row.meetupAgreedAt          { stepDates["meetup_agreed"]          = d }
                if let d = row.awaitingConfirmationAt  { stepDates["awaiting_confirmation"]  = d }
                if let d = row.completeAt              { stepDates["complete"]               = d }

                return KnotOrder(
                    id          : row.id,
                    listing     : listing,
                    buyerName   : buyerName,
                    sellerName  : sellerName,
                    sellerId    : row.sellerId,
                    buyerId     : row.buyerId,
                    subtotal    : row.subtotalCents,
                    knotFeeRate : row.knotFeeRate,
                    fulfilment  : FulfilmentMethod.fromDB(row.fulfilment),
                    address     : row.deliveryAddress,
                    date        : row.createdAt,
                    status      : OrderStatus(rawValue: row.status) ?? .pending,
                    escrow      : row.escrowStatus == "released" ? .released : .held,
                    meetupProposal: proposal,
                    stepDates   : stepDates
                )
            }
        } catch {
            print("[UserProfile] loadOrders error: \(error)")
        }
    }

    // MARK: - Messaging

    func openConversation(with targetName: String, sourceKnotID: UUID? = nil, sourceKnotName: String = "") {
        // If a conversation already exists locally, just navigate to it.
        if let existing = conversations.first(where: { $0.participantName == targetName && !$0.isGroup }) {
            selectedTab               = .messages
            pendingChatConversationID = existing.id
            return
        }
        // Look up the target's UUID so we can create the conversation in DB.
        guard let targetID = connectionProfiles.first(where: { $0.value == targetName })?.key else {
            // No UUID available — create a local-only conversation as a fallback.
            var c            = Conversation()
            c.participantName = targetName
            c.sourceKnotID   = sourceKnotID
            c.sourceKnotName = sourceKnotName
            conversations.insert(c, at: 0)
            selectedTab               = .messages
            pendingChatConversationID = c.id
            return
        }
        Task {
            do {
                let conv = try await MessagingService.createConversation(
                    isGroup       : false,
                    groupName     : nil,
                    participantIDs: [targetID],
                    sourceKnotID  : sourceKnotID
                )
                var c             = Conversation()
                c.id              = conv.id
                c.participantName = targetName
                c.sourceKnotID    = sourceKnotID
                c.sourceKnotName  = sourceKnotName
                conversations.insert(c, at: 0)
                selectedTab               = .messages
                pendingChatConversationID = conv.id
            } catch {
                print("[UserProfile] openConversation error: \(error)")
            }
        }
    }


    // MARK: - Misc

    func clearAllData() {
        conversations.removeAll()
        createdGroups.removeAll()
        joinedGroupIDs.removeAll()
        requestedGroupIDs.removeAll()
        announcements.removeAll()
        dbConnections.removeAll()
        connectionProfiles.removeAll()
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = realtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
            realtimeChannel = nil
        }
        stopMessagingRealtime()
        stopAnnouncementRealtime()
        joinRequests.removeAll()
        notifications.removeAll()
        allListings.removeAll()
        orders.removeAll()
        pendingAdminActions.removeAll()
        name             = ""
        bio              = ""
        profileImage     = nil
        profileImageURL  = nil
        currentUserID    = nil
    }
}
