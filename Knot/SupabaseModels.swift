//
//  SupabaseModels.swift
//  Knot
//
//  Codable structs that map 1:1 to Supabase database rows.
//  These are the data-transfer layer — separate from the view-model types.
//  Convert to/from app models in SupabaseManager service methods.
//

import Foundation

// MARK: - DBProfile

struct DBProfile: Codable, Sendable, Identifiable {
    let id              : UUID
    var name            : String
    var bio             : String
    var profileImage    : String?   // Storage public URL
    // Address fields are intentionally NOT in this model anymore — they live in
    // the `profile_address` table with strict per-user RLS. Read via
    // `ProfileService.fetchAddress()` and write via `updateAddress(...)`.
    var isPrivate       : Bool
    var showKnots       : Bool
    var showListings    : Bool
    var showConnections : Bool
    var stripeCustomerId    : String?
    var stripeConnectId     : String?
    var onboardingComplete  : Bool
    var hasSeenWelcome      : Bool
    var createdAt           : Date
    var updatedAt           : Date

    enum CodingKeys: String, CodingKey {
        case id, name, bio
        case profileImage        = "profile_image"
        case isPrivate           = "is_private"
        case showKnots           = "show_knots"
        case showListings        = "show_listings"
        case showConnections     = "show_connections"
        case stripeCustomerId    = "stripe_customer_id"
        case stripeConnectId     = "stripe_connect_id"
        case onboardingComplete  = "onboarding_complete"
        case hasSeenWelcome      = "has_seen_welcome"
        case createdAt           = "created_at"
        case updatedAt           = "updated_at"
    }
}

// Used for upsert — omits generated/read-only fields.
// Address fields live in `profile_address` (strict per-user RLS). Use
// `ProfileService.updateAddress(...)` to persist those — they are NOT written here.
struct DBProfileUpdate: Codable, Sendable {
    var name            : String
    var bio             : String
    var profileImage    : String?
    var isPrivate       : Bool
    var showKnots       : Bool
    var showListings    : Bool
    var showConnections : Bool

    enum CodingKeys: String, CodingKey {
        case name, bio
        case profileImage    = "profile_image"
        case isPrivate       = "is_private"
        case showKnots       = "show_knots"
        case showListings    = "show_listings"
        case showConnections = "show_connections"
    }
}


// MARK: - DBConnection

struct DBConnection: Codable, Sendable {
    let id          : UUID
    let requesterId : UUID
    let recipientId : UUID
    var status      : String    // "pending" | "accepted" | "declined"
    let createdAt   : Date
    var updatedAt   : Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterId = "requester_id"
        case recipientId = "recipient_id"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}


// MARK: - DBKnot

struct DBKnot: Codable, Sendable {
    let id                          : UUID
    let creatorId                   : UUID
    var name                        : String
    var description                 : String
    var imageUrl                    : String?
    var category                    : String
    var location                    : String
    var isPublic                    : Bool
    var isEvent                     : Bool
    var requiresApproval            : Bool
    var isConnectionsOnly           : Bool
    var hideLocationFromNonMembers  : Bool
    var maxMembers                  : Int?
    var ageGroup                    : String
    var minAge                      : Int
    var maxAge                      : Int
    var isPaid                      : Bool
    var paymentType                 : String
    var priceCents                  : Int
    var memberCount                 : Int
    var ratingSum                   : Int = 0
    var ratingCount                 : Int = 0
    let createdAt                   : Date
    var updatedAt                   : Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, location
        case creatorId                  = "creator_id"
        case imageUrl                   = "image_url"
        case isPublic                   = "is_public"
        case isEvent                    = "is_event"
        case requiresApproval           = "requires_approval"
        case isConnectionsOnly          = "is_connections_only"
        case hideLocationFromNonMembers = "hide_location_from_non_members"
        case maxMembers                 = "max_members"
        case ageGroup                   = "age_group"
        case minAge                     = "min_age"
        case maxAge                     = "max_age"
        case isPaid                     = "is_paid"
        case paymentType                = "payment_type"
        case priceCents                 = "price_cents"
        case memberCount                = "member_count"
        case ratingSum                  = "rating_sum"
        case ratingCount                = "rating_count"
        case createdAt                  = "created_at"
        case updatedAt                  = "updated_at"
    }
}


// MARK: - DBKnotRating

struct DBKnotRating: Codable, Sendable {
    let id        : UUID
    let knotId    : UUID
    let userId    : UUID
    var rating    : Int           // 1–5
    let createdAt : Date

    enum CodingKeys: String, CodingKey {
        case id, rating
        case knotId    = "knot_id"
        case userId    = "user_id"
        case createdAt = "created_at"
    }
}


// MARK: - DBKnotMember

struct DBKnotMember: Codable, Sendable {
    let id          : UUID
    let knotId      : UUID
    let userId      : UUID
    var role        : String      // "member" | "co_admin" | "creator"
    let joinedAt    : Date
    var lastPaidAt  : Date?

    enum CodingKeys: String, CodingKey {
        case id, role
        case knotId     = "knot_id"
        case userId     = "user_id"
        case joinedAt   = "joined_at"
        case lastPaidAt = "last_paid_at"
    }
}


// MARK: - DBJoinRequest

struct DBJoinRequest: Codable, Sendable {
    let id           : UUID
    let knotId       : UUID
    let applicantId  : UUID
    var status       : String             // "pending" | "approved" | "rejected"
    let submittedAt  : Date
    var reviewedAt   : Date?
    var reviewedBy   : UUID?

    enum CodingKeys: String, CodingKey {
        case id, status
        case knotId      = "knot_id"
        case applicantId = "applicant_id"
        case submittedAt = "submitted_at"
        case reviewedAt  = "reviewed_at"
        case reviewedBy  = "reviewed_by"
    }
}


// MARK: - DBConversation

struct DBConversation: Codable, Sendable {
    let id            : UUID
    var isGroup       : Bool
    var groupName     : String?
    var groupImageUrl : String?
    var groupDescription : String? = nil
    let creatorId     : UUID
    var sourceKnotId  : UUID?
    let createdAt     : Date
    var updatedAt     : Date

    enum CodingKeys: String, CodingKey {
        case id
        case isGroup      = "is_group"
        case groupName    = "group_name"
        case groupImageUrl = "group_image_url"
        case groupDescription = "group_description"
        case creatorId    = "creator_id"
        case sourceKnotId = "source_knot_id"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }
}


// MARK: - DBConversationParticipant

struct DBConversationParticipant: Codable, Sendable {
    let id              : UUID
    let conversationId  : UUID
    let userId          : UUID
    var isAdmin         : Bool
    var isCreator       : Bool
    var isFavourite     : Bool
    var hasLeft         : Bool
    var lastReadAt      : Date?
    let joinedAt        : Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case userId         = "user_id"
        case isAdmin        = "is_admin"
        case isCreator      = "is_creator"
        case isFavourite    = "is_favourite"
        case hasLeft        = "has_left"
        case lastReadAt     = "last_read_at"
        case joinedAt       = "joined_at"
    }
}


// MARK: - DBMessage

struct DBMessage: Codable, Sendable {
    let id              : UUID
    let conversationId  : UUID
    var senderId        : UUID?     // nil for system messages
    var text            : String
    var imageUrl        : String?
    var videoUrl        : String?
    var replyToId       : UUID?
    var isSystem        : Bool
    var isStarred       : Bool
    var status          : String    // "sent" | "delivered" | "read"
    let createdAt       : Date

    enum CodingKeys: String, CodingKey {
        case id, text, status
        case conversationId = "conversation_id"
        case senderId       = "sender_id"
        case imageUrl       = "image_url"
        case videoUrl       = "video_url"
        case replyToId      = "reply_to_id"
        case isSystem       = "is_system"
        case isStarred      = "is_starred"
        case createdAt      = "created_at"
    }
}


// MARK: - DBShopListing

struct DBShopListing: Codable, Sendable {
    let id           : UUID
    let sellerId     : UUID
    var listingType  : String   // "item" | "service" | "advertisement"
    var category     : String
    var condition    : String
    var name         : String
    var description  : String
    var link         : String
    var priceCents   : Int
    var imageUrls    : [String]
    var isActive     : Bool
    var isRecurring  : Bool   // true = stays listed after a sale; false = removed when sold
    var acceptsCash  : Bool
    var acceptsCard  : Bool
    let createdAt    : Date
    var updatedAt    : Date

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
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}


// MARK: - DBOrder

struct DBOrder: Codable, Sendable {
    let id                      : String    // "#KN-XXXXX"
    let listingId               : UUID
    let buyerId                 : UUID
    let sellerId                : UUID
    var subtotalCents           : Int
    var knotFeeRate             : Double
    let knotFeeCents            : Int       // generated column
    let payoutCents             : Int       // generated column
    var fulfilment              : String    // "meetup" | "delivery"
    var paymentMethod           : String    // "cash" | "card"
    var deliveryAddress         : String
    var status                  : String
    var escrowStatus            : String
    var meetupLocation          : String?
    var meetupDate              : Date?
    var meetupProposedBy        : String?
    var pendingAt               : Date?
    var paidAt                  : Date?    // set client-side once Stripe confirms the charge
    var sellerAcceptedAt        : Date?
    var meetupAgreedAt          : Date?
    var awaitingConfirmationAt  : Date?
    var completeAt              : Date?
    var disputedAt              : Date?
    var cancelledAt             : Date?
    var stripePaymentIntentId   : String?
    var stripeTransferId        : String?
    let createdAt               : Date
    var updatedAt               : Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case listingId              = "listing_id"
        case buyerId                = "buyer_id"
        case sellerId               = "seller_id"
        case subtotalCents          = "subtotal_cents"
        case knotFeeRate            = "knot_fee_rate"
        case knotFeeCents           = "knot_fee_cents"
        case payoutCents            = "payout_cents"
        case fulfilment             = "fulfilment"
        case paymentMethod          = "payment_method"
        case deliveryAddress        = "delivery_address"
        case escrowStatus           = "escrow_status"
        case meetupLocation         = "meetup_location"
        case meetupDate             = "meetup_date"
        case meetupProposedBy       = "meetup_proposed_by"
        case pendingAt              = "pending_at"
        case paidAt                 = "paid_at"
        case sellerAcceptedAt       = "seller_accepted_at"
        case meetupAgreedAt         = "meetup_agreed_at"
        case awaitingConfirmationAt = "awaiting_confirmation_at"
        case completeAt             = "complete_at"
        case disputedAt             = "disputed_at"
        case cancelledAt            = "cancelled_at"
        case stripePaymentIntentId  = "stripe_payment_intent_id"
        case stripeTransferId       = "stripe_transfer_id"
        case createdAt              = "created_at"
        case updatedAt              = "updated_at"
    }
}


// MARK: - DBStripePaymentMethod

struct DBStripePaymentMethod: Codable, Sendable {
    let id                      : UUID
    let userId                  : UUID
    let stripePaymentMethodId   : String    // "pm_xxx"
    var brand                   : String
    var last4                   : String
    var expMonth                : Int
    var expYear                 : Int
    var isDefault               : Bool
    let createdAt               : Date

    enum CodingKeys: String, CodingKey {
        case id, brand
        case userId                 = "user_id"
        case stripePaymentMethodId  = "stripe_payment_method_id"
        case last4                  = "last4"
        case expMonth               = "exp_month"
        case expYear                = "exp_year"
        case isDefault              = "is_default"
        case createdAt              = "created_at"
    }
}


// MARK: - DBAnnouncement

struct DBAnnouncement: Codable, Sendable {
    let id                : UUID
    var knotId            : UUID?
    let senderId          : UUID
    var title             : String
    var body              : String
    var isPinned          : Bool
    var paymentRequestId  : UUID?
    let createdAt         : Date

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case knotId           = "knot_id"
        case senderId         = "sender_id"
        case isPinned         = "is_pinned"
        case paymentRequestId = "payment_request_id"
        case createdAt        = "created_at"
    }
}


// MARK: - DBAnnouncementRead

struct DBAnnouncementRead: Codable, Sendable {
    let announcementId  : UUID
    let userId          : UUID
    var isRead          : Bool
    var isPinned        : Bool
    var isDismissed     : Bool
    var readAt          : Date?

    enum CodingKeys: String, CodingKey {
        case announcementId = "announcement_id"
        case userId         = "user_id"
        case isRead         = "is_read"
        case isPinned       = "is_pinned"
        case isDismissed    = "is_dismissed"
        case readAt         = "read_at"
    }
}


// MARK: - Announcement body media payload

struct AnnouncementMediaPayload: Codable, Sendable {
    let body: String
    let imageURLs: [String]
}

struct DecodedAnnouncementBody: Sendable {
    let body: String
    let imageURLs: [String]
}

enum AnnouncementBodyCodec {
    private static let prefix = "\n\n[KNOT_MEDIA:"
    private static let suffix = "]"

    static func encode(body: String, imageURLs: [String]) -> String {
        let trimmedURLs = Array(imageURLs.prefix(5))
        guard !trimmedURLs.isEmpty else { return body }
        let payload = AnnouncementMediaPayload(body: body, imageURLs: trimmedURLs)
        guard let data = try? JSONEncoder().encode(payload) else {
            return body
        }
        return body + prefix + data.base64EncodedString() + suffix
    }

    static func decode(_ rawBody: String) -> DecodedAnnouncementBody {
        guard
            rawBody.hasSuffix(suffix),
            let markerRange = rawBody.range(of: prefix, options: .backwards)
        else {
            return DecodedAnnouncementBody(body: rawBody, imageURLs: [])
        }

        let encodedRange = markerRange.upperBound..<rawBody.index(before: rawBody.endIndex)
        let encoded = String(rawBody[encodedRange])

        guard
            let data = Data(base64Encoded: encoded),
            let payload = try? JSONDecoder().decode(AnnouncementMediaPayload.self, from: data)
        else {
            return DecodedAnnouncementBody(body: rawBody, imageURLs: [])
        }

        return DecodedAnnouncementBody(
            body: payload.body,
            imageURLs: Array(payload.imageURLs.prefix(5))
        )
    }
}

