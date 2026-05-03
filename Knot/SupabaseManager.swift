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
        return try await supabase
            .from("profiles")
            .select("id, name, bio, profile_image, is_private, show_knots, show_listings, show_connections, street, city, postal_code, country, created_at, updated_at")
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
        try await supabase
            .from("profiles")
            .select("id, name, bio, profile_image, is_private, show_knots, show_listings, show_connections, created_at, updated_at")
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
}


// MARK: - ShopService

enum ShopService {

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

        enum CodingKeys: String, CodingKey {
            case id, name, description, link, condition, category
            case sellerId    = "seller_id"
            case listingType = "listing_type"
            case priceCents  = "price_cents"
            case imageUrls   = "image_urls"
            case isActive    = "is_active"
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

    static func create(
        type      : ListingType,
        category  : ShopCategory,
        condition : ItemCondition,
        name      : String,
        description: String,
        link      : String,
        price     : Int,
        images    : [UIImage]
    ) async throws -> DBShopListing {
        guard let me = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let listingID = UUID()

        var imageURLs: [String] = []
        for (i, img) in images.enumerated() {
            guard let data = img.jpegData(compressionQuality: 0.8) else { continue }
            let path = "\(listingID.uuidString.lowercased())/\(i).jpg"
            do {
                try await supabase.storage
                    .from(Bucket.listingImages)
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                let url = try supabase.storage
                    .from(Bucket.listingImages)
                    .getPublicURL(path: path)
                imageURLs.append(url.absoluteString)
            } catch {
                print("[ShopService] image upload failed at index \(i): \(error)")
            }
        }

        let insert = ListingInsert(
            id: listingID, sellerId: me,
            listingType: type.rawValue.lowercased(),
            category: category.dbValue,
            condition: condition.dbValue,
            name: name, description: description, link: link,
            priceCents: price * 100,
            imageUrls: imageURLs, isActive: true
        )
        try await supabase.from("shop_listings").insert(insert).execute()

        return DBShopListing(
            id: listingID, sellerId: me,
            listingType: type.rawValue.lowercased(),
            category: category.dbValue,
            condition: condition.dbValue,
            name: name, description: description, link: link,
            priceCents: price * 100,
            imageUrls: imageURLs, isActive: true,
            createdAt: Date(), updatedAt: Date()
        )
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


// MARK: - OrderService
// Phase 7 — creates/releases go through Edge Functions; status transitions are direct DB UPDATEs.

enum OrderService {

    private struct CreateOrderPayload: Encodable {
        let listingId      : String
        let fulfilment     : String
        let deliveryAddress: String?
        let meetupLocation : String?
        let meetupDateISO  : String?
    }

    private struct CreateOrderResponse: Decodable {
        let orderId      : String
        let clientSecret : String
        let customerId   : String
        let ephemeralKey : String
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

    /// Calls the create-order Edge Function.
    /// Returns (orderID, clientSecret) — clientSecret reserved for Stripe PaymentSheet integration.
    static func createOrder(listingID: UUID, fulfilment: FulfilmentMethod, deliveryAddress: String, meetupLocation: String = "", meetupDate: Date? = nil) async throws -> (orderID: String, clientSecret: String, customerId: String, ephemeralKey: String) {
        let isoFormatter = ISO8601DateFormatter()
        let payload = CreateOrderPayload(
            listingId      : listingID.uuidString.lowercased(),
            fulfilment     : fulfilment.dbValue,
            deliveryAddress: fulfilment == .delivery ? deliveryAddress : nil,
            meetupLocation : fulfilment == .meetup ? meetupLocation : nil,
            meetupDateISO  : meetupDate.map { isoFormatter.string(from: $0) }
        )
        let response: CreateOrderResponse = try await supabase.functions
            .invoke("create-order", options: FunctionInvokeOptions(body: payload))
        return (orderID: response.orderId, clientSecret: response.clientSecret, customerId: response.customerId, ephemeralKey: response.ephemeralKey)
    }

    /// Calls the release-escrow Edge Function, which captures the Stripe PaymentIntent
    /// and marks the order complete in one atomic operation.
    static func releaseEscrow(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await supabase.functions
            .invoke("release-escrow", options: FunctionInvokeOptions(body: Payload(orderId: orderID)))
    }

    /// Proposes or counter-proposes a meetup via edge function.
    static func proposeMeetup(orderID: String, location: String, date: Date, proposedBy: String) async throws {
        struct Payload: Encodable {
            let orderId   : String
            let location  : String
            let dateISO   : String
            let proposedBy: String
        }
        struct Response: Decodable { let success: Bool }
        let iso = ISO8601DateFormatter()
        let _: Response = try await supabase.functions
            .invoke("propose-meetup", options: FunctionInvokeOptions(
                body: Payload(orderId: orderID, location: location,
                              dateISO: iso.string(from: date), proposedBy: proposedBy)
            ))
    }

    /// Accepts the current meetup proposal via edge function.
    static func acceptMeetup(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await supabase.functions
            .invoke("accept-meetup", options: FunctionInvokeOptions(body: Payload(orderId: orderID)))
    }

    /// Cancels the order via edge function.
    static func cancelOrder(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await supabase.functions
            .invoke("cancel-order", options: FunctionInvokeOptions(body: Payload(orderId: orderID)))
    }

    /// Marks order as disputed via edge function.
    static func disputeOrder(orderID: String) async throws {
        struct Payload: Encodable { let orderId: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await supabase.functions
            .invoke("dispute-order", options: FunctionInvokeOptions(body: Payload(orderId: orderID)))
    }
}


// MARK: - AnnouncementService

enum AnnouncementService {

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

        return announcements.map { ann in
            let r = readMap[ann.id]
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

    /// Sends an announcement to a knot via a SECURITY DEFINER RPC.
    /// The RPC validates that the caller is a knot creator or co_admin.
    static func send(knotID: UUID, title: String, body: String, isPinned: Bool) async throws {
        struct Params: Encodable {
            let p_knot_id   : UUID
            let p_title     : String
            let p_body      : String
            let p_is_pinned : Bool
        }
        do {
            try await supabase
                .rpc("send_announcement", params: Params(
                    p_knot_id  : knotID,
                    p_title    : title,
                    p_body     : body,
                    p_is_pinned: isPinned
                ))
                .execute()
        } catch {
            print("[AnnouncementService] send error: \(error)")
            throw error
        }
    }
}
