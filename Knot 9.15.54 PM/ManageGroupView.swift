import SwiftUI
import PhotosUI

// MARK: - Manage Group View
struct ManageGroupView: View {
    let groupID: UUID
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    @State private var selectedTab = 0  // 0=Settings, 1=Members, 2=Requests

    private var group: CommunityGroup? {
        profile.createdGroups.first { $0.id == groupID }
    }
    private var isCreator: Bool {
        group?.adminName == profile.name
    }
    private var pendingCount: Int {
        (profile.joinRequests[groupID] ?? []).filter { $0.status == .pending }.count
    }
    private var showRequestsTab: Bool { isCreator }

    var body: some View {
        guard let group else {
            return AnyView(Text("Knot not found").onAppear { dismiss() })
        }
        return AnyView(mainView(group: group))
    }

    @ViewBuilder
    private func mainView(group: CommunityGroup) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                // -- Segmented tab bar
                Picker("", selection: $selectedTab) {
                    Text("Settings").tag(0)
                    Text("Members").tag(1)
                    if showRequestsTab {
                        Text("Requests\(pendingCount > 0 ? " (\(pendingCount))" : "")").tag(2)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                Divider()

                // -- Tab content
                switch selectedTab {
                case 0:  SettingsTab(group: group)
                case 1:  MembersTab(groupID: groupID, isCreator: isCreator)
                default: RequestsTab(groupID: groupID)
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Settings Tab
struct SettingsTab: View {
    let group: CommunityGroup
    @State private var showEdit = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)).frame(width: 60, height: 60)
                        Image(systemName: group.imageName).font(.system(size: 30)).foregroundColor(.black)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).font(.headline)
                        Text(group.category.isEmpty ? "No category" : group.category)
                            .font(.caption).foregroundColor(.gray)
                        Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                            .font(.caption).foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)

                Button(action: { showEdit = true }) {
                    Label("Edit Knot Settings", systemImage: "pencil")
                        .foregroundColor(.black)
                }
            }

            Section("Current Settings") {
                LabeledContent("Type", value: group.isEvent ? "Event" : "Knot")
                LabeledContent("Visibility", value: group.isConnectionsOnly ? "Connections Only" : (group.isPublic ? "Public" : "Private"))
                LabeledContent("Joining", value: group.requiresApproval ? "Requires Approval" : "Open")
                if let max = group.maxMembers {
                    LabeledContent("Max Members", value: "\(max)")
                }
                if !group.location.isEmpty {
                    LabeledContent("Location", value: group.location)
                }
                LabeledContent("Age Group", value: group.ageGroup.rawValue)
                if group.isPaid {
                    LabeledContent("Price", value: group.price == 0 ? "Free" : "$\(group.price)")
                }
            }

            if !group.description.isEmpty {
                Section("Description") {
                    Text(group.description)
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.8))
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            CreateGroupView(existingGroup: group)
        }
    }
}

// MARK: - Members Tab
struct KnotMemberID: Identifiable { let id: String }

struct MembersTab: View {
    let groupID   : UUID
    let isCreator : Bool
    @Environment(UserProfile.self) var profile
    @State private var selectedMember: KnotMemberID? = nil

    private var group: CommunityGroup? {
        profile.createdGroups.first { $0.id == groupID }
    }

    private var sortedMembers: [String] {
        guard let g = group else { return [] }
        let listed = Set([g.adminName] + g.coAdminNames)
        let regularMembers = g.memberNames.filter { !listed.contains($0) }
        return [g.adminName] + g.coAdminNames + regularMembers
    }

    var body: some View {
        guard let g = group else { return AnyView(EmptyView()) }
        return AnyView(memberList(g: g))
    }

    @ViewBuilder
    private func memberList(g: CommunityGroup) -> some View {
        List {
            Section("\(g.memberCount) Members") {
                ForEach(sortedMembers, id: \.self) { member in
                    let isThisCreator = member == g.adminName
                    let isThisAdmin   = g.coAdminNames.contains(member)
                    let isMe          = member == profile.name

                    Button(action: { selectedMember = KnotMemberID(id: member) }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isThisCreator ? Color.black : (isThisAdmin ? Color(.systemGray2) : Color(.systemGray4)))
                                    .frame(width: 38, height: 38)
                                Text(String(member.prefix(1)).uppercased())
                                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isMe ? "\(member) (You)" : member)
                                    .font(.subheadline).foregroundColor(.primary)
                                if isThisCreator {
                                    Text("Creator").font(.caption).foregroundColor(.gray)
                                } else if isThisAdmin {
                                    Text("Admin").font(.caption).foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            if isThisCreator {
                                Image(systemName: "crown.fill").font(.system(size: 12)).foregroundColor(.black)
                            } else if isThisAdmin {
                                Image(systemName: "star.fill").font(.system(size: 12)).foregroundColor(Color(.systemGray2))
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedMember) { m in
            KnotMemberProfileView(memberName: m.id, groupID: groupID, isViewerCreator: isCreator)
                .environment(profile)
        }
    }
}

// MARK: - Knot Member Profile View
struct KnotMemberProfileView: View {
    let memberName     : String
    let groupID        : UUID
    let isViewerCreator: Bool
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    @State private var showProfile             = false
    @State private var showKickConfirm         = false
    @State private var showMakeAdminConfirm    = false
    @State private var showDismissAdminConfirm = false

    private var group: CommunityGroup? {
        profile.createdGroups.first { $0.id == groupID }
    }
    private var isThisCreator: Bool { group?.adminName == memberName }
    private var isThisAdmin  : Bool { group?.coAdminNames.contains(memberName) ?? false }
    private var isMe         : Bool { memberName == profile.name }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile header
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.black).frame(width: 90, height: 90)
                            Text(String(memberName.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .semibold)).foregroundColor(.white)
                        }
                        .padding(.top, 32)

                        Text(isMe ? "\(memberName) (You)" : memberName)
                            .font(.system(size: 22, weight: .bold))

                        if isThisCreator {
                            Label("Knot Creator", systemImage: "crown.fill")
                                .font(.caption).foregroundColor(.orange)
                        } else if isThisAdmin {
                            Label("Knot Admin", systemImage: "star.fill")
                                .font(.caption).foregroundColor(Color(.systemGray))
                        }

                        if profile.connections.contains(memberName) {
                            Label("Connected", systemImage: "person.fill.checkmark")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)

                    // Actions
                    VStack(spacing: 0) {
                        Button(action: { showProfile = true }) {
                            HStack {
                                Label("View Profile", systemImage: "person.crop.circle").foregroundColor(.black)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                            }
                            .padding()
                        }
                        Divider().padding(.leading, 52)
                        Button(action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                profile.openConversation(with: memberName)
                            }
                        }) {
                            HStack {
                                Label("Message", systemImage: "message").foregroundColor(.black)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                            }
                            .padding()
                        }

                        if !isMe {
                            Divider().padding(.leading, 52)
                            if !profile.connections.contains(memberName) && !profile.sentConnectionRequests.contains(memberName) {
                                Button(action: { profile.sendConnectionRequest(to: memberName) }) {
                                    HStack {
                                        Label("Add Connection", systemImage: "person.badge.plus").foregroundColor(.black)
                                        Spacer()
                                    }
                                    .padding()
                                }
                            } else if profile.sentConnectionRequests.contains(memberName) {
                                HStack {
                                    Label("Request Sent", systemImage: "clock").foregroundColor(Color(.systemGray))
                                    Spacer()
                                }
                                .padding()
                            }

                            if !isThisCreator {
                                if isViewerCreator {
                                    Divider().padding(.leading, 52)
                                    if !isThisAdmin {
                                        Button(action: { showMakeAdminConfirm = true }) {
                                            HStack {
                                                Label("Make Admin", systemImage: "star.badge.plus").foregroundColor(.black)
                                                Spacer()
                                            }
                                            .padding()
                                        }
                                    } else {
                                        Button(action: { showDismissAdminConfirm = true }) {
                                            HStack {
                                                Label("Dismiss as Admin", systemImage: "star.slash").foregroundColor(.orange)
                                                Spacer()
                                            }
                                            .padding()
                                        }
                                    }
                                    Divider().padding(.leading, 52)
                                    Button(action: { showKickConfirm = true }) {
                                        HStack {
                                            Label("Kick Out", systemImage: "person.fill.xmark").foregroundColor(.red)
                                            Spacer()
                                        }
                                        .padding()
                                    }
                                } else {
                                    Divider().padding(.leading, 52)
                                    if !isThisAdmin {
                                        Button(action: {
                                            profile.requestAdminAction(groupID: groupID, groupName: group?.name ?? "", requestingAdmin: profile.name, target: memberName, action: .makeAdmin)
                                            dismiss()
                                        }) {
                                            HStack {
                                                Label("Request: Make Admin", systemImage: "star.badge.plus").foregroundColor(.black)
                                                Spacer()
                                            }
                                            .padding()
                                        }
                                    } else {
                                        Button(action: {
                                            profile.requestAdminAction(groupID: groupID, groupName: group?.name ?? "", requestingAdmin: profile.name, target: memberName, action: .dismissAdmin)
                                            dismiss()
                                        }) {
                                            HStack {
                                                Label("Request: Dismiss Admin", systemImage: "star.slash").foregroundColor(.orange)
                                                Spacer()
                                            }
                                            .padding()
                                        }
                                    }
                                    Divider().padding(.leading, 52)
                                    Button(action: {
                                        profile.requestAdminAction(groupID: groupID, groupName: group?.name ?? "", requestingAdmin: profile.name, target: memberName, action: .kick)
                                        dismiss()
                                    }) {
                                        HStack {
                                            Label("Request: Kick Out", systemImage: "person.fill.xmark").foregroundColor(.red)
                                            Spacer()
                                        }
                                        .padding()
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showProfile) {
                UserProfileView(name: memberName).environment(profile)
            }
            .alert("Make \(memberName) an admin?", isPresented: $showMakeAdminConfirm) {
                Button("Make Admin") {
                    profile.makeCoAdminInKnot(groupID: groupID, memberName: memberName)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will become an admin of this Knot.")
            }
            .alert("Dismiss \(memberName) as admin?", isPresented: $showDismissAdminConfirm) {
                Button("Dismiss", role: .destructive) {
                    if let gi = profile.createdGroups.firstIndex(where: { $0.id == groupID }) {
                        profile.createdGroups[gi].coAdminNames.removeAll { $0 == memberName }
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will lose admin powers.")
            }
            .alert("Kick \(memberName) out?", isPresented: $showKickConfirm) {
                Button("Kick Out", role: .destructive) {
                    profile.kickMemberFromKnot(groupID: groupID, memberName: memberName)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will be removed from this Knot.")
            }
        }
    }
}

// MARK: - Requests Tab
struct RequestsTab: View {
    let groupID: UUID
    @Environment(UserProfile.self) var profile
    @State private var selectedRequest: JoinRequest? = nil   // join form detail
    @State private var selectedProfile: JoinRequest? = nil   // profile view
    @State private var filterQuestion: FormQuestion? = nil
    @State private var filterAnswer  = ""


    private var group: CommunityGroup? {
        profile.createdGroups.first { $0.id == groupID }
    }
    // Only show pending — answered requests disappear automatically
    private var pendingRequests: [JoinRequest] {
        (profile.joinRequests[groupID] ?? []).filter { $0.status == .pending }
    }
    private var mcqQuestions: [FormQuestion] {
        group?.joinFormQuestions.filter { $0.type == .mcq } ?? []
    }
    private var filteredRequests: [JoinRequest] {
        guard let q = filterQuestion, !filterAnswer.isEmpty else { return pendingRequests }
        return pendingRequests.filter { $0.answers[q.id] == filterAnswer }
    }


    var body: some View {
        List {
            if !mcqQuestions.isEmpty {
                Section("Filter") {
                    Picker("Question", selection: $filterQuestion) {
                        Text("All requests").tag(Optional<FormQuestion>.none)
                        ForEach(mcqQuestions) { q in
                            Text(q.prompt.isEmpty ? "Question" : q.prompt).tag(Optional(q))
                        }
                    }
                    .onChange(of: filterQuestion) { _, _ in filterAnswer = "" }
                    if let q = filterQuestion {
                        Picker("Answer", selection: $filterAnswer) {
                            Text("Any answer").tag("")
                            ForEach(q.options, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }

            Section {
                if filteredRequests.isEmpty {
                    Text(pendingRequests.isEmpty ? "No pending requests." : "No requests match this filter.")
                        .font(.subheadline).foregroundColor(.gray).padding(.vertical, 4)
                } else {
                    ForEach(filteredRequests) { req in
                        RequestRow(
                            request: req,
                            hasJoinForm: !req.answers.isEmpty
                        ) {
                            selectedProfile = req
                        } onViewForm: {
                            selectedRequest = req
                        } onApprove: {
                            profile.updateRequest(id: req.id, inGroup: groupID, status: .approved)
                        } onReject: {
                            profile.updateRequest(id: req.id, inGroup: groupID, status: .rejected)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Join Requests")
                    if pendingRequests.count > 0 {
                        Text("\(pendingRequests.count) pending")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.black).cornerRadius(8)
                    }
                }
            }
        }
        .sheet(item: $selectedRequest) { req in
            if let g = group {
                RequestDetailView(request: req, group: g)
            }
        }
        .sheet(item: $selectedProfile) { req in
            UserProfileView(name: req.applicantName).environment(profile)
        }


    }


}

// MARK: - Request Row
struct RequestRow: View {
    let request      : JoinRequest
    let hasJoinForm  : Bool
    let onViewProfile: () -> Void
    let onViewForm   : () -> Void
    let onApprove    : () -> Void
    let onReject     : () -> Void

    @State private var showOptions = false

    var body: some View {
        HStack {
            ZStack {
                Circle().fill(Color.black).frame(width: 34, height: 34)
                Text(String(request.applicantName.prefix(1)))
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(request.applicantName).font(.subheadline).fontWeight(.semibold)
                Text(request.submittedAt, style: .date).font(.caption).foregroundColor(.gray)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { showOptions = true }
        Text("Swipe right to approve · left to reject")
            .font(.caption2).foregroundColor(Color(.systemGray3))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onApprove) {
                Label("Approve", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onReject) {
                Label("Reject", systemImage: "xmark")
            }
        }
        .confirmationDialog(request.applicantName, isPresented: $showOptions, titleVisibility: .visible) {
            Button("View Profile") { onViewProfile() }
            if hasJoinForm {
                Button("See Join Form") { onViewForm() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Request Detail View
struct RequestDetailView: View {
    let request : JoinRequest
    let group   : CommunityGroup
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    var body: some View {
        NavigationStack {
            List {
                Section("Applicant") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.black).frame(width: 40, height: 40)
                            Text(String(request.applicantName.prefix(1)))
                                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.applicantName).font(.headline)
                            Text("Applied \(request.submittedAt, style: .date)")
                                .font(.caption).foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !group.joinFormQuestions.isEmpty {
                    Section("Form Answers") {
                        ForEach(group.joinFormQuestions) { question in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.prompt.isEmpty ? "Question" : question.prompt)
                                    .font(.caption).fontWeight(.semibold).foregroundColor(.gray)
                                Text(request.answers[question.id] ?? "No answer provided")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if request.status == .pending {
                    Section {
                        Button(action: {
                            profile.updateRequest(id: request.id, inGroup: group.id, status: .approved)
                            dismiss()
                        }) {
                            Text("Approve").fontWeight(.semibold).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.black).cornerRadius(12)
                        }
                        .listRowInsets(.init()).padding(.horizontal)

                        Button(action: {
                            profile.updateRequest(id: request.id, inGroup: group.id, status: .rejected)
                            dismiss()
                        }) {
                            Text("Reject").fontWeight(.semibold).foregroundColor(.red)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.red.opacity(0.08)).cornerRadius(12)
                        }
                        .listRowInsets(.init()).padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Join Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
