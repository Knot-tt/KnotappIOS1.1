//
//  SupabaseManager.swift
//  Knot
//

import Foundation
import Supabase
import UIKit

// MARK: - Client

let supabase = SupabaseClient(
    supabaseURL: URL(string: Configuration.supabaseURL)!,
    supabaseKey: Configuration.supabaseAnonKey
)

// MARK: - Errors

enum AuthError: Error {
    /// Thrown when a service method requires an authenticated session but none exists.
    case sessionMissing
}

// MARK: - Storage bucket names

private enum Bucket {
    static let profileImages = "profile-images"
    static let knotImages    = "knot-images"
    static let listingImages = "listing-images"
    static let messageImages = "message-images"
}


// MARK: - ProfileService
// Phase 1 — fully implemented.

enum ProfileService {

    /// Fetch multiple profiles by user IDs in one query (used for connection name cache).
    static func fetchMultiple(userIDs: [UUID]) async throws -> [DBProfile] {
        guard !userIDs.isEmpty else { return [] }
        let idList = userIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        // The column list MUST contain every non-optional field on DBProfile —
        // notably `onboarding_complete` and `has_seen_welcome`. Omitting either
        // makes EVERY row fail to decode (silent failure), which throws here and
        // takes loadKnots / loadConversations down with it. Address columns are
        // deliberately excluded (PII; they aren't on DBProfile anyway).
        return try await supabase
            .from("profiles")
            .select("id, name, bio, profile_image, is_private, show_knots, show_listings, show_connections, onboarding_complete, has_seen_welcome, created_at, updated_at")
            .filter("id", operator: "in", value: "(\(idList))")
            .execute()
            .value
    }

    /// Fetch a profile by user ID. Returns nil if not found (new user, not yet inserted).
    static func fetch(userID: UUID) async throws -> DBProfile? {
        let rows: [DBProfile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .execute()
            .value
        return rows.first
    }

    /// Insert the initial profile row right after auth sign-up.
    /// Called once — subsequent updates use `save()`.
    static func create(userID: UUID, name: String, email: String = "") async throws {
        struct Insert: Encodable {
            let id: UUID
            let name, email, bio, street, city, postal_code, country: String
            let is_private, show_knots, show_listings, show_connections: Bool
            let onboarding_complete: Bool
        }
        try await supabase
            .from("profiles")
            .upsert(Insert(
                id: userID,
                name: name,
                email: email,
                bio: "", street: "", city: "", postal_code: "", country: "",
                is_private: false, show_knots: true, show_listings: true, show_connections: true,
                onboarding_complete: false
            ), onConflict: "id", ignoreDuplicates: true)
            .execute()
    }

    static func completeOnboarding() async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("profiles")
            .update(["onboarding_complete": true])
            .eq("id", value: userID)
            .execute()
    }

    /// Update just the display name on the current user's profile.
    static func updateName(_ name: String) async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        struct NameUpdate: Encodable { let name: String }
        try await supabase
            .from("profiles")
            .update(NameUpdate(name: name))
            .eq("id", value: userID)
            .execute()
    }

    /// Persist the user's date of birth (`profiles.birthday` is a DATE column).
    static func saveBirthday(_ dob: Date) async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        struct BirthdayUpdate: Encodable { let birthday: String }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        try await supabase
            .from("profiles")
            .update(BirthdayUpdate(birthday: formatter.string(from: dob)))
            .eq("id", value: userID)
            .execute()
    }

    /// Replace the user's interests with `names` (`user_interests` is one row per interest).
    static func saveInterests(_ names: [String]) async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        // Clear existing selection, then insert the new one.
        try await supabase
            .from("user_interests")
            .delete()
            .eq("user_id", value: userID)
            .execute()
        guard !names.isEmpty else { return }
        struct InterestInsert: Encodable { let user_id: UUID; let interest: String }
        let rows = names.map { InterestInsert(user_id: userID, interest: $0) }
        try await supabase.from("user_interests").insert(rows).execute()
    }

    /// Mark the one-time welcome screen as seen (`profiles.has_seen_welcome`).
    static func markWelcomeSeen() async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        struct WelcomeUpdate: Encodable { let has_seen_welcome: Bool }
        try await supabase
            .from("profiles")
            .update(WelcomeUpdate(has_seen_welcome: true))
            .eq("id", value: userID)
            .execute()
    }

    /// Upsert profile fields (everything except id, stripe_customer_id, created_at).
    /// Always operates on the currently authenticated user — callers cannot supply an arbitrary ID.
    static func save(_ update: DBProfileUpdate) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        try await supabase
            .from("profiles")
            .update(update)
            .eq("id", value: currentUserID)
            .execute()
    }

    /// Upload a profile image to Storage and return the public URL.
    /// Replaces any existing image at the same path.
    /// Always uploads to the current user's storage path — callers cannot supply an arbitrary ID.
    static func uploadProfileImage(_ image: UIImage) async throws -> String {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ProfileService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not compress image"])
        }
        // Reject uploads larger than 5 MB after compression (Supabase Storage limit is 50 MB
        // but 5 MB is sufficient for a profile avatar and prevents abuse).
        let maxBytes = 5 * 1024 * 1024
        guard data.count <= maxBytes else {
            throw NSError(domain: "ProfileService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Image is too large. Please choose a smaller photo."])
        }
        let path = "\(currentUserID.uuidString.lowercased())/avatar.jpg"
        try await supabase.storage
            .from(Bucket.profileImages)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        let publicURL = try supabase.storage
            .from(Bucket.profileImages)
            .getPublicURL(path: path)
        return publicURL.absoluteString
    }

    /// Delete the profile image from Storage.
    /// Always deletes the current user's image — callers cannot supply an arbitrary ID.
    static func deleteProfileImage() async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        let path = "\(currentUserID.uuidString.lowercased())/avatar.jpg"
        try await supabase.storage
            .from(Bucket.profileImages)
            .remove(paths: [path])
    }

    /// Upload a cover image for a knot. Returns the public URL.
    static func uploadKnotCoverImage(knotID: UUID, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "StorageService", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode image."])
        }
        let path = "\(knotID.uuidString.lowercased())/cover.jpg"
        try await supabase.storage
            .from(Bucket.knotImages)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let publicURL = try supabase.storage
            .from(Bucket.knotImages)
            .getPublicURL(path: path)
        return publicURL.absoluteString
    }

    /// Search profiles by name (partial, case-insensitive).
    /// Returns only public-safe fields — never addresses or stripeCustomerId.
    static func search(query: String, limit: Int = 20) async throws -> [DBProfile] {
        // Explicit column list — never expose stripe_customer_id, street, city,
        // postal_code, or country to search callers (search is for finding people,
        // not reading their PII). RLS still applies on top of this.
        // NOTE: must include onboarding_complete + has_seen_welcome — they're
        // non-optional on DBProfile, so omitting them makes every row fail to
        // decode and search silently returns nothing.
        try await supabase
            .from("profiles")
            .select("id, name, bio, profile_image, is_private, show_knots, show_listings, show_connections, onboarding_complete, has_seen_welcome, created_at, updated_at")
            .ilike("name", pattern: "%\(query)%")
            .limit(limit)
            .execute()
            .value
    }
}


// MARK: - ConnectionService
// Phase 2 — fully implemented.

enum ConnectionService {

    /// Fetch all connections + pending requests for the current user.
    /// Always fetches only the authenticated user's connections — no userID param to prevent IDOR.
    static func fetchAll() async throws -> [DBConnection] {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        return try await supabase
            .from("connections")
            .select()
            .or("requester_id.eq.\(currentUserID),recipient_id.eq.\(currentUserID)")
            .execute()
            .value
    }

    /// Send a connection request from the current user.
    /// Always uses the authenticated user as requester — callers cannot spoof the sender.
    static func send(to recipientID: UUID) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        struct Insert: Encodable {
            let requester_id: UUID
            let recipient_id: UUID
            let status: String
        }
        try await supabase
            .from("connections")
            .insert(Insert(requester_id: currentUserID, recipient_id: recipientID, status: "pending"))
            .execute()
    }

    /// Accept a pending connection request.
    /// Ownership enforced at both client (recipient_id filter) and server (RLS) layers.
    static func accept(connectionID: UUID) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        struct Update: Encodable { let status: String; let updated_at: Date }
        try await supabase
            .from("connections")
            .update(Update(status: "accepted", updated_at: Date()))
            .eq("id", value: connectionID)
            .eq("recipient_id", value: currentUserID)  // ownership: only the recipient can accept
            .execute()
    }

    /// Decline or cancel a pending connection request.
    /// Ownership enforced at both client (requester OR recipient filter) and server (RLS) layers.
    static func decline(connectionID: UUID) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        try await supabase
            .from("connections")
            .delete()
            .eq("id", value: connectionID)
            .or("requester_id.eq.\(currentUserID),recipient_id.eq.\(currentUserID)")  // ownership
            .execute()
    }

    /// Remove an accepted connection.
    /// Ownership enforced at both client (requester OR recipient filter) and server (RLS) layers.
    static func remove(connectionID: UUID) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        try await supabase
            .from("connections")
            .delete()
            .eq("id", value: connectionID)
            .or("requester_id.eq.\(currentUserID),recipient_id.eq.\(currentUserID)")  // ownership
            .execute()
    }
}


// MARK: - KnotService
// Phase 3 — fully implemented.

enum KnotRatingService {

    /// Insert or update the current user's star rating for a knot.
    /// The `knot_ratings_sync` DB trigger keeps knots.rating_sum / rating_count current.
    static func submit(knotID: UUID, rating: Int) async throws {
        guard let uid = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct RatingUpsert: Encodable {
            let knot_id: UUID
            let user_id: UUID
            let rating: Int
        }
        try await supabase
            .from("knot_ratings")
            .upsert(RatingUpsert(knot_id: knotID, user_id: uid, rating: rating),
                    onConflict: "knot_id,user_id")
            .execute()
    }

    /// The current user's existing rating for a knot (1–5), or nil if not yet rated.
    static func fetchMine(knotID: UUID) async throws -> Int? {
        guard let uid = supabase.auth.currentUser?.id else { return nil }
        let rows: [DBKnotRating] = try await supabase
            .from("knot_ratings")
            .select()
            .eq("knot_id", value: knotID)
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value
        return rows.first?.rating
    }

    /// Re-fetch a single knot's aggregate rating columns (e.g. after submitting).
    static func fetchAggregate(knotID: UUID) async throws -> (sum: Int, count: Int) {
        let rows: [DBKnot] = try await supabase
            .from("knots")
            .select()
            .eq("id", value: knotID)
            .limit(1)
            .execute()
            .value
        guard let k = rows.first else { return (0, 0) }
        return (k.ratingSum, k.ratingCount)
    }
}

enum KnotService {

    /// Fetch all knot_members rows for the current user, plus the knot rows.
    /// Returns (knots, members) so callers can determine role without a second query.
    static func fetchJoined() async throws -> (knots: [DBKnot], members: [DBKnotMember]) {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        let members: [DBKnotMember] = try await supabase
            .from("knot_members")
            .select()
            .eq("user_id", value: currentUserID)
            .execute()
            .value
        guard !members.isEmpty else { return ([], []) }
        let ids = members.map { $0.knotId.uuidString.lowercased() }.joined(separator: ",")
        let knots: [DBKnot] = try await supabase
            .from("knots")
            .select()
            .filter("id", operator: "in", value: "(\(ids))")
            .execute()
            .value
        return (knots, members)
    }

    static func fetchPublic(limit: Int = 50) async throws -> [DBKnot] {
        // No is_public filter — RLS handles visibility:
        // • Public knots → visible to everyone
        // • Connections-only knots → visible to accepted connections of creator
        // • Private knots (is_public=false) → visible to members only
        try await supabase
            .from("knots")
            .select()
            .order("member_count", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Insert a new knot row and add the creator as a knot_member with role='creator'.
    /// Returns the inserted knot (with server-generated id, created_at, etc.).
    static func create(
        name                       : String,
        description                : String,
        category                   : String,
        location                   : String,
        isPublic                   : Bool,
        isEvent                    : Bool,
        requiresApproval           : Bool,
        isConnectionsOnly          : Bool,
        hideLocationFromNonMembers : Bool,
        maxMembers                 : Int?,
        ageGroup                   : String,
        minAge                     : Int,
        maxAge                     : Int,
        isPaid                     : Bool,
        paymentType                : String,
        priceCents                 : Int
    ) async throws -> DBKnot {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }

        struct KnotInsert: Encodable {
            let creator_id: UUID
            let name, description, category, location, age_group, payment_type: String
            let is_public, is_event, requires_approval, is_connections_only, hide_location_from_non_members, is_paid: Bool
            let max_members: Int?
            let min_age, max_age, price_cents: Int
        }

        let inserted: [DBKnot] = try await supabase
            .from("knots")
            .insert(KnotInsert(
                creator_id                    : currentUserID,
                name                          : name,
                description                   : description,
                category                      : category,
                location                      : location,
                age_group                     : ageGroup,
                payment_type                  : paymentType,
                is_public                     : isPublic,
                is_event                      : isEvent,
                requires_approval             : requiresApproval,
                is_connections_only           : isConnectionsOnly,
                hide_location_from_non_members: hideLocationFromNonMembers,
                is_paid                       : isPaid,
                max_members                   : maxMembers,
                min_age                       : minAge,
                max_age                       : maxAge,
                price_cents                   : priceCents
            ), returning: .representation)
            .execute()
            .value

        guard let knot = inserted.first else {
            throw NSError(domain: "KnotService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Knot insert returned no row"])
        }

        // Add creator as knot_member with role='creator'
        struct MemberInsert: Encodable {
            let knot_id: UUID
            let user_id: UUID
            let role: String
        }
        try await supabase
            .from("knot_members")
            .insert(MemberInsert(
                knot_id : knot.id,
                user_id : currentUserID,
                role    : "creator"
            ))
            .execute()

        return knot
    }

    static func fetchMembers(knotID: UUID) async throws -> [DBKnotMember] {
        try await supabase
            .from("knot_members")
            .select()
            .eq("knot_id", value: knotID)
            .execute()
            .value
    }

    static func update(knotID: UUID, name: String, description: String, category: String,
                       location: String, isPublic: Bool, isEvent: Bool,
                       isConnectionsOnly: Bool, hideLocationFromNonMembers: Bool,
                       requiresApproval: Bool, maxMembers: Int?,
                       ageGroup: String, minAge: Int, maxAge: Int,
                       isPaid: Bool, paymentType: String, priceCents: Int) async throws {
        struct KnotUpdate: Encodable {
            let name, description, category, location: String
            let is_public, is_event, is_connections_only: Bool
            let hide_location_from_non_members, requires_approval: Bool
            let max_members: Int?
            let age_group, payment_type: String
            let min_age, max_age, price_cents: Int
            let is_paid: Bool
        }
        try await supabase
            .from("knots")
            .update(KnotUpdate(
                name: name, description: description, category: category, location: location,
                is_public: isPublic, is_event: isEvent,
                is_connections_only: isConnectionsOnly,
                hide_location_from_non_members: hideLocationFromNonMembers,
                requires_approval: requiresApproval,
                max_members: maxMembers,
                age_group: ageGroup, payment_type: paymentType,
                min_age: minAge, max_age: maxAge, price_cents: priceCents,
                is_paid: isPaid
            ))
            .eq("id", value: knotID)
            .execute()
    }

    /// Transfers creator role to newCreatorID, then removes the old creator from knot_members.
    static func transferCreator(knotID: UUID, newCreatorID: UUID) async throws {
        guard let oldCreatorID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        // 1. Update knots.creator_id
        struct CreatorUpdate: Encodable { let creator_id: UUID }
        try await supabase
            .from("knots")
            .update(CreatorUpdate(creator_id: newCreatorID))
            .eq("id", value: knotID)
            .execute()
        // 2. Promote new creator's role in knot_members
        struct RoleUpdate: Encodable { let role: String }
        try await supabase
            .from("knot_members")
            .update(RoleUpdate(role: "creator"))
            .eq("knot_id", value: knotID)
            .eq("user_id", value: newCreatorID)
            .execute()
        // 3. Remove old creator from knot_members
        try await supabase
            .from("knot_members")
            .delete()
            .eq("knot_id", value: knotID)
            .eq("user_id", value: oldCreatorID)
            .execute()
    }

    /// Update only the image_url column on a knot (called after Storage upload).
    static func updateImageURL(knotID: UUID, url: String) async throws {
        struct ImageUpdate: Encodable { let image_url: String }
        try await supabase
            .from("knots")
            .update(ImageUpdate(image_url: url))
            .eq("id", value: knotID)
            .execute()
    }

    static func delete(knotID: UUID) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        try await supabase
            .from("knots")
            .delete()
            .eq("id", value: knotID)
            .eq("creator_id", value: currentUserID)
            .execute()
    }

    static func leaveKnot(knotID: UUID) async throws {
        guard let currentUserID = supabase.auth.currentUser?.id else {
            throw AuthError.sessionMissing
        }
        try await supabase
            .from("knot_members")
            .delete()
            .eq("knot_id", value: knotID)
            .eq("user_id", value: currentUserID)
            .execute()
    }

    /// Promote a member to co-admin (`isAdmin: true`) or demote back to member.
    /// `knot_member_role` enum values: member, co_admin, creator.
    static func setCoAdmin(knotID: UUID, userID: UUID, isAdmin: Bool) async throws {
        struct RoleUpdate: Encodable { let role: String }
        try await supabase
            .from("knot_members")
            .update(RoleUpdate(role: isAdmin ? "co_admin" : "member"))
            .eq("knot_id", value: knotID)
            .eq("user_id", value: userID)
            .execute()
    }

    /// Remove a member from a knot.
    static func kickMember(knotID: UUID, userID: UUID) async throws {
        try await supabase
            .from("knot_members")
            .delete()
            .eq("knot_id", value: knotID)
            .eq("user_id", value: userID)
            .execute()
    }

    /// Exact count of the knots a user belongs to, straight from the server.
    static func countMemberships(userID: UUID) async throws -> Int {
        let response = try await supabase
            .from("knot_members")
            .select("knot_id", head: true, count: .exact)
            .eq("user_id", value: userID)
            .execute()
        return response.count ?? 0
    }
}


// MARK: - MessagingService
// Phase 4 — fully implemented.

enum MessagingService {

    /// Bundled result of one conversation + the caller's participant row + all other participants.
    struct ConversationData {
        let conversation    : DBConversation
        let myParticipant   : DBConversationParticipant
        let participants    : [DBConversationParticipant]  // includes all participants (caller + others)
    }

    /// Fetch all active conversations for the current user.
    /// No userID param — always uses auth.currentUser to prevent IDOR.
    static func fetchConversations() async throws -> [ConversationData] {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }

        // 1. Find all conversation IDs where the current user is an active participant.
        let myParts: [DBConversationParticipant] = try await supabase
            .from("conversation_participants")
            .select()
            .eq("user_id", value: me)
            .eq("has_left", value: false)
            .execute()
            .value

        guard !myParts.isEmpty else { return [] }

        let idList = myParts.map { $0.conversationId.uuidString.lowercased() }.joined(separator: ",")

        // 2. Fetch the conversation rows.
        let conversations: [DBConversation] = try await supabase
            .from("conversations")
            .select()
            .filter("id", operator: "in", value: "(\(idList))")
            .order("updated_at", ascending: false)
            .execute()
            .value

        // 3. Fetch all participant rows for those conversations (to resolve names, roles, etc.)
        let allParts: [DBConversationParticipant] = try await supabase
            .from("conversation_participants")
            .select()
            .filter("conversation_id", operator: "in", value: "(\(idList))")
            .execute()
            .value

        let myPartByConvID: [UUID: DBConversationParticipant] = Dictionary(
            myParts.map { ($0.conversationId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let partsByConvID = Dictionary(grouping: allParts, by: \.conversationId)

        return conversations.compactMap { conv in
            guard let myPart = myPartByConvID[conv.id] else { return nil }
            return ConversationData(
                conversation  : conv,
                myParticipant : myPart,
                participants  : partsByConvID[conv.id] ?? []
            )
        }
    }

    /// Fetch messages for a conversation in chronological order.
    /// RLS enforces that the caller must be a participant.
    static func fetchMessages(conversationID: UUID, limit: Int = 50) async throws -> [DBMessage] {
        guard supabase.auth.currentUser != nil else { throw AuthError.sessionMissing }
        return try await supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    /// Fetch only the newest message for a conversation.
    static func fetchLatestMessage(conversationID: UUID) async throws -> DBMessage? {
        guard supabase.auth.currentUser != nil else { throw AuthError.sessionMissing }
        let rows: [DBMessage] = try await supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Send a text message as the current user.
    /// No senderID param — always uses auth.currentUser to prevent sender spoofing.
    static func send(text: String, conversationID: UUID) async throws -> DBMessage {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct MessageInsert: Encodable {
            let conversation_id: UUID
            let sender_id      : UUID
            let text           : String
            let status         : String
        }
        let inserted: [DBMessage] = try await supabase
            .from("messages")
            .insert(
                MessageInsert(conversation_id: conversationID, sender_id: me, text: text, status: "sent"),
                returning: .representation
            )
            .execute()
            .value
        guard let msg = inserted.first else {
            throw NSError(domain: "MessagingService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Message insert returned no row"])
        }
        return msg
    }

    /// Create a new conversation and add the caller + participantIDs as participants.
    /// No creatorID param — always uses auth.currentUser.
    static func createConversation(
        isGroup       : Bool,
        groupName     : String?,
        participantIDs: [UUID],
        sourceKnotID  : UUID? = nil
    ) async throws -> DBConversation {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }

        // For DMs, return the existing conversation if one already exists.
        if !isGroup, let otherID = participantIDs.first(where: { $0 != me }) {
            let existing: UUID? = try? await supabase
                .rpc("find_dm_conversation", params: ["other_user_id": otherID])
                .execute()
                .value
            if let existingID = existing {
                return DBConversation(
                    id           : existingID,
                    isGroup      : false,
                    groupName    : nil,
                    groupImageUrl: nil,
                    creatorId    : me,
                    sourceKnotId : sourceKnotID,
                    createdAt    : Date(),
                    updatedAt    : Date()
                )
            }
        }

        // Generate the UUID client-side so we never need `returning: .representation`.
        // Using RETURNING triggers the conversations SELECT policy, which requires a
        // participant row — but that row doesn't exist yet at insert time.
        let convID = UUID()
        struct ConvInsert: Encodable {
            let id            : UUID
            let is_group      : Bool
            let group_name    : String?
            let creator_id    : UUID
            let source_knot_id: UUID?
        }
        try await supabase
            .from("conversations")
            .insert(
                ConvInsert(id: convID, is_group: isGroup, group_name: groupName,
                           creator_id: me, source_knot_id: sourceKnotID)
            )
            .execute()
        struct ParticipantInsert: Encodable {
            let conversation_id: UUID
            let user_id        : UUID
            let is_admin       : Bool
            let is_creator     : Bool
        }
        var participants = [ParticipantInsert(
            conversation_id: convID, user_id: me, is_admin: true, is_creator: true
        )]
        for pid in participantIDs where pid != me {
            participants.append(ParticipantInsert(
                conversation_id: convID, user_id: pid, is_admin: false, is_creator: false
            ))
        }
        try await supabase.from("conversation_participants").insert(participants).execute()
        // Build a minimal DBConversation to return to the caller — we have all fields.
        return DBConversation(
            id           : convID,
            isGroup      : isGroup,
            groupName    : groupName,
            groupImageUrl: nil,
            creatorId    : me,
            sourceKnotId : sourceKnotID,
            createdAt    : Date(),
            updatedAt    : Date()
        )
    }

    /// Toggle the favourite flag on the caller's participant row.
    static func setFavourite(conversationID: UUID, isFavourite: Bool) async throws {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct FavUpdate: Encodable { let is_favourite: Bool }
        try await supabase
            .from("conversation_participants")
            .update(FavUpdate(is_favourite: isFavourite))
            .eq("conversation_id", value: conversationID)
            .eq("user_id", value: me)
            .execute()
    }

    /// Leaves a conversation, promoting a random member to admin first if the
    /// caller is the only remaining admin.
    static func leaveConversation(conversationID: UUID) async throws {
        try await supabase
            .rpc("leave_conversation", params: ["p_conversation_id": conversationID])
            .execute()
    }

    /// Promote or demote a participant's admin status.
    /// Only admins/creators can call this in practice — RLS enforces it at DB layer.
    static func updateParticipantAdmin(conversationID: UUID, userID: UUID, isAdmin: Bool) async throws {
        struct AdminUpdate: Encodable { let is_admin: Bool }
        try await supabase
            .from("conversation_participants")
            .update(AdminUpdate(is_admin: isAdmin))
            .eq("conversation_id", value: conversationID)
            .eq("user_id", value: userID)
            .execute()
    }

    /// Find the existing knot group chat or create it, via a SECURITY DEFINER RPC.
    /// Returns the conversation UUID. (See CLAUDE.md — never generate this locally.)
    static func findOrCreateKnotChat(knotID: UUID, knotName: String) async throws -> UUID {
        struct Params: Encodable { let p_knot_id: UUID; let p_knot_name: String }
        return try await supabase
            .rpc("find_or_create_knot_chat", params: Params(p_knot_id: knotID, p_knot_name: knotName))
            .execute()
            .value
    }

    /// Send an image message: upload the photo to Storage, then insert the message row.
    static func sendImage(_ image: UIImage, caption: String = "", conversationID: UUID) async throws -> DBMessage {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw NSError(domain: "MessagingService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode image."])
        }
        let path = "\(conversationID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await supabase.storage
            .from(Bucket.messageImages)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let url = try supabase.storage
            .from(Bucket.messageImages)
            .getPublicURL(path: path)

        struct ImageMessageInsert: Encodable {
            let conversation_id: UUID
            let sender_id      : UUID
            let text           : String
            let image_url      : String
            let status         : String
        }
        let inserted: [DBMessage] = try await supabase
            .from("messages")
            .insert(
                ImageMessageInsert(conversation_id: conversationID, sender_id: me,
                                   text: caption, image_url: url.absoluteString, status: "sent"),
                returning: .representation
            )
            .execute()
            .value
        guard let msg = inserted.first else {
            throw NSError(domain: "MessagingService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Message insert returned no row"])
        }
        return msg
    }

    /// Upload a recorded video clip + its poster frame and insert a video message.
    /// The clip and poster both live in the `message-images` bucket (its RLS already
    /// scopes uploads to chat participants); `image_url` is the poster, `video_url`
    /// the clip.
    static func sendVideo(fileURL: URL, poster: UIImage, caption: String = "",
                          conversationID: UUID) async throws -> DBMessage {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let videoData = try Data(contentsOf: fileURL)
        guard let posterData = poster.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "MessagingService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode video poster."])
        }
        let base = "\(conversationID.uuidString.lowercased())/\(UUID().uuidString.lowercased())"
        let videoPath  = "\(base).mov"
        let posterPath = "\(base).jpg"

        try await supabase.storage.from(Bucket.messageImages)
            .upload(videoPath, data: videoData,
                    options: FileOptions(contentType: "video/quicktime", upsert: true))
        try await supabase.storage.from(Bucket.messageImages)
            .upload(posterPath, data: posterData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true))

        let videoURL  = try supabase.storage.from(Bucket.messageImages).getPublicURL(path: videoPath)
        let posterURL = try supabase.storage.from(Bucket.messageImages).getPublicURL(path: posterPath)

        struct VideoMessageInsert: Encodable {
            let conversation_id: UUID
            let sender_id      : UUID
            let text           : String
            let image_url      : String
            let video_url      : String
            let status         : String
        }
        let inserted: [DBMessage] = try await supabase
            .from("messages")
            .insert(
                VideoMessageInsert(conversation_id: conversationID, sender_id: me,
                                   text: caption, image_url: posterURL.absoluteString,
                                   video_url: videoURL.absoluteString, status: "sent"),
                returning: .representation
            )
            .execute()
            .value
        guard let msg = inserted.first else {
            throw NSError(domain: "MessagingService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Video message insert returned no row"])
        }
        return msg
    }

    /// Mark the conversation read for the current user (updates `last_read_at`).
    static func markConversationRead(conversationID: UUID) async throws {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct ReadUpdate: Encodable { let last_read_at: String }
        try await supabase
            .from("conversation_participants")
            .update(ReadUpdate(last_read_at: ISO8601DateFormatter().string(from: Date())))
            .eq("conversation_id", value: conversationID)
            .eq("user_id", value: me)
            .execute()
    }

    /// Rename a group conversation.
    static func renameGroup(conversationID: UUID, newName: String) async throws {
        struct NameUpdate: Encodable { let group_name: String }
        try await supabase
            .from("conversations")
            .update(NameUpdate(group_name: newName))
            .eq("id", value: conversationID)
            .execute()
    }

    /// Update a group conversation's name and description in one write.
    static func updateGroupInfo(conversationID: UUID, name: String, description: String) async throws {
        struct InfoUpdate: Encodable { let group_name: String; let group_description: String }
        try await supabase
            .from("conversations")
            .update(InfoUpdate(group_name: name, group_description: description))
            .eq("id", value: conversationID)
            .execute()
    }

    /// Upload a group conversation image to Storage and persist its URL. Returns the URL.
    @discardableResult
    static func uploadGroupImage(conversationID: UUID, _ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw NSError(domain: "MessagingService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode image."])
        }
        let path = "\(conversationID.uuidString.lowercased())/group.jpg"
        try await supabase.storage
            .from(Bucket.messageImages)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let url = try supabase.storage
            .from(Bucket.messageImages)
            .getPublicURL(path: path)
        struct ImageUpdate: Encodable { let group_image_url: String }
        try await supabase
            .from("conversations")
            .update(ImageUpdate(group_image_url: url.absoluteString))
            .eq("id", value: conversationID)
            .execute()
        return url.absoluteString
    }

    /// Re-join a conversation the current user previously left/hid (clears `has_left`).
    static func reactivateConversationForCurrentUser(conversationID: UUID) async throws {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct Reactivate: Encodable { let has_left: Bool }
        try await supabase
            .from("conversation_participants")
            .update(Reactivate(has_left: false))
            .eq("conversation_id", value: conversationID)
            .eq("user_id", value: me)
            .execute()
    }
}


// MARK: - ShopService

enum ShopService {

    private static func preparedListingImageData(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let maxDimension: CGFloat = 1600
        let originalSize = image.size
        let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return autoreleasepool {
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            if let compressed = resized.jpegData(compressionQuality: 0.72) {
                return compressed
            }
            return image.jpegData(compressionQuality: 0.6)
        }
    }

    private struct ListingInsert: Encodable {
        let id          : UUID
        let sellerId    : UUID
        let listingType : String
        let category    : String
        let condition   : String
        let name        : String
        let description : String
        let link        : String
        let priceCents  : Int
        let imageUrls   : [String]
        let isActive    : Bool
        let isRecurring : Bool
        let acceptsCash : Bool
        let acceptsCard : Bool

        enum CodingKeys: String, CodingKey {
            case id, name, description, link, condition, category
            case sellerId    = "seller_id"
            case listingType = "listing_type"
            case priceCents  = "price_cents"
            case imageUrls   = "image_urls"
            case isActive    = "is_active"
            case isRecurring = "is_recurring"
            case acceptsCash = "accepts_cash"
            case acceptsCard = "accepts_card"
        }
    }

    static func fetchActive(limit: Int = 50) async throws -> [DBShopListing] {
        return try await supabase
            .from("shop_listings")
            .select()
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func fetch(listingID: UUID) async throws -> DBShopListing? {
        let rows: [DBShopListing] = try await supabase
            .from("shop_listings")
            .select()
            .eq("id", value: listingID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Exact count of a user's ACTIVE listings, straight from the server.
    /// Used for profile stats so the number isn't limited by what the viewer
    /// happens to have cached in the public feed.
    static func countActive(sellerID: UUID) async throws -> Int {
        let response = try await supabase
            .from("shop_listings")
            .select("id", head: true, count: .exact)
            .eq("seller_id", value: sellerID)
            .eq("is_active", value: true)
            .execute()
        return response.count ?? 0
    }

    static func create(
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
    ) async throws -> DBShopListing {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let listingID = UUID()
        let folder = listingID.uuidString.lowercased()

        // Public URLs are deterministic — getPublicURL just builds a string and
        // makes no network call, so we know every image's final URL before a
        // single byte is uploaded.
        var imageURLs: [String] = []
        imageURLs.reserveCapacity(images.count)
        for i in images.indices {
            let url = try supabase.storage
                .from(Bucket.listingImages)
                .getPublicURL(path: "\(folder)/\(i).jpg")
            imageURLs.append(url.absoluteString)
        }

        // Insert the listing row FIRST, before any Storage upload — exactly like
        // KnotService.create / uploadKnotCoverImage (that flow never freezes).
        //
        // The reverse order (upload, then insert) intermittently deadlocks the
        // Supabase client's auth/token layer: the upload succeeds, then the
        // insert is never sent and "Post" hangs the app. Inserting first means
        // the only network calls after the uploads are the uploads themselves.
        let insert = ListingInsert(
            id: listingID, sellerId: me,
            listingType: type.rawValue.lowercased(),
            category: category.dbValue,
            condition: condition.dbValue,
            name: name, description: description, link: link,
            priceCents: price * 100,
            imageUrls: imageURLs, isActive: true,
            isRecurring: isRecurring,
            acceptsCash: acceptsCash,
            acceptsCard: acceptsCard
        )
        try await supabase.from("shop_listings").insert(insert).execute()

        // Now upload the image bytes. The row already exists, so these are the
        // last network calls in this operation.
        var failedIndexes: [Int] = []
        for (i, image) in images.enumerated() {
            let path = "\(folder)/\(i).jpg"
            guard let data = preparedListingImageData(image) else {
                print("[ShopService] image preparation failed at index \(i)")
                failedIndexes.append(i)
                continue
            }
            do {
                try await supabase.storage
                    .from(Bucket.listingImages)
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            } catch {
                // Retry once for intermittent storage failures.
                do {
                    try await supabase.storage
                        .from(Bucket.listingImages)
                        .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                } catch {
                    print("[ShopService] image upload failed at index \(i): \(error)")
                    failedIndexes.append(i)
                }
            }
        }

        // If any upload failed the row now points at a missing file. Correct the
        // stored URLs to the subset that actually uploaded. Done in a detached
        // task so this clean-up can never block (or re-freeze) the post.
        if !failedIndexes.isEmpty {
            let survivingURLs = imageURLs.enumerated()
                .filter { !failedIndexes.contains($0.offset) }
                .map(\.element)
            imageURLs = survivingURLs
            Task.detached {
                struct ImageURLsPatch: Encodable {
                    let imageUrls: [String]
                    enum CodingKeys: String, CodingKey { case imageUrls = "image_urls" }
                }
                _ = try? await supabase.from("shop_listings")
                    .update(ImageURLsPatch(imageUrls: survivingURLs))
                    .eq("id", value: listingID)
                    .execute()
            }
        }

        return DBShopListing(
            id: listingID, sellerId: me,
            listingType: type.rawValue.lowercased(),
            category: category.dbValue,
            condition: condition.dbValue,
            name: name, description: description, link: link,
            priceCents: price * 100,
            imageUrls: imageURLs, isActive: true,
            isRecurring: isRecurring,
            acceptsCash: acceptsCash,
            acceptsCard: acceptsCard,
            createdAt: Date(), updatedAt: Date()
        )
    }

    /// Update a listing's editable fields. Caller must own the listing (RLS enforces this).
    /// Images are not touched here — sellers manage photos via a separate flow.
    static func update(
        listingID  : UUID,
        type       : ListingType,
        category   : ShopCategory,
        condition  : ItemCondition,
        name       : String,
        description: String,
        link       : String,
        price      : Int
    ) async throws {
        struct ListingUpdate: Encodable {
            let listing_type : String
            let category     : String
            let condition    : String
            let name         : String
            let description  : String
            let link         : String
            let price_cents  : Int
        }
        let payload = ListingUpdate(
            listing_type: type.rawValue.lowercased(),
            category    : category.dbValue,
            condition   : condition.dbValue,
            name        : name,
            description : description,
            link        : link,
            price_cents : price * 100
        )
        try await supabase
            .from("shop_listings")
            .update(payload)
            .eq("id", value: listingID)
            .execute()
    }

    /// Fetch every listing the current user owns, regardless of active state.
    /// Used to power a "My Listings" view that can show + restore soft-deleted rows.
    static func fetchMine() async throws -> [DBShopListing] {
        guard let me = supabase.auth.currentUser?.id else { return [] }
        return try await supabase
            .from("shop_listings")
            .select()
            .eq("seller_id", value: me)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Restore a previously soft-deleted listing — the inverse of `delete(listingID:)`.
    static func restore(listingID: UUID) async throws {
        struct Reactivate: Encodable { let isActive: Bool
            enum CodingKeys: String, CodingKey { case isActive = "is_active" }
        }
        try await supabase
            .from("shop_listings")
            .update(Reactivate(isActive: true))
            .eq("id", value: listingID.uuidString.lowercased())
            .execute()
    }

    static func delete(listingID: UUID) async throws {
        struct Deactivate: Encodable { let isActive: Bool
            enum CodingKeys: String, CodingKey { case isActive = "is_active" }
        }
        try await supabase
            .from("shop_listings")
            .update(Deactivate(isActive: false))
            .eq("id", value: listingID.uuidString.lowercased())
            .execute()
    }
}


// MARK: - SettingsService
// Notification preference persistence + blocked users.

enum SettingsService {

    struct NotificationPrefs: Codable {
        var notifyKnots         : Bool
        var notifyMessages      : Bool
        var notifyAnnouncements : Bool
        var notifyMarketplace   : Bool
        enum CodingKeys: String, CodingKey {
            case notifyKnots         = "notify_knots"
            case notifyMessages      = "notify_messages"
            case notifyAnnouncements = "notify_announcements"
            case notifyMarketplace   = "notify_marketplace"
        }
    }

    static func fetchNotificationPrefs() async throws -> NotificationPrefs? {
        guard let userID = supabase.auth.currentUser?.id else { return nil }
        let rows: [NotificationPrefs] = try await supabase
            .from("user_settings")
            .select("notify_knots, notify_messages, notify_announcements, notify_marketplace")
            .eq("user_id", value: userID)
            .execute()
            .value
        return rows.first
    }

    static func updateNotificationPrefs(_ prefs: NotificationPrefs) async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        struct Payload: Encodable {
            let user_id              : UUID
            let notify_knots         : Bool
            let notify_messages      : Bool
            let notify_announcements : Bool
            let notify_marketplace   : Bool
            let updated_at           : Date
        }
        try await supabase.from("user_settings").upsert(Payload(
            user_id: userID,
            notify_knots: prefs.notifyKnots,
            notify_messages: prefs.notifyMessages,
            notify_announcements: prefs.notifyAnnouncements,
            notify_marketplace: prefs.notifyMarketplace,
            updated_at: Date()
        ), onConflict: "user_id").execute()
    }

    // ── Blocked users ──────────────────────────────────────────────────────

    static func fetchBlockedUserIDs() async throws -> [UUID] {
        guard let userID = supabase.auth.currentUser?.id else { return [] }
        struct Row: Decodable { let blocked_id: UUID }
        let rows: [Row] = try await supabase
            .from("blocked_users")
            .select("blocked_id")
            .eq("blocker_id", value: userID)
            .execute()
            .value
        return rows.map(\.blocked_id)
    }

    static func block(userID toBlock: UUID) async throws {
        guard let me = supabase.auth.currentUser?.id, me != toBlock else { return }
        struct Insert: Encodable { let blocker_id, blocked_id: UUID }
        try await supabase.from("blocked_users").insert(Insert(blocker_id: me, blocked_id: toBlock)).execute()
    }

    static func unblock(userID toUnblock: UUID) async throws {
        guard let me = supabase.auth.currentUser?.id else { return }
        try await supabase.from("blocked_users")
            .delete()
            .eq("blocker_id", value: me)
            .eq("blocked_id", value: toUnblock)
            .execute()
    }

    /// Returns true if `userID` has blocked the current user.
    ///
    /// Requires this RLS policy on the blocked_users table in Supabase:
    ///   CREATE POLICY "users_can_check_if_blocked_by_others"
    ///     ON blocked_users FOR SELECT
    ///     USING (blocked_id = auth.uid());
    ///
    /// Without this policy the query returns empty (not an error), which is
    /// treated as "not blocked" — safe fallback.
    static func isBlockedBy(userID: UUID) async -> Bool {
        guard let me = supabase.auth.currentUser?.id else { return false }
        struct Row: Decodable { let blocked_id: UUID }
        let rows: [Row] = (try? await supabase
            .from("blocked_users")
            .select("blocked_id")
            .eq("blocker_id", value: userID)
            .eq("blocked_id", value: me)
            .limit(1)
            .execute()
            .value) ?? []
        return !rows.isEmpty
    }
}


// MARK: - ReportService
// User / content reporting. Required by Apple App Store Review Guideline 1.2
// for apps with user-generated content. Rows land in public.reports (RLS:
// reporter_id = auth.uid()) for moderation review.

enum ReportService {

    /// File a report against another user, optionally tied to a conversation/message.
    static func report(
        userID reported: UUID?,
        reason: String,
        details: String?,
        conversationID: UUID? = nil,
        messageID: UUID? = nil
    ) async throws {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct Insert: Encodable {
            let reporter_id: UUID
            let reported_user_id: UUID?
            let conversation_id: UUID?
            let message_id: UUID?
            let reason: String
            let details: String?
        }
        try await supabase.from("reports").insert(Insert(
            reporter_id: me,
            reported_user_id: reported,
            conversation_id: conversationID,
            message_id: messageID,
            reason: reason,
            details: details?.isEmpty == true ? nil : details
        )).execute()
    }
}


// MARK: - Edge-function HTTP helper
// Calls a Supabase Edge Function with the current user's JWT for auth.

private func callEdgeFunction<Req: Encodable, Res: Decodable>(name: String, body: Req) async throws -> Res {
    guard let session = try? await supabase.auth.session else {
        throw AuthError.sessionMissing
    }
    let urlString = "\(Configuration.supabaseURL)/functions/v1/\(name)"
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "EdgeFn", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let msg = String(data: data, encoding: .utf8) ?? "Edge function failed"
        throw NSError(domain: "EdgeFn", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                      userInfo: [NSLocalizedDescriptionKey: msg])
    }
    return try JSONDecoder().decode(Res.self, from: data)
}


// MARK: - OrderService
// Phase 7 — creates/releases go through Edge Functions; status transitions are direct DB UPDATEs.

enum OrderService {

    private static func notifyOtherParty(orderID: String, title: String, body: String) async {
        guard let me = supabase.auth.currentUser?.id else { return }
        do {
            let rows: [DBOrder] = try await supabase
                .from("orders")
                .select()
                .eq("id", value: orderID)
                .limit(1)
                .execute()
                .value
            guard let order = rows.first else { return }
            let recipientID = order.buyerId == me ? order.sellerId : order.buyerId
            guard recipientID != me else { return }
            await NotificationManager.notify(userID: recipientID, title: title, body: body, target: "orders", orderID: orderID)
        } catch {
            print("[OrderService] notification lookup error: \(error)")
        }
    }

    /// Fetch all orders where the current user is buyer or seller.
    /// RLS on the orders table enforces this — no manual filtering needed.
    static func fetchAll() async throws -> [DBOrder] {
        return try await supabase
            .from("orders")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Proposes or counter-proposes a meetup via edge function.
    static func proposeMeetup(
        orderID: String,
        location: String,
        date: Date,
        proposedBy: String,
        resetProgressToPending: Bool = false
    ) async throws {
        struct Payload: Encodable {
            let orderId   : String
            let location  : String
            let dateISO   : String
            let proposedBy: String
        }
        struct Response: Decodable { let success: Bool }
        let iso = ISO8601DateFormatter()
        let response: Response = try await callEdgeFunction(
            name: "propose-meetup",
            body: Payload(
                orderId: orderID,
                location: location,
                dateISO: iso.string(from: date),
                proposedBy: proposedBy
            )
        )
        guard response.success else {
            throw NSError(domain: "OrderService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not send meetup proposal."])
        }
        if resetProgressToPending {
            guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
            try await supabase
                .from("orders")
                .update([
                    "status": "pending"
                ])
                .eq("id", value: orderID)
                .eq("seller_id", value: me)
                .execute()
        }
        await notifyOtherParty(
            orderID: orderID,
            title: proposedBy == "seller" ? "Meetup Proposed" : "Meetup Counter-Proposed",
            body: "Review the proposed meetup details."
        )
    }

    /// Seller accepts a pending order before meetup / delivery details are finalized.
    static func acceptOrder(orderID: String) async throws {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        try await supabase
            .from("orders")
            .update([
                "status": "seller_accepted",
                "seller_accepted_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: orderID)
            .eq("seller_id", value: me)
            .eq("status", value: "pending")
            .execute()
        await notifyOtherParty(orderID: orderID, title: "Order Accepted", body: "The seller accepted your order.")
    }

    /// Accepts the current meetup proposal via edge function.
    static func acceptMeetup(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await callEdgeFunction(name: "accept-meetup", body: Payload(orderId: orderID))
        await notifyOtherParty(orderID: orderID, title: "Meetup Accepted", body: "The meetup has been confirmed.")
    }

    /// Cancels the order via edge function.
    static func cancelOrder(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await callEdgeFunction(name: "cancel-order", body: Payload(orderId: orderID))
        await notifyOtherParty(orderID: orderID, title: "Order Cancelled", body: "The order has been cancelled.")
    }

    /// Marks order as disputed via edge function.
    static func disputeOrder(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await callEdgeFunction(name: "dispute-order", body: Payload(orderId: orderID))
        await notifyOtherParty(orderID: orderID, title: "Order Disputed", body: "A problem was reported for this order.")
    }

    /// Marks a cash order as complete directly in the DB (no Stripe involved).
    static func markCashOrderComplete(orderID: String) async throws {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        try await supabase
            .from("orders")
            .update([
                "status":       "complete",
                "escrow_status": "released",
                "complete_at":  ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: orderID)
            .eq("buyer_id", value: me)
            .execute()
        await notifyOtherParty(orderID: orderID, title: "Order Closed", body: "The buyer confirmed receipt.")
    }

    /// Creates a cash order (no Stripe payment). Returns the new order ID.
    static func createCashOrder(listingID: UUID, fulfilment: FulfilmentMethod, deliveryAddress: String, meetupLocation: String = "") async throws -> String {
        struct Payload: Encodable {
            let listingId      : String
            let fulfilment     : String
            let deliveryAddress: String
            let meetupLocation : String
        }
        struct Response: Decodable { let orderId: String }
        let response: Response = try await callEdgeFunction(
            name: "create-cash-order",
            body: Payload(
                listingId      : listingID.uuidString.lowercased(),
                fulfilment     : fulfilment.dbValue,
                deliveryAddress: fulfilment == .delivery ? deliveryAddress : "",
                meetupLocation : fulfilment == .meetup ? meetupLocation : ""
            )
        )
        await notifyOtherParty(orderID: response.orderId, title: "New Order", body: "You have a new order to review.")
        return response.orderId
    }

}


// MARK: - AnnouncementService

enum AnnouncementService {

    private static func uploadImages(knotID: UUID, images: [UIImage]) async throws -> [String] {
        guard !images.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, image) in Array(images.prefix(5)).enumerated() {
                group.addTask {
                    guard let data = image.jpegData(compressionQuality: 0.75) else {
                        throw NSError(
                            domain: "AnnouncementService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Could not encode announcement image."]
                        )
                    }

                    let path = "\(knotID.uuidString.lowercased())/announcements/\(UUID().uuidString.lowercased())-\(index).jpg"
                    try await supabase.storage
                        .from(Bucket.knotImages)
                        .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))

                    let url = try await supabase.storage
                        .from(Bucket.knotImages)
                        .getPublicURL(path: path)

                    return (index, url.absoluteString)
                }
            }

            var indexedURLs: [(Int, String)] = []
            for try await result in group {
                indexedURLs.append(result)
            }
            return indexedURLs
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    struct FetchedAnnouncement {
        let announcement : DBAnnouncement
        let isRead       : Bool
        let isPinned     : Bool
    }

    /// Fetches all announcements visible to the current user (platform-wide + their knots).
    /// RLS on the `announcements` table handles visibility — no manual filtering needed.
    static func fetchForUser() async throws -> [FetchedAnnouncement] {
        let announcements: [DBAnnouncement] = try await supabase
            .from("announcements")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        guard !announcements.isEmpty else { return [] }

        // Fetch membership join dates so we can hide payment request alerts that
        // existed before the current user joined the knot.
        struct MemberDateRow: Decodable, Sendable {
            let knotId   : UUID
            let joinedAt : Date
            enum CodingKeys: String, CodingKey {
                case knotId   = "knot_id"
                case joinedAt = "joined_at"
            }
        }
        let memberships: [MemberDateRow] = (try? await supabase
            .from("knot_members")
            .select("knot_id, joined_at")
            .execute()
            .value) ?? []
        let joinedAtMap = Dictionary(memberships.map { ($0.knotId, $0.joinedAt) },
                                     uniquingKeysWith: { a, _ in a })

        let reads: [DBAnnouncementRead]
        do {
            reads = try await supabase
                .from("announcement_reads")
                .select()
                .in("announcement_id", values: announcements.map { $0.id.uuidString.lowercased() })
                .execute()
                .value
        } catch {
            print("[AnnouncementService] fetchForUser reads error: \(error)")
            reads = []
        }

        let readMap = Dictionary(reads.map { ($0.announcementId, $0) }, uniquingKeysWith: { first, _ in first })

        return announcements.compactMap { ann in
            let r = readMap[ann.id]
            if r?.isDismissed == true { return nil }

            // Hide payment request alerts that were sent before this user joined the knot.
            if ann.paymentRequestId != nil,
               let knotID = ann.knotId,
               let joinedAt = joinedAtMap[knotID],
               ann.createdAt < joinedAt {
                return nil
            }

            return FetchedAnnouncement(
                announcement: ann,
                isRead      : r?.isRead   ?? false,
                isPinned    : r?.isPinned ?? ann.isPinned
            )
        }
    }

    /// Marks an announcement as read via a SECURITY DEFINER RPC.
    static func markRead(announcementID: UUID) async throws {
        do {
            try await supabase
                .rpc("mark_announcement_read", params: ["p_announcement_id": announcementID])
                .execute()
        } catch {
            print("[AnnouncementService] markRead error: \(error)")
            throw error
        }
    }

    /// Dismiss a single announcement for the current user (per-user, server-side).
    static func dismiss(announcementID: UUID) async throws {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        struct DismissUpsert: Encodable {
            let announcement_id : UUID
            let user_id         : UUID
            let is_read         : Bool
            let is_dismissed    : Bool
        }
        try await supabase
            .from("announcement_reads")
            .upsert(
                DismissUpsert(
                    announcement_id: announcementID,
                    user_id        : userID,
                    is_read        : true,
                    is_dismissed   : true
                ),
                onConflict: "announcement_id,user_id"
            )
            .execute()
    }

    /// Dismiss all currently-visible announcements for the current user.
    static func dismissAll(announcementIDs: [UUID]) async throws {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        guard !announcementIDs.isEmpty else { return }
        struct DismissUpsert: Encodable {
            let announcement_id : UUID
            let user_id         : UUID
            let is_read         : Bool
            let is_dismissed    : Bool
        }
        let rows = announcementIDs.map {
            DismissUpsert(announcement_id: $0, user_id: userID, is_read: true, is_dismissed: true)
        }
        try await supabase
            .from("announcement_reads")
            .upsert(rows, onConflict: "announcement_id,user_id")
            .execute()
    }

    /// Sends an announcement to a knot via a SECURITY DEFINER RPC.
    /// The RPC validates that the caller is a knot creator or co_admin.
    static func send(
        knotID: UUID,
        title: String,
        body: String,
        isPinned: Bool,
        images: [UIImage] = []
    ) async throws {
        struct Params: Encodable {
            let p_knot_id   : UUID
            let p_title     : String
            let p_body      : String
            let p_is_pinned : Bool
        }

        let plainBody = body
        var bodyToSend = plainBody

        if !images.isEmpty {
            do {
                let imageURLs = try await uploadImages(knotID: knotID, images: images)
                bodyToSend = AnnouncementBodyCodec.encode(body: body, imageURLs: imageURLs)
            } catch {
                print("[AnnouncementService] image upload failed; sending text-only alert instead: \(error)")
                bodyToSend = plainBody
            }
        }

        func sendRPC(with body: String) async throws {
            try await supabase
                .rpc("send_announcement", params: Params(
                    p_knot_id  : knotID,
                    p_title    : title,
                    p_body     : body,
                    p_is_pinned: isPinned
                ))
                .execute()
        }

        do {
            try await sendRPC(with: bodyToSend)
        } catch {
            if bodyToSend != plainBody {
                print("[AnnouncementService] rich alert send failed; retrying text-only alert: \(error)")
                try await sendRPC(with: plainBody)
                return
            }
            print("[AnnouncementService] send error: \(error)")
            throw error
        }

        // Fire-and-forget push notifications to all knot members
        Task {
            do {
                guard let me = supabase.auth.currentUser?.id else { return }
                struct MemberRow: Decodable { let user_id: UUID }
                let members: [MemberRow] = try await supabase
                    .from("knot_members")
                    .select("user_id")
                    .eq("knot_id", value: knotID)
                    .neq("user_id", value: me)
                    .execute()
                    .value
                for m in members {
                    await NotificationManager.notify(
                        userID: m.user_id,
                        title : title,
                        body  : body.count > 80 ? String(body.prefix(80)) + "…" : body,
                        target: "alerts"
                    )
                }
            } catch {
                print("[AnnouncementService] notification error: \(error)")
            }
        }
    }
}
