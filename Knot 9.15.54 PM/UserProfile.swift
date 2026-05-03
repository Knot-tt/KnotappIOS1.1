import SwiftUI
import UIKit
import Observation

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
    var name         : String    = ""
    var bio          : String    = ""
    var street       : String    = ""
    var city         : String    = ""
    var postalCode   : String    = ""
    var country      : String    = ""
    var profileImage : UIImage?  = nil

    // Privacy
    var isPrivateAccount : Bool = false

    // Mock privacy settings for other users (replace with Supabase fetch)
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

    // Join requests received on groups you manage: groupID → [JoinRequest]
    var joinRequests: [UUID: [JoinRequest]] = [:]

    var pendingAdminActions: [AdminActionRequest] = []

    // Connections
    var connections               : [String] = []
    var sentConnectionRequests    : [String] = []
    var receivedConnectionRequests: [String] = []
    var notifications             : [AppNotification] = []

    // Shop listings
    var myListings              : [ShopListing] = []
    var orders                  : [KnotOrder]   = []
    var savedCards              : [SavedCard]   = []
    // Alerts / Announcements
    var announcements           : [Announcement] = sampleAnnouncements
    // Profile display toggles
    var showKnotsOnProfile      : Bool = true
    var showListingsOnProfile   : Bool = true
    var showConnectionsOnProfile: Bool = true

    // Conversations
    var conversations             : [Conversation] = []
    var pendingChatConversationID : UUID?           = nil

    init(name: String) {
        self.name = name
        self.conversations = makeSampleConversations(myName: name)
        // Sample pending requests — remove when Supabase is connected
        self.receivedConnectionRequests = ["Ahmad Khalid", "Lin Hui"]
        // Test knot — user is creator so admin features can be tested
        let testKnot = CommunityGroup(
            name: "Morning Joggers",
            imageName: "figure.run.circle.fill",
            description: "A small neighbourhood group for early morning jogs around the park. Everyone is welcome regardless of pace.",
            memberCount: 5,
            category: "Fitness",
            location: "Bishan Park, Singapore",
            adminName: name,
            memberNames: ["Wei Ming", "Sarah Tan", "James Lim", "Priya Nair"],
            coAdminNames: ["Wei Ming"]
        )
        // Second knot — user is creator
        let testKnot2 = CommunityGroup(
            name: "Book Club",
            imageName: "books.vertical.circle.fill",
            description: "A monthly neighbourhood book club. We read fiction and non-fiction and meet at someone's home each time.",
            memberCount: 6,
            category: "Reading",
            location: "Toa Payoh, Singapore",
            adminName: name,
            requiresApproval: true,
            memberNames: ["Sarah Tan", "Priya Nair", "Lin Hui", "Ahmad Khalid", "Ravi Kumar"],
            coAdminNames: ["Sarah Tan"]
        )

        // Knot where user is a co-admin (created by Wei Ming)
        let coAdminKnot = CommunityGroup(
            name: "Foodie Neighbours",
            imageName: "fork.knife.circle.fill",
            description: "Sharing the best hawker finds, restaurant recommendations, and occasional group dinners around the neighbourhood.",
            memberCount: 8,
            category: "Food",
            location: "Ang Mo Kio, Singapore",
            adminName: "Wei Ming",
            memberNames: [name, "James Lim", "Priya Nair", "Ahmad Khalid", "Lin Hui", "Ravi Kumar", "David Chen"],
            coAdminNames: [name]
        )

        self.createdGroups = [testKnot, testKnot2]
        self.joinedGroupIDs = [testKnot.id, testKnot2.id, coAdminKnot.id]

        // 2 pending join requests for Morning Joggers
        self.joinRequests = [
            testKnot.id: [
                JoinRequest(applicantName: "Ravi Kumar",  submittedAt: Date().addingTimeInterval(-7200)),
                JoinRequest(applicantName: "David Chen",  submittedAt: Date().addingTimeInterval(-3600)),
            ]
        ]

        // Add co-admin knot to createdGroups so it appears in community/manage views
        self.createdGroups.append(coAdminKnot)
    }

    var initial: String { String(name.prefix(1)).uppercased() }

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

    func updateCreatedGroup(_ updated: CommunityGroup) {
        guard let idx = createdGroups.firstIndex(where: { $0.id == updated.id }) else { return }
        createdGroups[idx] = updated
    }


    // MARK: - Admin Action helpers

    func requestAdminAction(groupID: UUID, groupName: String, requestingAdmin: String, target: String, action: AdminActionRequest.ActionType) {
        let req = AdminActionRequest(groupID: groupID, groupName: groupName, requestingAdminName: requestingAdmin, targetMemberName: target, actionType: action)
        pendingAdminActions.append(req)
    }

    func approveAdminAction(id reqID: UUID) {
        guard let idx = pendingAdminActions.firstIndex(where: { $0.id == reqID }) else { return }
        let req = pendingAdminActions[idx]
        pendingAdminActions[idx].status = .approved
        // Apply the action
        guard let gi = createdGroups.firstIndex(where: { $0.id == req.groupID }) else { return }
        switch req.actionType {
        case .makeAdmin:
            if !createdGroups[gi].coAdminNames.contains(req.targetMemberName) {
                createdGroups[gi].coAdminNames.append(req.targetMemberName)
            }
        case .dismissAdmin:
            createdGroups[gi].coAdminNames.removeAll { $0 == req.targetMemberName }
        case .kick:
            createdGroups[gi].memberNames.removeAll { $0 == req.targetMemberName }
            createdGroups[gi].coAdminNames.removeAll { $0 == req.targetMemberName }
        }
    }

    func rejectAdminAction(id reqID: UUID) {
        guard let idx = pendingAdminActions.firstIndex(where: { $0.id == reqID }) else { return }
        pendingAdminActions[idx].status = .rejected
    }

    // MARK: - Connection helpers

    func acceptConnectionRequest(from name: String) {
        receivedConnectionRequests.removeAll { $0 == name }
        if !connections.contains(name) { connections.append(name) }
        // TODO: Supabase — persist connection
    }

    func declineConnectionRequest(from name: String) {
        receivedConnectionRequests.removeAll { $0 == name }
        // TODO: Supabase — notify sender
    }

    func sendConnectionRequest(to targetName: String) {
        guard !sentConnectionRequests.contains(targetName),
              !connections.contains(targetName)
        else { return }
        sentConnectionRequests.append(targetName)
        // TODO: Supabase — push notification to recipient
    }

    func openKnotGroupChat(knotID: UUID, knotName: String) {
        if !conversations.contains(where: { $0.sourceKnotID == knotID && $0.isGroup }) {
            var c = Conversation(
                isGroup: true,
                groupName: "\(knotName) Chat",
                participants: [],
                messages: []
            )
            c.sourceKnotID   = knotID
            c.sourceKnotName = knotName
            c.adminNames     = [name]
            c.creatorName    = name
            conversations.insert(c, at: 0)
        }
        let id = conversations.first { $0.sourceKnotID == knotID && $0.isGroup }?.id
        selectedTab = .messages
        pendingChatConversationID = id
    }

    // MARK: - Group Chat Admin helpers

    func renameConversation(id convID: UUID, to newName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupName = newName
    }

    func updateConversationImage(id convID: UUID, image: UIImage?) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].groupImage = image
    }

    func makeAdminInConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        if !conversations[idx].adminNames.contains(memberName) {
            conversations[idx].adminNames.append(memberName)
        }
    }

    func demoteAdminInConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        // The creator can never be demoted
        guard conversations[idx].creatorName != memberName else { return }
        conversations[idx].adminNames.removeAll { $0 == memberName }
    }

    func kickFromConversation(id convID: UUID, memberName: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[idx].participants.removeAll { $0 == memberName }
        conversations[idx].adminNames.removeAll   { $0 == memberName }
        // If this is a knot group chat, also remove from the knot
        if let knotID = conversations[idx].sourceKnotID,
           let gi = createdGroups.firstIndex(where: { $0.id == knotID }) {
            createdGroups[gi].memberNames.removeAll  { $0 == memberName }
            createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
        }
    }

    func leaveConversation(id convID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == convID }) else { return }
        // Reassign creator role if leaving user is the creator
        if conversations[idx].creatorName == name {
            let otherAdmins = conversations[idx].adminNames.filter { $0 != name }
            if let newCreator = otherAdmins.randomElement() {
                conversations[idx].creatorName = newCreator
            } else if let newCreator = conversations[idx].participants.filter({ $0 != name }).randomElement() {
                conversations[idx].creatorName = newCreator
                conversations[idx].adminNames.append(newCreator)
            }
        }
        conversations[idx].adminNames.removeAll { $0 == name }
        conversations[idx].participants.removeAll { $0 == name }
        // Post system message before marking as left
        let systemMsg = ChatMessage(text: "\(name) left the group.",
                                    sender: "system",
                                    timestamp: Date(),
                                    isSystem: true)
        conversations[idx].messages.append(systemMsg)
        conversations[idx].hasLeft = true
        // If bound to a knot, also leave the knot
        if let knotID = conversations[idx].sourceKnotID { joinedGroupIDs.remove(knotID) }
    }

    func leaveKnot(groupID: UUID) {
        // Remove from joined set
        joinedGroupIDs.remove(groupID)
        requestedGroupIDs.remove(groupID)
        // Find if we're the creator in createdGroups
        if let gi = createdGroups.firstIndex(where: { $0.id == groupID && $0.adminName == name }) {
            // Reassign creator: try a co-admin first, then a random member
            let coAdmins = createdGroups[gi].coAdminNames
            if let newCreator = coAdmins.randomElement() {
                createdGroups[gi].adminName = newCreator
                createdGroups[gi].coAdminNames.removeAll { $0 == newCreator }
            } else if let newCreator = createdGroups[gi].memberNames.randomElement() {
                createdGroups[gi].adminName = newCreator
                createdGroups[gi].memberNames.removeAll { $0 == newCreator }
            }
        }
        // Also leave the linked group chat if present
        if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
            leaveConversation(id: conversations[ci].id)
        }
    }

    func deleteConversation(id convID: UUID) {
        conversations.removeAll { $0.id == convID }
    }

    func clearAllData() {
        conversations.removeAll()
        createdGroups.removeAll()
        joinedGroupIDs.removeAll()
        requestedGroupIDs.removeAll()
        announcements.removeAll()
        connections.removeAll()
        joinRequests.removeAll()
        sentConnectionRequests.removeAll()
        receivedConnectionRequests.removeAll()
        notifications.removeAll()
        myListings.removeAll()
        pendingAdminActions.removeAll()
        name        = ""
        bio         = ""
        profileImage = nil
    }

    func deleteKnot(groupID: UUID) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = createdGroups[gi]

        // Send a deletion announcement to all members
        let announcement = Announcement(
            title   : "\(group.name) has been deleted",
            body    : "The knot \"\(group.name)\" has been permanently deleted by the creator. You are no longer a member.",
            sender  : group.name,
            date    : "Just now",
            isRead  : false,
            knotName: group.name
        )
        announcements.insert(announcement, at: 0)

        // Remove the linked group chat entirely
        conversations.removeAll { $0.sourceKnotID == groupID && $0.isGroup }

        // Remove from joined/requested sets
        joinedGroupIDs.remove(groupID)
        requestedGroupIDs.remove(groupID)

        // Remove from createdGroups
        createdGroups.remove(at: gi)
    }

    // MARK: - Knot Member helpers

    func kickMemberFromKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        createdGroups[gi].memberNames.removeAll  { $0 == memberName }
        createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
        // Also remove from the linked group chat participants
        if let ci = conversations.firstIndex(where: { $0.sourceKnotID == groupID && $0.isGroup }) {
            conversations[ci].participants.removeAll { $0 == memberName }
            conversations[ci].adminNames.removeAll   { $0 == memberName }
        }
    }

    func makeCoAdminInKnot(groupID: UUID, memberName: String) {
        guard let gi = createdGroups.firstIndex(where: { $0.id == groupID }) else { return }
        if !createdGroups[gi].coAdminNames.contains(memberName) {
            createdGroups[gi].coAdminNames.append(memberName)
        }
    }

    func openConversation(with targetName: String, sourceKnotID: UUID? = nil, sourceKnotName: String = "") {
        if !conversations.contains(where: { $0.participantName == targetName && !$0.isGroup }) {
            var c = Conversation(participantName: targetName, messages: [])
            c.sourceKnotID   = sourceKnotID
            c.sourceKnotName = sourceKnotName
            conversations.insert(c, at: 0)
        }
        let id = conversations.first { $0.participantName == targetName && !$0.isGroup }?.id
        selectedTab = .messages
        pendingChatConversationID = id
    }
}
