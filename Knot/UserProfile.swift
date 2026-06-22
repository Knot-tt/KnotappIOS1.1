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
    var stripeConnectId  : String?   = nil
    var name             : String    = ""
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

    // First-load flags — let views show a spinner instead of an empty state
    // ("No knots available") while the very first fetch is still in flight.
    var hasLoadedKnots         = false
    var hasLoadedConversations = false
    var hasLoadedListings      = false

    var joinRequests       : [UUID: [JoinRequest]] = [:]
    var pendingAdminActions: [AdminActionRequest]  = []

    /// Non-nil when a knot admin action (promote/demote/kick) fails — shown as an alert.
    var adminActionError: String? = nil

    // Phase 2 — UUID-based connections from Supabase
    var dbConnections      : [DBConnection] = []
    var connectionProfiles    : [UUID: String] = [:]   // other user's UUID → their name
    var connectionAvatarURLs  : [UUID: String] = [:]   // other user's UUID → profile image URL
    var blockedUserIDs     : Set<UUID>       = []      // UUIDs this user has blocked
    var blockedByUserIDs   : Set<UUID>       = []      // UUIDs who have blocked this user
    private var realtimeTask   : Task<Void, Never>? = nil
    private var realtimeChannel: RealtimeChannelV2? = nil

    // Phase 4 — Messaging realtime (one channel per open ChatView)
    private var messagingRealtimeTask   : Task<Void, Never>? = nil
    private var messagingRealtimeChannel: RealtimeChannelV2? = nil
    private var conversationParticipantRealtimeTask   : Task<Void, Never>? = nil
    private var conversationParticipantRealtimeChannel: RealtimeChannelV2? = nil
    private var conversationMessageRealtimeTask       : Task<Void, Never>? = nil
    private var conversationMessageRealtimeChannel    : RealtimeChannelV2? = nil
    private var conversationRealtimeTask              : Task<Void, Never>? = nil
    private var conversationRealtimeChannel           : RealtimeChannelV2? = nil
    private var isEnsuringKnotChats = false

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
    var profileConnectionCount: Int {
        guard let me = currentUserID else { return 0 }
        return dbConnections.filter { connection in
            connection.status == "accepted" &&
            !blockedUserIDs.contains(connection.requesterId == me ? connection.recipientId : connection.requesterId)
        }.count
    }
    var profileListingCount: Int {
        myListings.filter(\.isActive).count
    }
    var profileKnotCount: Int {
        Set(joinedGroupIDs).union(createdGroups.map(\.id)).count
    }
    var orders     : [KnotOrder]   = []

    // Alerts / Announcements
    var announcements: [Announcement] = []
    /// IDs the user has dismissed. In-memory cache only — source of truth is Supabase
    /// (announcement_reads.is_dismissed), so the experience is identical across devices.
    var dismissedAnnouncementIDs: Set<UUID> = []

    // First-launch welcome sheet — stored in Supabase (profiles.has_seen_welcome)
    // so the user sees it once across all devices, not once per device.
    var hasSeenWelcome: Bool = false

    // Conversations / notification deep links
    var conversations             : [Conversation] = []
    var pendingChatConversationID : UUID?           = nil
    var pendingOrderNotificationID: String?         = nil
    /// Toggled to ask the orders sheet (MyOrdersView) to dismiss itself back to
    /// the Hub — e.g. after a meetup proposal is accepted.
    var closeOrdersFlowSignal     : Bool            = false

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
            // Self-register in the UUID → name cache so member-row UUID lookups
            // (used everywhere for "is this me?" / privilege checks) work for self too.
            connectionProfiles[userID] = db.name
            if let url = db.profileImage { connectionAvatarURLs[userID] = url }
            bio                    = db.bio
            street = ""; city = ""; postalCode = ""; country = ""
            isPrivateAccount       = db.isPrivate
            showKnotsOnProfile     = db.showKnots
            showListingsOnProfile  = db.showListings
            showConnectionsOnProfile = db.showConnections
            stripeConnectId        = db.stripeConnectId
            hasSeenWelcome         = db.hasSeenWelcome
            profileImageURL        = db.profileImage
            // Download the image for in-memory display if a URL exists.
            // Validate the URL is from the expected Supabase Storage domain before fetching —
            // prevents a compromised DB row from directing the app to an attacker-controlled host.
            if let urlString = db.profileImage,
               let url = URL(string: urlString),
               let host = url.host,
               host.hasSuffix(".supabase.co") || host.hasSuffix(".supabase.in") {
                // Download the avatar OFF the critical path — it must never delay
                // the data loads that the tabs need.
                Task { [weak self] in
                    if let (data, _) = try? await URLSession.shared.data(from: url) {
                        self?.profileImage = UIImage(data: data)
                    }
                }
            }

            // NOTE: these loads run SEQUENTIALLY on purpose. Firing them
            // concurrently (async let) deadlocks supabase-swift's auth/token layer
            // under parallel requests and the loads never return — leaving Knots/
            // Messages stuck empty. Keep them one-at-a-time.
            await loadConnections()
            await loadBlockedUsers()
            startConnectionRealtime()
            await loadKnots()
            await loadConversations()
            startConversationListRealtime()
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

        // Restore cached data immediately so the UI is populated before the
        // network round-trip completes. The Supabase fetch below will overwrite
        // this with fresh data.
        restoreConnectionsCache()

        do {
            let rows = try await ConnectionService.fetchAll()

            // Refresh names/avatars for EVERY connection, not just ones missing
            // from the cache. A connection may have changed their name or photo
            // on another device (e.g. Android) — fetching only cache misses
            // would leave the stale value on screen forever.
            let otherIDs = Array(Set(rows.compactMap { c -> UUID? in
                c.requesterId == me ? c.recipientId : c.requesterId
            }))

            if !otherIDs.isEmpty {
                let profiles = try await ProfileService.fetchMultiple(userIDs: otherIDs)
                for p in profiles {
                    connectionProfiles[p.id]  = p.name
                    // Assigning nil clears a removed avatar; non-nil updates it.
                    connectionAvatarURLs[p.id] = p.profileImage
                }
            }

            // Atomic update: only replace dbConnections once names are resolved,
            // so the computed `connections` property never returns [] mid-flight.
            dbConnections = rows

            // Persist to disk so the next launch shows data instantly.
            saveConnectionsCache()
        } catch {
            print("[UserProfile] loadConnections error: \(error)")
        }
    }

    // MARK: - Connections cache (UserDefaults)

    private enum CacheKey {
        static let dbConnections        = "cachedDBConnections_v1"
        static let connectionProfiles   = "cachedConnectionProfiles_v1"
        static let connectionAvatarURLs = "cachedConnectionAvatarURLs_v1"
    }

    private func saveConnectionsCache() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(dbConnections) {
            defaults.set(data, forKey: CacheKey.dbConnections)
        }
        let stringProfiles = Dictionary(uniqueKeysWithValues:
            connectionProfiles.map { (k, v) in (k.uuidString, v) })
        if let data = try? JSONEncoder().encode(stringProfiles) {
            defaults.set(data, forKey: CacheKey.connectionProfiles)
        }
        let stringAvatars = Dictionary(uniqueKeysWithValues:
            connectionAvatarURLs.map { (k, v) in (k.uuidString, v) })
        if let data = try? JSONEncoder().encode(stringAvatars) {
            defaults.set(data, forKey: CacheKey.connectionAvatarURLs)
        }
    }

    private func restoreConnectionsCache() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: CacheKey.dbConnections),
           let rows = try? JSONDecoder().decode([DBConnection].self, from: data) {
            dbConnections = rows
        }
        if let data = defaults.data(forKey: CacheKey.connectionProfiles),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in dict {
                if let uuid = UUID(uuidString: key) { connectionProfiles[uuid] = value }
            }
        }
        if let data = defaults.data(forKey: CacheKey.connectionAvatarURLs),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in dict {
                if let uuid = UUID(uuidString: key) { connectionAvatarURLs[uuid] = value }
            }
        }
    }

    // MARK: - Blocked users

    func loadBlockedUsers() async {
        do {
            let ids = try await SettingsService.fetchBlockedUserIDs()
            blockedUserIDs = Set(ids)
        } catch {
            print("[UserProfile] loadBlockedUsers error: \(error)")
        }
    }

    /// Blocks `userID`, removes any connection with them, and hides their conversation.
    func blockUser(userID: UUID) async {
        // Optimistic update — hide the user immediately so the UI responds
        // even before the Supabase round-trip completes.
        blockedUserIDs.insert(userID)

        do {
            // Persist to Supabase (uses ON CONFLICT DO NOTHING if row exists)
            try await SettingsService.block(userID: userID)

            // Remove any existing connection so they vanish from the connections list
            if let conn = dbConnections.first(where: {
                $0.requesterId == userID || $0.recipientId == userID
            }) {
                try? await ConnectionService.remove(connectionID: conn.id)
            }
            await loadConnections()
        } catch {
            // Keep the local block even if Supabase failed — it will be retried
            // next time blockUser is called or on next launch if Supabase recovers.
            print("[UserProfile] blockUser error: \(error)")
        }
    }

    func unblockUser(userID: UUID) async {
        blockedUserIDs.remove(userID)   // optimistic
        do {
            try await SettingsService.unblock(userID: userID)
        } catch {
            blockedUserIDs.insert(userID)   // revert on failure
            print("[UserProfile] unblockUser error: \(error)")
        }
    }

    /// Call when opening a 1-to-1 chat to discover if the other person has blocked us.
    func checkIfBlockedBy(userID: UUID) async {
        let blocked = await SettingsService.isBlockedBy(userID: userID)
        if blocked {
            blockedByUserIDs.insert(userID)
        } else {
            blockedByUserIDs.remove(userID)
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
            let channel = supabase.realtimeV2.channel("connections:\(me)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "connections"
            )
            try? await channel.subscribeWithError()
            realtimeChannel = channel
            for await _ in changes {
                await loadConnections()
            }
        }
    }

    // MARK: - Phase 3: Knots

    func loadKnots() async {
        defer { hasLoadedKnots = true }
        do {
            let (knots, members) = try await KnotService.fetchJoined()

            // Fetch all public knots for "All Knots" tab
            let allPublicDBKnots = try await KnotService.fetchPublic()

            // Collect all unique creator IDs across joined + public knots
            let allKnotsForNames = knots + allPublicDBKnots
            let creatorIDs = Array(Set(allKnotsForNames.map(\.creatorId)))
            let creatorProfiles = try await ProfileService.fetchMultiple(userIDs: creatorIDs)
            let creatorNames: [UUID: String] = Dictionary(uniqueKeysWithValues: creatorProfiles.map { ($0.id, $0.name) })

            func toCommunityGroup(_ knot: DBKnot) -> CommunityGroup {
                let ageGroup = AgeGroup(rawValue: knot.ageGroup) ?? .any
                let payType: KnotPaymentType = {
                    switch knot.paymentType {
                    case "join":        return .join
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
                    creatorID                  : knot.creatorId,
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
                group.imageURL    = knot.imageUrl
                group.ratingSum   = knot.ratingSum
                group.ratingCount = knot.ratingCount
                return group
            }

            let joinedGroups = knots.map { toCommunityGroup($0) }
            let creatorKnotIDs = Set(members.filter { $0.role == "creator" }.map(\.knotId))
            let newCreatedGroups = joinedGroups.filter { creatorKnotIDs.contains($0.id) }
            // Preserve member/admin data already loaded by loadKnotMembers — loadKnots
            // rebuilds groups from scratch and would otherwise wipe coAdminNames/coAdminIDs/
            // memberUUIDs/memberNames that are fetched separately.
            createdGroups = newCreatedGroups.map { newGroup in
                if let existing = createdGroups.first(where: { $0.id == newGroup.id }) {
                    var g = newGroup
                    if !existing.memberNames.isEmpty  { g.memberNames  = existing.memberNames  }
                    if !existing.coAdminNames.isEmpty { g.coAdminNames = existing.coAdminNames }
                    if !existing.coAdminIDs.isEmpty   { g.coAdminIDs   = existing.coAdminIDs   }
                    if !existing.memberUUIDs.isEmpty  { g.memberUUIDs  = existing.memberUUIDs  }
                    return g
                }
                return newGroup
            }
            joinedGroupIDs = Set(joinedGroups.map(\.id))
            publicKnots    = allPublicDBKnots.map { toCommunityGroup($0) }

            // Mark the knots where I'm a co-admin so `isCoAdmin` is true immediately —
            // otherwise coAdminIDs stays empty until loadKnotMembers runs, but that load
            // is itself gated on being an admin (chicken-and-egg), so the Manage button
            // would never appear. `members` are MY own knot_members rows (with my role).
            if let me = currentUserID {
                let myCoAdminKnotIDs = Set(members.filter { $0.role == "co_admin" }.map(\.knotId))
                for i in publicKnots.indices where myCoAdminKnotIDs.contains(publicKnots[i].id) {
                    publicKnots[i].coAdminIDs.insert(me)
                }
            }
        } catch {
            print("[UserProfile] loadKnots error: \(error)")
        }
    }

    func addKnot(_ group: CommunityGroup) {
        createdGroups.append(group)
        joinedGroupIDs.insert(group.id)
    }

    /// Submit (or change) the current user's star rating for a knot, then refresh
    /// the knot's aggregate so the 5-star display updates immediately.
    func submitKnotRating(knotID: UUID, rating: Int) async throws {
        try await KnotRatingService.submit(knotID: knotID, rating: rating)
        let agg = try await KnotRatingService.fetchAggregate(knotID: knotID)
        if let i = publicKnots.firstIndex(where: { $0.id == knotID }) {
            publicKnots[i].ratingSum   = agg.sum
            publicKnots[i].ratingCount = agg.count
        }
        if let i = createdGroups.firstIndex(where: { $0.id == knotID }) {
            createdGroups[i].ratingSum   = agg.sum
            createdGroups[i].ratingCount = agg.count
        }
    }

    /// Domain errors the UI can surface to the user. Anything else falls back
    /// to a generic "Couldn't join — please try again" message.
    enum JoinKnotError: LocalizedError {
        case notSignedIn
        case atCapacity(max: Int)
        case ageRestricted(min: Int, max: Int)
        case other(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Please sign in to join Knots."
            case .atCapacity(let m): return "This Knot is full (max \(m) members)."
            case .ageRestricted(let lo, let hi): return "You must be aged \(lo)–\(hi) to join this Knot."
            case .other(let s): return s
            }
        }
    }

    /// Parse a Supabase / Postgres / Edge Function error into one of our typed errors.
    private func translateJoinError(_ error: Error) -> JoinKnotError {
        var combined = "\(error)"   // include underlying details

        // Edge functions return `{"error":"…"}` JSON bodies. Extract the actual
        // message so the user sees "Creator hasn't set up payouts yet" instead
        // of the raw JSON, and so the trigger-message tests below match.
        if let data = combined.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = dict["error"] as? String {
            combined = msg
        }
        // Some PostgrestError bodies are pretty-printed structs that nest the
        // `message:` field — pull that out too.
        if let m = combined.range(of: #"message[^:]*:\s*"([^"]+)""#, options: .regularExpression) {
            let extracted = combined[m]
                .replacingOccurrences(of: #"message[^:]*:\s*""#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !extracted.isEmpty { combined = extracted }
        }

        let lower = combined.lowercased()

        if lower.contains("at capacity") || lower.contains("knot is full") {
            if let m = combined.range(of: #"max (\d+)"#, options: .regularExpression) {
                let n = Int(combined[m].replacingOccurrences(of: "max ", with: "")) ?? 0
                return .atCapacity(max: n)
            }
            return .atCapacity(max: 0)
        }
        if lower.contains("aged") {
            let nums = combined.matches(of: #/\d+/#)
            let ints = nums.compactMap { Int($0.output) }
            if ints.count >= 2 { return .ageRestricted(min: ints[0], max: ints[1]) }
            return .ageRestricted(min: 13, max: 99)
        }
        if lower.contains("already a member") {
            return .other("You're already a member of this Knot.")
        }
        if lower.contains("not authenticated") || lower.contains("unauthorized") || lower.contains("401") {
            return .notSignedIn
        }

        // Fall back to the cleaned-up message — much more useful than "try again".
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return .other(trimmed.isEmpty ? "Couldn't join. Please try again." : trimmed)
    }

    func joinKnot(_ group: CommunityGroup) async throws {
        guard let me = currentUserID else { throw JoinKnotError.notSignedIn }

        if group.requiresApproval {
            // Submit a join request — delete any stale rejected/cancelled row first
            // so the unique constraint on (knot_id, applicant_id) doesn't block re-submission.
            struct JoinRequestInsert: Encodable {
                let knot_id, applicant_id: UUID
            }
            do {
                _ = try? await supabase
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
                throw translateJoinError(error)
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
                await ensureJoinedKnotChatsPresent()
            } catch {
                throw translateJoinError(error)
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
        guard let me = currentUserID else {
            print("[UserProfile] removeConnection: no current user")
            return
        }
        guard let conn = dbConnections.first(where: {
            ($0.requesterId == me && $0.recipientId == userID) ||
            ($0.requesterId == userID && $0.recipientId == me)
        }) else {
            print("[UserProfile] removeConnection: no connection row found for userID=\(userID), dbConnections.count=\(dbConnections.count)")
            return
        }
        do {
            try await ConnectionService.remove(connectionID: conn.id)
            dbConnections.removeAll { $0.id == conn.id }
            // Refresh so derived arrays (connections, connectionProfiles) stay consistent
            await loadConnections()
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
                isPrivate: isPrivateAccount,
                showKnots: showKnotsOnProfile,
                showListings: showListingsOnProfile,
                showConnections: showConnectionsOnProfile
            )
            try await ProfileService.save(update)
            // Profile name may have changed — refresh the denormalised "by …" string
            // on every knot the user created so the UI updates immediately.
            refreshOwnKnotAdminNames()
        } catch {
            print("[UserProfile] saveProfileToSupabase error: \(error.localizedDescription)")
        }
    }

    func saveProfilePreferencesToSupabase() {
        Task { await saveProfileToSupabase() }
    }

    /// Rewrites every cached display name that references the current user, so a
    /// profile rename is reflected immediately everywhere in the app — knot cards,
    /// knot detail "by …" labels, conversation member lists, group chat creator
    /// labels, co-admin lists, etc. — without waiting for the next server round-trip.
    ///
    /// IDENTITY (UUIDs) is never touched. Only DISPLAY strings.
    func refreshOwnKnotAdminNames() {
        guard let me = currentUserID else { return }
        let newName = name

        // Update the global UUID → name cache first so any later UUID lookup uses the new name.
        connectionProfiles[me] = newName

        // Knot cards / detail headers — "by …" label
        for i in publicKnots.indices where publicKnots[i].creatorID == me {
            publicKnots[i].adminName = newName
        }
        for i in createdGroups.indices where createdGroups[i].creatorID == me {
            createdGroups[i].adminName = newName
        }
        // Knot member name lists (co-admin list, member list, name→UUID lookup)
        rewriteOwnNameInGroupLists(in: &publicKnots, oldName: connectionProfiles[me] ?? "", newName: newName, meID: me)
        rewriteOwnNameInGroupLists(in: &createdGroups, oldName: connectionProfiles[me] ?? "", newName: newName, meID: me)

        // Conversations — DM participant name, group member list, group creator/admin labels
        for i in conversations.indices {
            // DM other-party name (when we open conversations we created, our name may appear here)
            if conversations[i].participantID == me {
                conversations[i].participantName = newName
            }
            // Group member names
            conversations[i].participants = conversations[i].participants.map {
                conversations[i].memberIDsByName[$0] == me ? newName : $0
            }
            // Group creator / admin display
            if conversations[i].creatorID == me {
                conversations[i].creatorName = newName
            }
            // adminNames is a display-only mirror of adminIDs — recompute it from connectionProfiles.
            conversations[i].adminNames = Array(conversations[i].adminIDs).compactMap {
                $0 == me ? newName : connectionProfiles[$0]
            }
            // Rebuild the memberIDsByName lookup with the renamed entry.
            var rebuilt: [String: UUID] = [:]
            for (n, uid) in conversations[i].memberIDsByName {
                let displayName = (uid == me) ? newName : n
                rebuilt[displayName] = uid
            }
            conversations[i].memberIDsByName = rebuilt
        }

        // Hub listings — "sellerName" label on cards / detail.
        for i in allListings.indices where allListings[i].sellerID == me {
            allListings[i].sellerName = newName
        }
        // Sent announcements — "by …" attribution.
        for i in announcements.indices where announcements[i].sender == connectionProfiles[me] || announcements[i].sender == name {
            announcements[i].sender = newName
        }
    }

    private func rewriteOwnNameInGroupLists(in groups: inout [CommunityGroup], oldName: String, newName: String, meID: UUID) {
        for i in groups.indices {
            // coAdminNames — mirror of coAdminIDs; replace my entry if present
            if groups[i].coAdminIDs.contains(meID) {
                groups[i].coAdminNames = groups[i].coAdminNames.map { $0 == oldName ? newName : $0 }
            }
            // memberNames — replace if my UUID is mapped to my old name
            if let oldLookup = groups[i].memberUUIDs.first(where: { $0.value == meID })?.key,
               oldLookup != newName {
                groups[i].memberNames = groups[i].memberNames.map { $0 == oldLookup ? newName : $0 }
                groups[i].memberUUIDs.removeValue(forKey: oldLookup)
                groups[i].memberUUIDs[newName] = meID
            }
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
                    isPrivate: isPrivateAccount,
                    showKnots: showKnotsOnProfile,
                    showListings: showListingsOnProfile,
                    showConnections: showConnectionsOnProfile
                ))
                print("[UserProfile] uploadProfileImage: profile_image written to DB OK")
                // Same DB write may have included a renamed `name`; refresh denormalised
                // "by …" labels on every knot the user created.
                refreshOwnKnotAdminNames()
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
    func uploadKnotCoverImage(knotID: UUID, image: UIImage) async throws -> String {
        print("[UserProfile] uploadKnotCoverImage CALLED for knotID=\(knotID)")
        guard currentUserID != nil else {
            print("[UserProfile] uploadKnotCoverImage: NO currentUserID")
            throw AuthError.sessionMissing
        }
        // 1) Upload to Storage
        let url: String
        do {
            url = try await ProfileService.uploadKnotCoverImage(knotID: knotID, image: image)
            print("[UserProfile] uploadKnotCoverImage: Storage upload OK → \(url)")
        } catch {
            print("[UserProfile] uploadKnotCoverImage: Storage upload FAILED → \(error)")
            throw error
        }
        // 2) Write the URL to the knots table
        do {
            try await KnotService.updateImageURL(knotID: knotID, url: url)
            print("[UserProfile] uploadKnotCoverImage: DB image_url write OK")
        } catch {
            print("[UserProfile] uploadKnotCoverImage: DB image_url write FAILED → \(error)")
            throw error
        }
        // 3) Update local state with cache-busted URL
        let busted = url + "?t=\(Int(Date().timeIntervalSince1970))"
        if let idx = createdGroups.firstIndex(where: { $0.id == knotID }) {
            createdGroups[idx].imageURL = busted
        }
        if let idx = publicKnots.firstIndex(where: { $0.id == knotID }) {
            publicKnots[idx].imageURL = busted
        }
        return busted
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
            // IDENTITY (UUID) — co-admin checks use this so renames can't grant or revoke admin power.
            let coAdminIDs   : Set<UUID> = Set(members.filter { $0.role == "co_admin" }.map(\.userId))
            let memberUUIDs = Dictionary(
                members.compactMap { m -> (String, UUID)? in
                    guard let name = nameByID[m.userId] else { return nil }
                    return (name, m.userId)
                },
                uniquingKeysWith: { first, _ in first }
            )
            let memberLastPaidAt: [UUID: Date] = Dictionary(
                members.compactMap { m -> (UUID, Date)? in
                    guard let d = m.lastPaidAt else { return nil }
                    return (m.userId, d)
                },
                uniquingKeysWith: { first, _ in first }
            )

            if let gi = createdGroups.firstIndex(where: { $0.id == knotID }) {
                createdGroups[gi].memberCount      = realCount
                createdGroups[gi].memberNames      = memberNames
                createdGroups[gi].coAdminNames     = coAdminNames
                createdGroups[gi].coAdminIDs       = coAdminIDs
                createdGroups[gi].memberUUIDs      = memberUUIDs
                createdGroups[gi].memberLastPaidAt = memberLastPaidAt
            }
            if let pi = publicKnots.firstIndex(where: { $0.id == knotID }) {
                publicKnots[pi].memberCount      = realCount
                publicKnots[pi].memberNames      = memberNames
                publicKnots[pi].coAdminNames     = coAdminNames
                publicKnots[pi].coAdminIDs       = coAdminIDs
                publicKnots[pi].memberUUIDs      = memberUUIDs
                publicKnots[pi].memberLastPaidAt = memberLastPaidAt
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

        // Optimistic local update
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

        // Persist to database
        let targetName = req.targetMemberName
        let targetID   = createdGroups[gi].memberUUIDs[targetName]
        let groupID    = req.groupID
        Task {
            do {
                guard let uid = targetID else { return }
                switch req.actionType {
                case .makeAdmin:
                    try await KnotService.setCoAdmin(knotID: groupID, userID: uid, isAdmin: true)
                case .dismissAdmin:
                    try await KnotService.setCoAdmin(knotID: groupID, userID: uid, isAdmin: false)
                case .kick:
                    try await KnotService.kickMember(knotID: groupID, userID: uid)
                }
            } catch {
                print("[UserProfile] approveAdminAction DB error: \(error)")
            }
        }
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
        // Switch tab immediately for responsive feel
        selectedTab = .messages
        Task {
            do {
                // Server-side find-or-create. Ensures the caller is a participant
                // (RLS gate for the upcoming insert when they send a message).
                let convID = try await MessagingService.findOrCreateKnotChat(
                    knotID: knotID, knotName: knotName
                )

                // Reload conversations so the new/joined chat appears in the list
                await loadConversations()

                // If the local list still doesn't have it for any reason, insert a stub
                if !conversations.contains(where: { $0.id == convID }) {
                    var c = Conversation(isGroup: true, groupName: "\(knotName) Chat", participants: [], messages: [])
                    c.id             = convID
                    c.sourceKnotID   = knotID
                    c.sourceKnotName = knotName
                    conversations.insert(c, at: 0)
                }
                pendingChatConversationID = convID
            } catch {
                print("[UserProfile] openKnotGroupChat error: \(error)")
            }
        }
    }

    func renameConversation(id convID: UUID, to newName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupName = newName
        Task {
            do { try await MessagingService.renameGroup(conversationID: convID, newName: newName) }
            catch { print("[UserProfile] renameConversation DB error: \(error)") }
        }
    }

    /// Update a group chat's name and description together (admin/creator only).
    func updateGroupDetails(id convID: UUID, name: String, description: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupName        = name
        conversations[idx].groupDescription = description
        Task {
            do { try await MessagingService.updateGroupInfo(conversationID: convID, name: name, description: description) }
            catch { print("[UserProfile] updateGroupDetails DB error: \(error)") }
        }
    }

    func updateConversationImage(id convID: UUID, image: UIImage?) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupImage = image
        guard let img = image else { return }
        Task {
            do {
                let url = try await MessagingService.uploadGroupImage(conversationID: convID, img)
                if let i = conversations.firstIndex(where: { $0.id == convID }) {
                    conversations[i].groupImageURL = url
                }
            }
            catch { print("[UserProfile] updateConversationImage error: \(error)") }
        }
    }

    func makeAdminInConversation(id convID: UUID, memberName: String) {
        // Resolve UUID from this conversation's own member map — much safer than the
        // global connectionProfiles reverse lookup which can mis-resolve when two
        // users share a display name (impersonation vector).
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        guard let targetID = conversations[idx].memberIDsByName[memberName] else {
            print("[UserProfile] makeAdminInConversation: no UUID for \(memberName)")
            return
        }
        // Refuse to demote a non-existent admin (defensive)
        if !conversations[idx].adminIDs.contains(targetID) {
            conversations[idx].adminIDs.insert(targetID)
            conversations[idx].adminNames.append(memberName)
        }
        Task {
            try? await MessagingService.updateParticipantAdmin(conversationID: convID, userID: targetID, isAdmin: true)
        }
    }

    func demoteAdminInConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        guard let targetID = conversations[idx].memberIDsByName[memberName] else {
            print("[UserProfile] demoteAdminInConversation: no UUID for \(memberName)")
            return
        }
        // Creator can never be demoted — UUID compare, not name compare
        guard conversations[idx].creatorID != targetID else { return }
        conversations[idx].adminIDs.remove(targetID)
        conversations[idx].adminNames.removeAll { $0 == memberName }
        Task {
            try? await MessagingService.updateParticipantAdmin(conversationID: convID, userID: targetID, isAdmin: false)
        }
    }

    func kickFromConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        guard let targetID = conversations[idx].memberIDsByName[memberName] else {
            print("[UserProfile] kickFromConversation: no UUID for \(memberName)")
            return
        }
        // Creator can never be kicked — UUID compare
        guard conversations[idx].creatorID != targetID else { return }
        conversations[idx].participants.removeAll { $0 == memberName }
        conversations[idx].adminNames.removeAll   { $0 == memberName }
        conversations[idx].adminIDs.remove(targetID)
        conversations[idx].memberIDsByName.removeValue(forKey: memberName)
        if let knotID = conversations[idx].sourceKnotID,
           let gi = createdGroups.firstIndex(where: { $0.id == knotID }) {
            createdGroups[gi].memberNames.removeAll  { $0 == memberName }
            createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
            createdGroups[gi].coAdminIDs.remove(targetID)
        }
        // TODO: Phase 4 — update conversation_participants.has_left = true; Phase 3 — remove from knot_members
    }

    /// User-initiated "delete chat" — hides the conversation from this user's list.
    /// Same server semantics as leaving (sets has_left=true). The other party still
    /// sees the chat in their list; new messages from them don't reappear for us.
    func deleteConversation(id convID: UUID) {
        // Remove from local feed immediately for responsive UI.
        conversations.removeAll { $0.id == convID }
        Task {
            do { try await MessagingService.leaveConversation(conversationID: convID) }
            catch { print("[UserProfile] deleteConversation error: \(error)") }
        }
    }

    /// Set the favourite flag on a conversation. Updates locally first so the
    /// swipe feels instant, then persists; reverts the local change on failure.
    func setConversationFavourite(id convID: UUID, isFavourite: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].isFavourite = isFavourite
        Task {
            do {
                try await MessagingService.setFavourite(conversationID: convID, isFavourite: isFavourite)
            } catch {
                print("[UserProfile] setConversationFavourite error: \(error)")
                if let i = conversations.firstIndex(where: { $0.id == convID }) {
                    conversations[i].isFavourite = !isFavourite
                }
            }
        }
    }

    func leaveConversation(id convID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        guard let me = currentUserID else { return }
        // UUID compare for "am I the creator?" so renames don't break the transfer logic.
        if conversations[idx].creatorID == me {
            // Pick a new creator: prefer existing admin, otherwise any remaining member.
            let otherAdminIDs = conversations[idx].adminIDs.filter { $0 != me }
            if let newCreatorID = otherAdminIDs.randomElement() {
                conversations[idx].creatorID = newCreatorID
                conversations[idx].creatorName = connectionProfiles[newCreatorID] ?? ""
            } else {
                // Pick from remaining participants by UUID via the member-ID map
                let otherIDs = conversations[idx].memberIDsByName.values.filter { $0 != me }
                if let newCreatorID = otherIDs.randomElement() {
                    conversations[idx].creatorID = newCreatorID
                    conversations[idx].creatorName = connectionProfiles[newCreatorID] ?? ""
                    conversations[idx].adminIDs.insert(newCreatorID)
                    if let nn = connectionProfiles[newCreatorID] {
                        conversations[idx].adminNames.append(nn)
                    }
                }
            }
        }
        // Remove self from all member lists — UUID-based, then mirror to name lists.
        conversations[idx].adminIDs.remove(me)
        conversations[idx].adminNames.removeAll { $0 == name }
        conversations[idx].participants.removeAll { $0 == name }
        conversations[idx].memberIDsByName = conversations[idx].memberIDsByName.filter { $0.value != me }
        let systemMsg = ChatMessage(text: "\(name) left the group.", sender: "system", senderID: nil, timestamp: Date(), isSystem: true)
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

    // (deleteConversation is defined above — it now also calls
    //  MessagingService.leaveConversation so the chat hides server-side too.)

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

    /// True if the current user is the creator OR a co-admin of the knot.
    /// This is the client mirror of the DB `is_knot_admin()` function and is the
    /// single source of truth for "do I have management powers on this knot".
    func isKnotAdmin(_ knotID: UUID) -> Bool {
        guard let me = currentUserID, let g = managedKnotSnapshot(knotID) else { return false }
        return g.creatorID == me || g.coAdminIDs.contains(me)
    }

    /// Read a knot from whichever collection holds it — `createdGroups` for the
    /// creator, `publicKnots` for a co-admin who didn't create it.
    func managedKnotSnapshot(_ knotID: UUID) -> CommunityGroup? {
        createdGroups.first(where: { $0.id == knotID }) ?? publicKnots.first(where: { $0.id == knotID })
    }

    /// Apply a mutation to a knot in every collection that holds it, so the
    /// creator-owned (createdGroups) and co-admin-managed (publicKnots) copies
    /// stay in sync.
    private func mutateManagedKnot(_ knotID: UUID, _ body: (inout CommunityGroup) -> Void) {
        if let i = createdGroups.firstIndex(where: { $0.id == knotID }) { body(&createdGroups[i]) }
        if let i = publicKnots.firstIndex(where: { $0.id == knotID })   { body(&publicKnots[i]) }
    }

    func kickMemberFromKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        // Resolve UUID from THIS knot's member map — avoids the global-reverse-lookup
        // impersonation hole where two users share a display name.
        guard let targetID = createdGroups[gi].memberUUIDs[memberName] else {
            print("[UserProfile] kickMemberFromKnot: no UUID for \(memberName)")
            return
        }
        // Refuse to kick the creator (defensive; server RLS also enforces this)
        guard createdGroups[gi].creatorID != targetID else { return }
        createdGroups[gi].memberNames.removeAll  { $0 == memberName }
        createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
        createdGroups[gi].coAdminIDs.remove(targetID)
        createdGroups[gi].memberUUIDs.removeValue(forKey: memberName)
        if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
            conversations[ci].participants.removeAll { $0 == memberName }
            conversations[ci].adminNames.removeAll   { $0 == memberName }
            conversations[ci].adminIDs.remove(targetID)
            conversations[ci].memberIDsByName.removeValue(forKey: memberName)
        }
        // Persist to database
        Task {
            do {
                try await KnotService.kickMember(knotID: groupID, userID: targetID)
            } catch {
                print("[UserProfile] kickMemberFromKnot error: \(error)")
            }
        }
    }

    func makeCoAdminInKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        guard let targetID = createdGroups[gi].memberUUIDs[memberName] else {
            adminActionError = "Couldn't find \(memberName) in this Knot. Try closing and reopening the members list."
            print("[UserProfile] makeCoAdminInKnot: no UUID for \(memberName)")
            return
        }
        // Optimistic local update
        if !createdGroups[gi].coAdminIDs.contains(targetID) {
            createdGroups[gi].coAdminIDs.insert(targetID)
            createdGroups[gi].coAdminNames.append(memberName)
        }
        // Persist to database
        Task {
            do {
                try await KnotService.setCoAdmin(knotID: groupID, userID: targetID, isAdmin: true)
            } catch {
                // Roll back local change on failure
                if let ri = createdGroups.firstIndex(where: { $0.id == groupID }) {
                    createdGroups[ri].coAdminIDs.remove(targetID)
                    createdGroups[ri].coAdminNames.removeAll { $0 == memberName }
                }
                adminActionError = "Couldn't make \(memberName) an admin. \(error.localizedDescription)"
                print("[UserProfile] makeCoAdminInKnot error: \(error)")
            }
        }
    }

    func dismissCoAdminInKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        guard let targetID = createdGroups[gi].memberUUIDs[memberName] else {
            adminActionError = "Couldn't find \(memberName) in this Knot. Try closing and reopening the members list."
            print("[UserProfile] dismissCoAdminInKnot: no UUID for \(memberName)")
            return
        }
        // Optimistic local update
        createdGroups[gi].coAdminIDs.remove(targetID)
        createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
        // Persist to database
        Task {
            do {
                try await KnotService.setCoAdmin(knotID: groupID, userID: targetID, isAdmin: false)
            } catch {
                // Roll back local change on failure
                if let ri = createdGroups.firstIndex(where: { $0.id == groupID }) {
                    createdGroups[ri].coAdminIDs.insert(targetID)
                    if !createdGroups[ri].coAdminNames.contains(memberName) {
                        createdGroups[ri].coAdminNames.append(memberName)
                    }
                }
                adminActionError = "Couldn't remove \(memberName) as admin. \(error.localizedDescription)"
                print("[UserProfile] dismissCoAdminInKnot error: \(error)")
            }
        }
    }

    // Async versions — await the DB write before returning.
    // Return nil on success, or an error string the UI can display.
    @discardableResult
    func makeCoAdminInKnotAsync(groupID: UUID, memberName: String) async -> String? {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else {
            return "Knot not found. Try reopening this screen."
        }
        guard let targetID = createdGroups[gi].memberUUIDs[memberName] else {
            print("[UserProfile] makeCoAdminInKnotAsync: no UUID for '\(memberName)'. keys=\(createdGroups[gi].memberUUIDs.keys.sorted())")
            return "Couldn't find \(memberName) in this Knot. Close the members list and reopen it, then try again."
        }
        do {
            try await KnotService.setCoAdmin(knotID: groupID, userID: targetID, isAdmin: true)
            if let ri = createdGroups.firstIndex(where: { $0.id == groupID }) {
                if !createdGroups[ri].coAdminIDs.contains(targetID) {
                    createdGroups[ri].coAdminIDs.insert(targetID)
                    createdGroups[ri].coAdminNames.append(memberName)
                }
            }
            return nil  // success
        } catch {
            print("[UserProfile] makeCoAdminInKnotAsync error: \(error)")
            return "Couldn't make \(memberName) an admin: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func dismissCoAdminInKnotAsync(groupID: UUID, memberName: String) async -> String? {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else {
            return "Knot not found. Try reopening this screen."
        }
        guard let targetID = createdGroups[gi].memberUUIDs[memberName] else {
            return "Couldn't find \(memberName). Close the members list and reopen it."
        }
        do {
            try await KnotService.setCoAdmin(knotID: groupID, userID: targetID, isAdmin: false)
            if let ri = createdGroups.firstIndex(where: { $0.id == groupID }) {
                createdGroups[ri].coAdminIDs.remove(targetID)
                createdGroups[ri].coAdminNames.removeAll { $0 == memberName }
            }
            return nil
        } catch {
            print("[UserProfile] dismissCoAdminInKnotAsync error: \(error)")
            return "Couldn't remove \(memberName) as admin: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func kickMemberFromKnotAsync(groupID: UUID, memberName: String) async -> String? {
        guard let snap = managedKnotSnapshot(groupID) else {
            return "Knot not found. Try reopening this screen."
        }
        guard let targetID = snap.memberUUIDs[memberName] else {
            return "Couldn't find \(memberName). Close the members list and reopen it."
        }
        guard snap.creatorID != targetID else { return nil }
        do {
            try await KnotService.kickMember(knotID: groupID, userID: targetID)
            mutateManagedKnot(groupID) { g in
                g.memberNames.removeAll  { $0 == memberName }
                g.coAdminNames.removeAll { $0 == memberName }
                g.coAdminIDs.remove(targetID)
                g.memberUUIDs.removeValue(forKey: memberName)
            }
            if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
                conversations[ci].participants.removeAll   { $0 == memberName }
                conversations[ci].adminNames.removeAll     { $0 == memberName }
                conversations[ci].adminIDs.remove(targetID)
                conversations[ci].memberIDsByName.removeValue(forKey: memberName)
            }
            return nil
        } catch {
            print("[UserProfile] kickMemberFromKnotAsync error: \(error)")
            return "Couldn't kick \(memberName): \(error.localizedDescription)"
        }
    }

    // MARK: - Phase 4: Conversations

    func loadConversations() async {
        defer { hasLoadedConversations = true }
        guard let me = currentUserID else { return }
        do {
            let data = try await MessagingService.fetchConversations()

            // Refresh names/avatars for every participant, not just unseen ones,
            // so a rename or new photo made on another device shows up here too.
            var participantIDs: Set<UUID> = []
            for d in data {
                for p in d.participants where p.userId != me {
                    participantIDs.insert(p.userId)
                }
            }
            if !participantIDs.isEmpty {
                let profiles = try await ProfileService.fetchMultiple(userIDs: Array(participantIDs))
                for p in profiles {
                    connectionProfiles[p.id]   = p.name
                    connectionAvatarURLs[p.id] = p.profileImage
                }
            }

            var built: [Conversation] = []
            for d in data {
                let lastReadReference = d.myParticipant.lastReadAt ?? d.myParticipant.joinedAt
                let shouldResurfaceHiddenConversation =
                    d.myParticipant.hasLeft &&
                    d.conversation.updatedAt > lastReadReference.addingTimeInterval(1)

                if shouldResurfaceHiddenConversation {
                    try? await MessagingService.reactivateConversationForCurrentUser(conversationID: d.conversation.id)
                }

                guard !d.myParticipant.hasLeft || shouldResurfaceHiddenConversation else { continue }

                let otherParts = d.participants.filter { $0.userId != me }
                let isGroup    = d.conversation.isGroup

                // IDENTITY (UUID) — used for privilege checks. Survives renames + prevents impersonation.
                let creatorID: UUID? = d.participants.first { $0.isCreator }?.userId
                let adminIDs: Set<UUID> = Set(
                    d.participants.filter { $0.isAdmin && !$0.isCreator }.map(\.userId)
                )

                // DISPLAY (name) — derived live from the latest connectionProfiles lookup.
                let adminNames: [String] = d.participants
                    .filter { $0.isAdmin && !$0.isCreator }
                    .compactMap { connectionProfiles[$0.userId] }
                let creatorName: String = creatorID.flatMap { connectionProfiles[$0] } ?? ""

                // name → UUID lookup for member rows. Built from ALL participants so
                // we can map any displayed name back to a UUID for "is this me?" etc.
                var memberIDsByName: [String: UUID] = [:]
                for p in d.participants {
                    if let n = connectionProfiles[p.userId] {
                        memberIDsByName[n] = p.userId
                    }
                }

                var c = Conversation()
                c.id             = d.conversation.id
                c.isGroup        = isGroup
                c.isFavourite    = d.myParticipant.isFavourite
                c.hasLeft        = false
                c.adminNames     = adminNames
                c.adminIDs       = adminIDs
                c.creatorName    = creatorName
                c.creatorID      = creatorID
                c.memberIDsByName = memberIDsByName
                c.sourceKnotID   = d.conversation.sourceKnotId
                // Authoritative sort key — always comes from the DB so sorting is
                // correct even before loadMessages() populates the messages array.
                c.lastActivityAt = d.conversation.updatedAt

                if isGroup {
                    c.groupName        = d.conversation.groupName ?? ""
                    c.groupDescription = d.conversation.groupDescription ?? ""
                    c.groupImageURL    = d.conversation.groupImageUrl
                    c.participants = otherParts.compactMap { connectionProfiles[$0.userId] }
                } else {
                    let otherID = otherParts.first?.userId
                    c.participantID   = otherID
                    c.participantName = otherID.flatMap { connectionProfiles[$0] } ?? ""
                }

                // Preserve messages already in memory so loadConversations() doesn't
                // wipe the chat history that loadMessages() already fetched. For chats
                // that have not been opened yet, fetch only the newest message so the
                // conversation list can show an accurate preview under the name.
                if let existing = conversations.first(where: { $0.id == c.id }), !existing.messages.isEmpty {
                    c.messages = existing.messages.sorted { $0.timestamp < $1.timestamp }
                }
                if let existing = conversations.first(where: { $0.id == c.id }) {
                    c.groupImage = existing.groupImage
                }
                do {
                    if let latestMessageRow = try await MessagingService.fetchLatestMessage(conversationID: c.id) {
                        let latestMessage = dbMessageToChatMessage(latestMessageRow)
                        if let existingIndex = c.messages.firstIndex(where: { $0.id == latestMessage.id }) {
                            c.messages[existingIndex] = latestMessage
                        } else {
                            c.messages.append(latestMessage)
                        }
                        c.messages.sort { $0.timestamp < $1.timestamp }
                        c.lastActivityAt = max(c.lastActivityAt, latestMessage.timestamp)
                    }
                } catch {
                    print("[UserProfile] fetchLatestMessage error for \(c.id): \(error)")
                }

                // Compute unread from the DB: any conversation whose updated_at is
                // meaningfully newer than the user's last_read_at has unread messages.
                // A 3-second grace period prevents our own just-sent messages from
                // briefly appearing as unread before markConversationRead fires.
                let lastRead = d.myParticipant.lastReadAt
                let convUpdated = d.conversation.updatedAt
                if let lr = lastRead {
                    c.unreadCount = convUpdated > lr.addingTimeInterval(3) ? 1 : 0
                } else {
                    // Never read — flag as unread only if the conversation is older than
                    // a few seconds (so a just-created chat doesn't flash the dot).
                    c.unreadCount = Date().timeIntervalSince(convUpdated) > 3 ? 1 : 0
                }

                built.append(c)
            }

            conversations = built.sorted { $0.lastTimestamp > $1.lastTimestamp }
            await ensureJoinedKnotChatsPresent()
        } catch {
            print("[UserProfile] loadConversations error: \(error)")
        }
    }

    private func ensureJoinedKnotChatsPresent() async {
        guard !isEnsuringKnotChats else { return }
        let joinedGroups = (createdGroups + publicKnots)
            .filter { joinedGroupIDs.contains($0.id) }
        let missingGroups = joinedGroups.filter { group in
            !conversations.contains { $0.isGroup && $0.sourceKnotID == group.id }
        }
        guard !missingGroups.isEmpty else { return }

        isEnsuringKnotChats = true
        defer { isEnsuringKnotChats = false }

        var createdOrJoinedAny = false
        for group in missingGroups {
            do {
                _ = try await MessagingService.findOrCreateKnotChat(knotID: group.id, knotName: group.name)
                createdOrJoinedAny = true
            } catch {
                print("[UserProfile] ensureJoinedKnotChatsPresent error for \(group.id): \(error)")
            }
        }

        guard createdOrJoinedAny else { return }
        do {
            let data = try await MessagingService.fetchConversations()

            var participantIDs: Set<UUID> = []
            for d in data {
                for p in d.participants where p.userId != currentUserID {
                    participantIDs.insert(p.userId)
                }
            }
            if !participantIDs.isEmpty {
                let profiles = try await ProfileService.fetchMultiple(userIDs: Array(participantIDs))
                for p in profiles {
                    connectionProfiles[p.id] = p.name
                    connectionAvatarURLs[p.id] = p.profileImage
                }
            }

            let existingMessagesByConversation = Dictionary(
                uniqueKeysWithValues: conversations.map { ($0.id, $0.messages) }
            )
            conversations = data.map { d in
                let otherParts = d.participants.filter { $0.userId != currentUserID }
                let isGroup = d.conversation.isGroup
                let creatorID: UUID? = d.participants.first { $0.isCreator }?.userId
                let adminIDs: Set<UUID> = Set(
                    d.participants.filter { $0.isAdmin && !$0.isCreator }.map(\.userId)
                )
                let adminNames: [String] = d.participants
                    .filter { $0.isAdmin && !$0.isCreator }
                    .compactMap { connectionProfiles[$0.userId] }
                let creatorName: String = creatorID.flatMap { connectionProfiles[$0] } ?? ""

                var memberIDsByName: [String: UUID] = [:]
                for p in d.participants {
                    if let n = connectionProfiles[p.userId] {
                        memberIDsByName[n] = p.userId
                    }
                }

                var c = Conversation()
                c.id = d.conversation.id
                c.isGroup = isGroup
                c.isFavourite = d.myParticipant.isFavourite
                c.hasLeft = d.myParticipant.hasLeft
                c.adminNames = adminNames
                c.adminIDs = adminIDs
                c.creatorName = creatorName
                c.creatorID = creatorID
                c.memberIDsByName = memberIDsByName
                c.sourceKnotID = d.conversation.sourceKnotId
                c.lastActivityAt = d.conversation.updatedAt

                if isGroup {
                    c.groupName = d.conversation.groupName ?? ""
                    c.groupDescription = d.conversation.groupDescription ?? ""
                    c.groupImageURL    = d.conversation.groupImageUrl
                    c.participants = otherParts.compactMap { connectionProfiles[$0.userId] }
                } else {
                    let otherID = otherParts.first?.userId
                    c.participantID = otherID
                    c.participantName = otherID.flatMap { connectionProfiles[$0] } ?? ""
                }

                c.messages = existingMessagesByConversation[c.id] ?? []
                let lastRead = d.myParticipant.lastReadAt
                let convUpdated = d.conversation.updatedAt
                if let lr = lastRead {
                    c.unreadCount = convUpdated > lr.addingTimeInterval(3) ? 1 : 0
                } else {
                    c.unreadCount = Date().timeIntervalSince(convUpdated) > 3 ? 1 : 0
                }
                return c
            }
        } catch {
            print("[UserProfile] ensureJoinedKnotChatsPresent reload error: \(error)")
        }
    }

    /// Persists last_read_at server-side AND clears the local unread badge.
    /// Called when the chat view opens and on every new message while it stays open.
    func markConversationRead(conversationID: UUID) async {
        if let idx = conversations.firstIndex(where: { $0.id == conversationID }),
           conversations[idx].unreadCount != 0 {
            conversations[idx].unreadCount = 0
        }
        do { try await MessagingService.markConversationRead(conversationID: conversationID) }
        catch { print("[UserProfile] markConversationRead error: \(error)") }
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
                for p in profiles {
                    connectionProfiles[p.id] = p.name
                    if let url = p.profileImage { connectionAvatarURLs[p.id] = url }
                }
            }

            let mapped = dbMessages.map { dbMessageToChatMessage($0) }
            conversations[idx].messages = mapped.sorted { $0.timestamp < $1.timestamp }
            // If new messages arrived (realtime push), bump lastActivityAt so the
            // conversation rises to the top of the list for both DMs and group chats.
            if let newest = conversations[idx].messages.last {
                if newest.timestamp > conversations[idx].lastActivityAt {
                    conversations[idx].lastActivityAt = newest.timestamp
                }
            }
        } catch {
            print("[UserProfile] loadMessages error: \(error)")
        }
    }

    func sendMessage(text: String, conversationID: UUID, replyToID: UUID? = nil) async {
        do {
            var outboundText = text
            if let idx = conversations.firstIndex(where: { $0.id == conversationID }),
               let listingContext = conversations[idx].pendingListingContext {
                outboundText = makeListingContextMessageText(
                    listingID: listingContext.listingID,
                    listingName: listingContext.listingName,
                    body: text
                )
            }
            let dbMsg = try await MessagingService.send(text: outboundText, conversationID: conversationID)
            guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            conversations[idx].pendingListingContext = nil
            let msg = dbMessageToChatMessage(dbMsg)
            // Skip if realtime already delivered it
            if !conversations[idx].messages.contains(where: { $0.id == dbMsg.id }) {
                conversations[idx].messages.append(msg)
                conversations[idx].messages.sort { $0.timestamp < $1.timestamp }
            }
            // Bump sort key so this chat rises to the top of the list immediately.
            conversations[idx].lastActivityAt = Date()
            // Mark as read immediately after sending so our own message doesn't
            // trigger an unread dot on the next loadConversations() call.
            if conversations[idx].unreadCount != 0 { conversations[idx].unreadCount = 0 }
            // Persist last_read_at so the server reflects our send time.
            do { try await MessagingService.markConversationRead(conversationID: conversationID) }
            catch { print("[UserProfile] sendMessage markRead error: \(error)") }
        } catch {
            print("[UserProfile] sendMessage error: \(error)")
        }
    }

    /// Upload one image and persist a chat message row that references its public URL.
    /// Returns true on success — caller removes its optimistic placeholder.
    /// Returns false on failure — caller should leave the placeholder visible so
    /// the user can see something went wrong and try again.
    @discardableResult
    func sendImageMessage(image: UIImage, caption: String = "", conversationID: UUID) async -> Bool {
        do {
            let dbMsg = try await MessagingService.sendImage(image, caption: caption, conversationID: conversationID)
            guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return true }
            let msg = dbMessageToChatMessage(dbMsg)
            // Skip if realtime already delivered it
            if !conversations[idx].messages.contains(where: { $0.id == dbMsg.id }) {
                conversations[idx].messages.append(msg)
                conversations[idx].messages.sort { $0.timestamp < $1.timestamp }
            }
            // Bump sort key so this chat rises to the top of the list immediately.
            conversations[idx].lastActivityAt = Date()
            // Same as sendMessage — keep last_read_at current so our own image
            // doesn't trigger an unread dot on the next loadConversations().
            if conversations[idx].unreadCount != 0 { conversations[idx].unreadCount = 0 }
            do { try await MessagingService.markConversationRead(conversationID: conversationID) }
            catch { print("[UserProfile] sendImageMessage markRead error: \(error)") }
            return true
        } catch {
            print("[UserProfile] sendImageMessage error: \(error)")
            return false
        }
    }

    func sendVideoMessage(fileURL: URL, caption: String = "", conversationID: UUID) async -> Bool {
        do {
            let poster = VideoPoster.make(from: fileURL) ?? UIImage()
            let dbMsg = try await MessagingService.sendVideo(fileURL: fileURL, poster: poster,
                                                             caption: caption, conversationID: conversationID)
            guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return true }
            let msg = dbMessageToChatMessage(dbMsg)
            if !conversations[idx].messages.contains(where: { $0.id == dbMsg.id }) {
                conversations[idx].messages.append(msg)
                conversations[idx].messages.sort { $0.timestamp < $1.timestamp }
            }
            conversations[idx].lastActivityAt = Date()
            if conversations[idx].unreadCount != 0 { conversations[idx].unreadCount = 0 }
            try? await MessagingService.markConversationRead(conversationID: conversationID)
            return true
        } catch {
            print("[UserProfile] sendVideoMessage error: \(error)")
            return false
        }
    }

    func createGroupConversation(name: String, participantNames: [String], groupImage: UIImage?) async {
        let participantIDs = participantNames.compactMap { participantName in
            connectionProfiles.first(where: { $0.value == participantName })?.key
        }
        await createGroupConversation(
            name            : name,
            participantIDs  : participantIDs,
            participantNames: participantNames,
            groupImage      : groupImage
        )
    }

    func createGroupConversation(name: String, participantIDs: [UUID], participantNames: [String], groupImage: UIImage?) async {
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
            let channel = supabase.realtimeV2.channel("messages:\(conversationID)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table : "messages",
                filter: .eq("conversation_id", value: conversationID.uuidString.lowercased())
            )
            try? await channel.subscribeWithError()
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

    func startConversationListRealtime() {
        guard let me = currentUserID else { return }

        conversationParticipantRealtimeTask?.cancel()
        conversationParticipantRealtimeTask = nil
        let oldParticipantChannel = conversationParticipantRealtimeChannel
        conversationParticipantRealtimeChannel = nil
        conversationParticipantRealtimeTask = Task {
            if let old = oldParticipantChannel {
                await supabase.realtimeV2.removeChannel(old)
            }
            let channel = supabase.realtimeV2.channel("conversation-participants:\(me)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "conversation_participants",
                filter: .eq("user_id", value: me.uuidString.lowercased())
            )
            try? await channel.subscribeWithError()
            conversationParticipantRealtimeChannel = channel
            for await _ in changes {
                await loadConversations()
            }
        }

        conversationMessageRealtimeTask?.cancel()
        conversationMessageRealtimeTask = nil
        let oldMessageChannel = conversationMessageRealtimeChannel
        conversationMessageRealtimeChannel = nil
        conversationMessageRealtimeTask = Task {
            if let old = oldMessageChannel {
                await supabase.realtimeV2.removeChannel(old)
            }
            let channel = supabase.realtimeV2.channel("conversation-messages:\(me)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "messages"
            )
            try? await channel.subscribeWithError()
            conversationMessageRealtimeChannel = channel
            for await _ in changes {
                await loadConversations()
            }
        }

        conversationRealtimeTask?.cancel()
        conversationRealtimeTask = nil
        let oldConversationChannel = conversationRealtimeChannel
        conversationRealtimeChannel = nil
        conversationRealtimeTask = Task {
            if let old = oldConversationChannel {
                await supabase.realtimeV2.removeChannel(old)
            }
            let channel = supabase.realtimeV2.channel("conversations:\(me)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "conversations"
            )
            try? await channel.subscribeWithError()
            conversationRealtimeChannel = channel
            for await _ in changes {
                await loadConversations()
            }
        }
    }

    func stopConversationListRealtime() {
        conversationParticipantRealtimeTask?.cancel()
        conversationParticipantRealtimeTask = nil
        if let ch = conversationParticipantRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
            conversationParticipantRealtimeChannel = nil
        }

        conversationMessageRealtimeTask?.cancel()
        conversationMessageRealtimeTask = nil
        if let ch = conversationMessageRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
            conversationMessageRealtimeChannel = nil
        }

        conversationRealtimeTask?.cancel()
        conversationRealtimeTask = nil
        if let ch = conversationRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
            conversationRealtimeChannel = nil
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
        var cm        = ChatMessage(sender: senderName, senderID: msg.senderId, timestamp: msg.createdAt, status: status)
        cm.id         = msg.id
        let parsedListingContext = parseListingContextMessage(msg.text)
        cm.text       = parsedListingContext?.body ?? msg.text
        cm.imageURL   = msg.imageUrl
        cm.videoURL   = msg.videoUrl
        cm.isSystem   = msg.isSystem
        cm.listingContext = parsedListingContext?.context
        cm.isStarred  = msg.isStarred
        if let rid = msg.replyToId { cm.replyToID = rid }
        return cm
    }

    // MARK: - Phase 5: Announcements

    func loadAnnouncements() async {
        do {
            let rows = try await AnnouncementService.fetchForUser()
            // Filter out anything the user has previously dismissed locally
            let visibleRows = rows.filter { !dismissedAnnouncementIDs.contains($0.announcement.id) }
            guard !visibleRows.isEmpty else {
                announcements = []
                return
            }
            let senderIDs = Array(Set(visibleRows.map(\.announcement.senderId)))
            var senderNames: [UUID: String] = [:]
            if let profiles = try? await ProfileService.fetchMultiple(userIDs: senderIDs) {
                for p in profiles { senderNames[p.id] = p.name }
            }
            let allKnots = createdGroups + publicKnots
            let knotNameMap = Dictionary(allKnots.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

            announcements = visibleRows.map { row in
                let decodedBody = AnnouncementBodyCodec.decode(row.announcement.body)
                var a = Announcement(
                    title            : row.announcement.title,
                    body             : decodedBody.body,
                    sender           : senderNames[row.announcement.senderId] ?? "Unknown",
                    senderID         : row.announcement.senderId,
                    date             : Self.formatAnnouncementDate(row.announcement.createdAt),
                    isRead           : row.isRead,
                    knotName         : row.announcement.knotId.flatMap { knotNameMap[$0] } ?? "Knot",
                    isPinned         : row.isPinned,
                    paymentRequestId : row.announcement.paymentRequestId,
                    imageURLs        : decodedBody.imageURLs
                )
                a.id     = row.announcement.id
                a.knotID = row.announcement.knotId
                return a
            }
        } catch {
            print("[UserProfile] loadAnnouncements error: \(error)")
        }
    }

    /// Dismiss a single announcement. Persisted in Supabase (announcement_reads.is_dismissed)
    /// so it stays dismissed across devices.
    func dismissAnnouncement(id: UUID) {
        dismissedAnnouncementIDs.insert(id)
        announcements.removeAll { $0.id == id }
        Task {
            do { try await AnnouncementService.dismiss(announcementID: id) }
            catch { print("[UserProfile] dismissAnnouncement error: \(error)") }
        }
    }

    /// Dismiss every currently-visible announcement ("Clear All"). Persisted in Supabase
    /// so dismissals are mirrored on every device the user signs in on.
    func dismissAllAnnouncements() {
        let ids = announcements.map { $0.id }
        for id in ids { dismissedAnnouncementIDs.insert(id) }
        announcements.removeAll()
        Task {
            do { try await AnnouncementService.dismissAll(announcementIDs: ids) }
            catch { print("[UserProfile] dismissAllAnnouncements error: \(error)") }
        }
    }

    /// Mark the in-app welcome sheet as seen. Persisted in Supabase
    /// (profiles.has_seen_welcome) so it only shows once across all devices.
    func markWelcomeSeen() {
        guard !hasSeenWelcome else { return }
        hasSeenWelcome = true
        Task {
            do { try await ProfileService.markWelcomeSeen() }
            catch { print("[UserProfile] markWelcomeSeen error: \(error)") }
        }
    }

    @discardableResult
    func sendAnnouncement(
        knotID: UUID,
        title: String,
        body: String,
        isPinned: Bool,
        images: [UIImage] = []
    ) async -> Bool {
        print("[UserProfile] sendAnnouncement called — knotID: \(knotID), title: \(title)")
        do {
            try await AnnouncementService.send(
                knotID: knotID,
                title: title,
                body: body,
                isPinned: isPinned,
                images: images
            )
            print("[UserProfile] sendAnnouncement succeeded")
            await loadAnnouncements()
            return true
        } catch {
            print("[UserProfile] sendAnnouncement error: \(error)")
            return false
        }
    }

    func startAnnouncementRealtime() {
        announcementRealtimeTask?.cancel()
        let oldCh = announcementRealtimeChannel
        announcementRealtimeChannel = nil
        announcementRealtimeTask = Task {
            if let old = oldCh { await supabase.realtimeV2.removeChannel(old) }
            let ch = supabase.realtimeV2.channel("announcements")
            let changes = ch.postgresChange(AnyAction.self, schema: "public", table: "announcements")
            try? await ch.subscribeWithError()
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
        defer { hasLoadedListings = true }
        do {
            let existingListings = allListings
            // Public feed: only active listings.
            let activeRows = try await ShopService.fetchActive()
            // Also fetch own listings so newly created ones appear immediately even if
            // the active-feed hasn't propagated yet. We only surface ACTIVE own listings
            // here — deleted (is_active=false) rows are intentionally hidden from the UI.
            let mineRows = (try? await ShopService.fetchMine()) ?? []
            let mineActiveRows = mineRows.filter { $0.isActive }

            // Union of (everyone's active) + (my active not yet in public feed).
            var merged: [UUID: DBShopListing] = [:]
            for r in activeRows   { merged[r.id] = r }
            for r in mineActiveRows { merged[r.id] = r }
            let combinedRows = Array(merged.values)

            let sellerIDs = Array(Set(combinedRows.map { $0.sellerId }))
            var sellerNames: [UUID: String] = [:]
            if let profiles = try? await ProfileService.fetchMultiple(userIDs: sellerIDs) {
                for p in profiles { sellerNames[p.id] = p.name }
            }
            let fetchedListings = combinedRows.map { row in
                ShopListing(
                    id          : row.id,
                    type        : Self.listingTypeFromDB(row.listingType),
                    category    : ShopCategory.fromDB(row.category),
                    condition   : ItemCondition.fromDB(row.condition),
                    name        : row.name,
                    description : row.description,
                    link        : row.link,
                    price       : row.priceCents / 100,
                    sellerName  : sellerNames[row.sellerId] ?? "Unknown",
                    sellerID    : row.sellerId,
                    isActive    : row.isActive,
                    isRecurring : row.isRecurring,
                    acceptsCash : row.acceptsCash,
                    acceptsCard : row.acceptsCard,
                    imageURLs   : row.imageUrls,
                    date        : row.createdAt
                )
            }

            let fetchedIDs = Set(fetchedListings.map(\.id))
            let preservedLocalListings = existingListings.filter { listing in
                listing.isActive &&
                listing.sellerID == currentUserID &&
                !fetchedIDs.contains(listing.id)
            }

            allListings = (fetchedListings + preservedLocalListings)
                .sorted { $0.date > $1.date }
        } catch {
            print("[UserProfile] loadListings error: \(error)")
        }
    }

    /// Restore a previously deleted listing back to active.
    func restoreListing(listingID: UUID) async {
        do {
            try await ShopService.restore(listingID: listingID)
            if let idx = allListings.firstIndex(where: { $0.id == listingID }) {
                allListings[idx].isActive = true
            }
            await loadListings()
        } catch {
            print("[UserProfile] restoreListing error: \(error)")
        }
    }

    func createListing(
        type        : ListingType,
        category    : ShopCategory,
        condition   : ItemCondition,
        name        : String,
        description : String,
        link        : String,
        price       : Int,
        images      : [UIImage],
        isRecurring : Bool = false,
        acceptsCash : Bool = true,
        acceptsCard : Bool = false
    ) async throws {
        do {
            let db = try await ShopService.create(
                type: type, category: category, condition: condition,
                name: name, description: description, link: link,
                price: price, images: images, isRecurring: isRecurring,
                acceptsCash: acceptsCash, acceptsCard: acceptsCard
            )
            let local = ShopListing(
                id          : db.id,
                type        : type,
                category    : category,
                condition   : condition,
                name        : name,
                description : description,
                link        : link,
                price       : price,
                sellerName  : self.name,
                sellerID    : db.sellerId,
                isRecurring : isRecurring,
                acceptsCash : acceptsCash,
                acceptsCard : acceptsCard,
                imageURLs   : db.imageUrls,
                date        : db.createdAt
            )
            allListings.insert(local, at: 0)
        } catch {
            print("[UserProfile] createListing error: \(error)")
            throw error
        }
    }

    func deleteListing(listingID: UUID) async {
        do {
            // Cancel every active order for this listing BEFORE deactivating it,
            // so a buyer never ends up holding a live order against a dead listing.
            // cancel-order releases the buyer's Stripe hold (or refunds a captured
            // payment) and marks the order cancelled.
            //
            // We refetch orders straight from the DB rather than trusting the local
            // `orders` array: the seller may not have opened their orders tab this
            // session, so the in-memory list can be empty or stale.
            let activeStatuses: Set<String> = ["pending", "seller_accepted", "meetup_agreed", "awaiting_confirmation"]
            let affectedIDs = (try? await OrderService.fetchAll())?
                .filter { $0.listingId == listingID && activeStatuses.contains($0.status) }
                .map(\.id) ?? []

            for orderID in affectedIDs {
                try? await OrderService.cancelOrder(orderID: orderID)
            }
            // Drop the cancelled orders from local state so any open list updates instantly.
            if !affectedIDs.isEmpty {
                let cancelledIDs = Set(affectedIDs)
                orders = orders.filter { !cancelledIDs.contains($0.id) }
            }
            try await ShopService.delete(listingID: listingID)
            allListings = allListings.filter { $0.id != listingID }
        } catch {
            print("[UserProfile] deleteListing error: \(error)")
        }
    }

    /// Called when an order completes (escrow released). Deletes the listing unless it
    /// was marked as recurring — recurring listings stay on the Hub after a sale.
    func deleteSoldListing(listingID: UUID) async {
        guard let listing = allListings.first(where: { $0.id == listingID }) else { return }
        guard !listing.isRecurring else { return }  // recurring listings stay up
        await deleteListing(listingID: listingID)
    }

    func updateListing(
        listingID  : UUID,
        type       : ListingType,
        category   : ShopCategory,
        condition  : ItemCondition,
        name       : String,
        description: String,
        link       : String,
        price      : Int
    ) async {
        do {
            try await ShopService.update(
                listingID: listingID,
                type: type, category: category, condition: condition,
                name: name, description: description, link: link, price: price
            )
            // Reflect locally
            if let idx = allListings.firstIndex(where: { $0.id == listingID }) {
                allListings[idx].type        = type
                allListings[idx].category    = category
                allListings[idx].condition   = condition
                allListings[idx].name        = name
                allListings[idx].description = description
                allListings[idx].link        = link
                allListings[idx].price       = price
            }
        } catch {
            print("[UserProfile] updateListing error: \(error)")
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

    /// Unified history row — wraps a shop order for the wallet's order history.
    enum TransactionItem: Identifiable {
        case order(KnotOrder)

        var id: String {
            switch self { case .order(let o): return "order-\(o.id)" }
        }
        var date: Date {
            switch self { case .order(let o): return o.date }
        }
    }

    var transactionHistory: [TransactionItem] {
        orders.map(TransactionItem.order).sorted { $0.date > $1.date }
    }

    func loadOrders() async {
        do {
            let rawRows = try await OrderService.fetchAll()

            // ── Defensive filters ──────────────────────────────────────────────
            // 1. Self-orders: somehow has buyer == seller (shouldn't happen — create-order
            //    blocks it server-side — but a leftover row from older code mustn't appear).
            // 2. Abandoned pre-payment rows: an order is only "real" once Stripe has
            //    confirmed the buyer's card. Until then status stays 'pending' AND no
            //    timestamp past `pending_at` is set. If a row has been pending for a while
            //    with no progress, treat it as abandoned and hide it. cancel-order also
            //    server-side deletes these on PaymentSheet dismissal — this filter just
            //    catches the rare cases (network drop, app killed) it didn't run.
            let now = Date()
            let rows = rawRows.filter { row in
                if row.buyerId == row.sellerId { return false }
                if row.status == "pending" {
                    // A confirmed Stripe payment moves the PI to requires_capture but our
                    // status stays "pending" until the seller accepts. The reliable signal
                    // that a payment actually went through is `paid_at` (stamped client-side
                    // on PaymentSheet success). If it's set, this is a real order — keep it.
                    // Only hide pending orders that were NEVER paid (paid_at nil) and have
                    // been sitting around for >2h — those are abandoned carts that the
                    // cancel-order cleanup didn't catch (network drop, app killed).
                    if row.paidAt == nil && now.timeIntervalSince(row.createdAt) > 7200 {
                        return false
                    }
                }
                return true
            }

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
                if let d = row.disputedAt              { stepDates["disputed"]               = d }
                if let d = row.cancelledAt             { stepDates["cancelled"]              = d }

                return KnotOrder(
                    id            : row.id,
                    listing       : listing,
                    buyerName     : buyerName,
                    sellerName    : sellerName,
                    sellerId      : row.sellerId,
                    buyerId       : row.buyerId,
                    subtotal      : row.subtotalCents,
                    knotFeeRate   : row.knotFeeRate,
                    fulfilment    : FulfilmentMethod.fromDB(row.fulfilment),
                    paymentMethod : row.paymentMethod,
                    address       : row.deliveryAddress,
                    date          : row.createdAt,
                    status        : OrderStatus(rawValue: row.status) ?? .pending,
                    escrow        : row.escrowStatus == "released" ? .released : .held,
                    meetupProposal: proposal,
                    stepDates     : stepDates
                )
            }
        } catch {
            print("[UserProfile] loadOrders error: \(error)")
        }
    }

    // MARK: - Messaging

    func openConversation(with targetName: String,
                          sourceKnotID: UUID? = nil,
                          sourceKnotName: String = "",
                          listingContext: ListingMessageContext? = nil) {
        // Switch tab first so MessagesView mounts its .onChange observer.
        selectedTab = .messages
        pendingChatConversationID = nil

        // Prefer a UUID-keyed existing match (survives name renames). Fall back to name.
        if let existing = conversations.first(where: { c in
            !c.isGroup &&
            (c.participantID.map { connectionProfiles[$0] == targetName } ?? false ||
             c.participantName == targetName)
        }) {
            if let idx = conversations.firstIndex(where: { $0.id == existing.id }), let listingContext {
                conversations[idx].pendingListingContext = listingContext
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                pendingChatConversationID = existing.id
            }
            return
        }

        Task {
            // 1. Already in our name cache?
            var targetID: UUID? = connectionProfiles.first(where: { $0.value == targetName })?.key
            // 2. Otherwise hit the server. Match case-insensitive + trim whitespace so
            //    a small casing/whitespace diff doesn't cause silent failure.
            if targetID == nil {
                let needle = targetName.trimmingCharacters(in: .whitespaces).lowercased()
                if let match = try? await ProfileService.search(query: targetName, limit: 10)
                    .first(where: {
                        $0.name.trimmingCharacters(in: .whitespaces).lowercased() == needle
                    }) {
                    targetID = match.id
                    connectionProfiles[match.id] = match.name
                    if let url = match.profileImage { connectionAvatarURLs[match.id] = url }
                }
            }
            guard let targetID else {
                print("[UserProfile] openConversation: could not resolve UUID for \(targetName)")
                return
            }
            await openConversationInternal(
                targetID: targetID, targetName: targetName,
                sourceKnotID: sourceKnotID, sourceKnotName: sourceKnotName,
                listingContext: listingContext
            )
        }
    }

    /// Preferred entry point when we already have the target's UUID (e.g. from
    /// ShopListing.sellerID, KnotMember row, etc.). Skips the name-search round
    /// trip and the case-sensitivity foot-gun that comes with it.
    func openConversation(withUserID targetID: UUID,
                          name: String,
                          sourceKnotID: UUID? = nil,
                          sourceKnotName: String = "",
                          listingContext: ListingMessageContext? = nil) {
        // Switch tab first so MessagesView mounts and its .onChange observer
        // is ready before we set pendingChatConversationID.
        selectedTab = .messages
        // Clear first so a re-set to the same value still triggers .onChange.
        pendingChatConversationID = nil

        // Existing conversation by UUID — most reliable identifier.
        if let existing = conversations.first(where: { $0.participantID == targetID && !$0.isGroup }) {
            if let idx = conversations.firstIndex(where: { $0.id == existing.id }), let listingContext {
                conversations[idx].pendingListingContext = listingContext
            }
            // Brief delay lets MessagesView mount after the tab switch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                pendingChatConversationID = existing.id
            }
            return
        }
        // Cache the name immediately so the conversation list shows it without flicker.
        connectionProfiles[targetID] = name
        Task {
            await openConversationInternal(
                targetID: targetID, targetName: name,
                sourceKnotID: sourceKnotID, sourceKnotName: sourceKnotName,
                listingContext: listingContext
            )
        }
    }

    @MainActor
    private func openConversationInternal(targetID: UUID, targetName: String,
                                          sourceKnotID: UUID?, sourceKnotName: String,
                                          listingContext: ListingMessageContext? = nil) async {
        do {
            let conv = try await MessagingService.createConversation(
                isGroup       : false,
                groupName     : nil,
                participantIDs: [targetID],
                sourceKnotID  : sourceKnotID
            )
            // If we already have a row with that ID (re-opening), just navigate to it.
            if let existingIdx = conversations.firstIndex(where: { $0.id == conv.id }) {
                pendingChatConversationID = conversations[existingIdx].id
                return
            }
            var c             = Conversation()
            c.id              = conv.id
            c.participantName = targetName
            c.participantID   = targetID                       // critical for avatar + future UUID-based checks
            c.memberIDsByName = [targetName: targetID,
                                 name      : currentUserID ?? UUID()]
            c.sourceKnotID    = sourceKnotID
            c.sourceKnotName  = sourceKnotName
            c.pendingListingContext = listingContext
            conversations.insert(c, at: 0)
            pendingChatConversationID = conv.id
        } catch {
            print("[UserProfile] openConversation error: \(error)")
        }
    }

    /// Deep-link entry point for a tapped message notification. Switches to the
    /// Messages tab, then opens the conversation. The brief delay lets the tab
    /// switch render MessagesView before its navigation `onChange` observes the
    /// new pending ID (otherwise the change can be missed). Clearing first
    /// guarantees a fresh value even if this chat was already the pending one.
    @MainActor
    func openConversationFromNotification(_ conversationID: UUID) {
        selectedTab = .messages
        pendingChatConversationID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pendingChatConversationID = conversationID
        }
    }

    @MainActor
    func openAlertsFromNotification() {
        selectedTab = .alerts
    }

    @MainActor
    func openOrdersFromNotification(orderID: String?) {
        selectedTab = .buy
        pendingOrderNotificationID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pendingOrderNotificationID = orderID ?? ""
        }
    }

    // MARK: - Misc

    func clearAllData() {
        stopMessagingRealtime()
        stopConversationListRealtime()
        stopAnnouncementRealtime()
        conversations.removeAll()
        createdGroups.removeAll()
        joinedGroupIDs.removeAll()
        requestedGroupIDs.removeAll()
        announcements.removeAll()
        dbConnections.removeAll()
        connectionProfiles.removeAll()
        connectionAvatarURLs.removeAll()
        blockedUserIDs.removeAll()
        blockedByUserIDs.removeAll()
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
        // sentConnectionRequests / pendingReceivedRequests are computed from dbConnections,
        // which we cleared above — they read as empty without an explicit reset.
        dismissedAnnouncementIDs.removeAll()
        joinRequests.removeAll()
        pendingChatConversationID  = nil
        pendingOrderNotificationID = nil
        pendingKnotsViewMode       = nil
        selectedTab                = .home
        street           = ""
        city             = ""
        postalCode       = ""
        country          = ""
        // No stripeCustomerId property on UserProfile — Stripe customer id lives on DBProfile
        // and is fetched fresh by loadFromSupabase on next sign-in.
        stripeConnectId  = nil
        isPrivateAccount         = false
        showKnotsOnProfile       = true
        showListingsOnProfile    = true
        showConnectionsOnProfile = true
        hasSeenWelcome   = false
        name             = ""
        bio              = ""
        profileImage     = nil
        profileImageURL  = nil
        currentUserID    = nil

        // Wipe all local caches on sign-out so a different account never sees
        // stale data from the previous session.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CacheKey.dbConnections)
        defaults.removeObject(forKey: CacheKey.connectionProfiles)
        defaults.removeObject(forKey: CacheKey.connectionAvatarURLs)
        // Legacy keys from older app versions
        defaults.removeObject(forKey: "dismissedAnnouncementIDs")
        defaults.removeObject(forKey: "hasSeenWelcome")
    }
}
