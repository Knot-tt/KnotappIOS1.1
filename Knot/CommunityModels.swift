import SwiftUI

// MARK: - Group View Mode
enum GroupViewMode: String, CaseIterable {
    case all       = "All Knots"
    case yours     = "Your Knots"
    case manage    = "Manage Knots"
    case requested = "Requested Knots"
    case events    = "Knot Events"
}

// MARK: - Age Group
enum AgeGroup: String, CaseIterable, Codable {
    case any      = "Any Age"
    case teen     = "Teens (13–17)"
    case young    = "Young Adults (18–25)"
    case adult    = "Adults (26–54)"
    case senior   = "Seniors (55+)"
    case custom   = "Custom Range"
}

// MARK: - Payment Type
enum KnotPaymentType: String, CaseIterable {
    case free       = "Free"
    case join       = "Join"       // new default — pay to join
    case perSession = "Per Session" // legacy
    case oneTime    = "One Time"   // legacy
}

// MARK: - Join Request
struct JoinRequest: Identifiable {
    enum Status { case pending, approved, rejected }

    let id            = UUID()        // local identity for SwiftUI
    var dbID          : UUID?         // Supabase row id
    var applicantID   : UUID?         // Supabase applicant user id
    let applicantName : String
    var submittedAt   : Date = Date()
    var status        : Status = .pending
}

// MARK: - Admin Action Request
struct AdminActionRequest: Identifiable {
    enum ActionType {
        case makeAdmin, dismissAdmin, kick
        var label: String {
            switch self {
            case .makeAdmin:    return "wants to make"
            case .dismissAdmin: return "wants to dismiss"
            case .kick:         return "wants to kick"
            }
        }
        var suffix: String {
            switch self {
            case .makeAdmin:    return "an admin"
            case .dismissAdmin: return "as admin"
            case .kick:         return "from the group"
            }
        }
    }
    enum Status { case pending, approved, rejected }

    let id                  = UUID()
    let groupID             : UUID
    let groupName           : String
    let requestingAdminName : String
    let targetMemberName    : String
    let actionType          : ActionType
    let timestamp           : Date     = Date()
    var status              : Status   = .pending
}


// MARK: - Community Group (Knot) Model
struct CommunityGroup: Identifiable {
    let id: UUID

    var name              : String
    var imageName         : String
    var imageURL          : String?        = nil   // uploaded cover photo
    var description       : String
    var memberCount       : Int
    var category          : String
    var location          : String
    /// Creator's user UUID. Used as the source of truth for "who made this knot".
    /// `adminName` is a denormalised display string that must be kept in sync with the
    /// creator's current profile name — see UserProfile.refreshOwnKnotAdminNames().
    var creatorID                  : UUID?           = nil
    var adminName                  : String          = "Unknown"
    var maxMembers                 : Int?            = nil
    var requiresApproval           : Bool            = false
    var isPublic                   : Bool            = true
    var isEvent                    : Bool            = false
    var isConnectionsOnly          : Bool            = false
    var hideLocationFromNonMembers : Bool            = false
    var ageGroup          : AgeGroup        = .any
    var minAge            : Int             = 13
    var maxAge            : Int             = 99
    var isPaid            : Bool            = false
    var paymentType       : KnotPaymentType = .free
    var price             : Int             = 0
    var memberNames       : [String]       = []   // non-admin members — DISPLAY ONLY
    var coAdminNames      : [String]       = []   // co-admins — DISPLAY ONLY
    var coAdminIDs        : Set<UUID>      = []   // co-admin IDENTITY — used for privilege checks (survives renames)
    var memberUUIDs       : [String: UUID]  = [:]  // name → UUID lookup for member rows (display layer)
    var memberLastPaidAt  : [UUID: Date]    = [:]  // member UUID → last paid timestamp

    // ── Ratings ──────────────────────────────────────────────────────────
    // Maintained server-side on the knots row (rating_sum / rating_count).
    var ratingSum         : Int             = 0
    var ratingCount       : Int             = 0

    /// Raw mean of all star ratings (0 if none yet).
    var averageRating: Double {
        ratingCount > 0 ? Double(ratingSum) / Double(ratingCount) : 0
    }

    /// Average snapped to the nearest 0.5 — what the 5-star template displays.
    var roundedRating: Double {
        (averageRating * 2).rounded() / 2
    }

    init(
        id               : UUID            = UUID(),
        name             : String,
        imageName        : String,
        description      : String,
        memberCount      : Int,
        category         : String,
        location         : String,
        creatorID                  : UUID?           = nil,
        adminName                  : String          = "Unknown",
        maxMembers                 : Int?            = nil,
        requiresApproval           : Bool            = false,
        isPublic                   : Bool            = true,
        isEvent                    : Bool            = false,
        isConnectionsOnly          : Bool            = false,
        hideLocationFromNonMembers : Bool            = false,
        ageGroup         : AgeGroup        = .any,
        minAge           : Int             = 13,
        maxAge           : Int             = 99,
        isPaid           : Bool            = false,
        paymentType      : KnotPaymentType = .free,
        price            : Int             = 0,
        memberNames      : [String]        = [],
        coAdminNames     : [String]        = []
    ) {
        self.id                = id
        self.name              = name
        self.imageName         = imageName
        self.description       = description
        self.memberCount       = memberCount
        self.category          = category
        self.location          = location
        self.creatorID         = creatorID
        self.adminName         = adminName
        self.maxMembers        = maxMembers
        self.requiresApproval           = requiresApproval
        self.isPublic                   = isPublic
        self.isEvent                    = isEvent
        self.isConnectionsOnly          = isConnectionsOnly
        self.hideLocationFromNonMembers = hideLocationFromNonMembers
        self.ageGroup          = ageGroup
        self.minAge            = minAge
        self.maxAge            = maxAge
        self.isPaid            = isPaid
        self.paymentType       = paymentType
        self.price             = price
        self.memberNames       = memberNames
        self.coAdminNames      = coAdminNames
    }
}

// MARK: - Category → SF Symbol
func categoryIcon(_ category: String) -> String {
    switch category {
    case "Photography":   return "camera.circle.fill"
    case "Food":          return "fork.knife.circle.fill"
    case "Fitness":       return "figure.run.circle.fill"
    case "Reading":       return "book.circle.fill"
    case "Gaming":        return "gamecontroller.circle.fill"
    case "Arts":          return "paintbrush.circle.fill"
    case "Music":         return "music.note.list"
    case "Education":     return "graduationcap.circle.fill"
    case "Gardening":     return "leaf.circle.fill"
    case "Entertainment": return "film.circle.fill"
    case "Technology":    return "cpu.circle.fill"
    case "Outdoors":      return "mountain.2.circle.fill"
    default:              return "circle.grid.cross.fill"
    }
}

// MARK: - Sample Knots
// Replaced by real Supabase data loaded in UserProfile.loadKnots()
let sampleGroups: [CommunityGroup] = []
