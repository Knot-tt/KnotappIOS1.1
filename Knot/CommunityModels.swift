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
    case free      = "Free"
    case perSession = "Per Session"
    case oneTime   = "One Time"
}

// MARK: - Form Question
struct FormQuestion: Identifiable, Hashable {
    enum QuestionType: String, CaseIterable {
        case openEnded = "Open Ended"
        case mcq       = "Multiple Choice"
    }

    var id       = UUID()
    var type     : QuestionType = .openEnded
    var prompt   : String       = ""
    var options  : [String]     = ["Option 1", "Option 2"]
    var required : Bool         = true
}

// MARK: - Join Request
struct JoinRequest: Identifiable {
    enum Status { case pending, approved, rejected }

    let id            = UUID()        // local identity for SwiftUI
    var dbID          : UUID?         // Supabase row id
    var applicantID   : UUID?         // Supabase applicant user id
    let applicantName : String
    var answers       : [UUID: String] = [:]
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
    var joinFormQuestions : [FormQuestion]  = []
    var memberNames       : [String]       = []   // non-admin members
    var coAdminNames      : [String]       = []   // co-admins (not the main admin)
    var memberUUIDs       : [String: UUID] = [:]  // name → UUID for all members (used for creator transfer)

    init(
        id               : UUID            = UUID(),
        name             : String,
        imageName        : String,
        description      : String,
        memberCount      : Int,
        category         : String,
        location         : String,
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
        joinFormQuestions: [FormQuestion]  = [],
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
        self.joinFormQuestions = joinFormQuestions
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
