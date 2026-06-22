import SwiftUI
import PhotosUI

// MARK: - Manage Group View
struct ManageGroupView: View {
    let groupID: UUID
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    @State private var selectedTab = 0

    private var group: CommunityGroup? {
        profile.managedKnotSnapshot(groupID)
    }
    private var isCreator: Bool {
        // Compare by UUID so the check survives a profile rename.
        if let cid = group?.creatorID, let me = profile.currentUserID {
            return cid == me
        }
        return group?.adminName == profile.name
    }
    // Creator OR co-admin — full management parity (everything except delete /
    // changing the admin roster, which stay creator-only).
    private var isAdmin: Bool { profile.isKnotAdmin(groupID) }
    private var pendingCount: Int {
        (profile.joinRequests[groupID] ?? []).filter { $0.status == .pending }.count
    }
    private var showRequestsTab: Bool { isAdmin }

    var body: some View {
        Group {
            if let group {
                mainView(group: group)
            } else {
                Text("Knot not found").onAppear { dismiss() }
            }
        }
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
                .background(Color.knotBackground)

                Divider()

                // -- Tab content
                switch selectedTab {
                case 0:  SettingsTab(group: group)
                case 1:  MembersTab(groupID: groupID, isCreator: isCreator, isViewerAdmin: isAdmin)
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

// MARK: - Send Announcement Sheet

struct SendAnnouncementSheet: View {
    private enum Field: Hashable {
        case title
        case message
    }

    let knotID  : UUID
    let knotName: String
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    @State private var title       = ""
    @State private var messageBody = ""
    @State private var isPinned    = false
    @State private var isSending   = false
    @State private var selectedImages: [UIImage] = []
    @State private var showPhotoPicker = false
    @State private var showSendError = false
    @FocusState private var focusedField: Field?

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Announcement") {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)
                    TextField("Message", text: $messageBody, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($focusedField, equals: .message)
                }

                Section("Photos") {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label(
                            selectedImages.isEmpty
                                ? "Add Photos"
                                : "Add or Replace Photos",
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
                    Toggle("Pin this announcement", isOn: $isPinned)
                }
            }
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
            .navigationTitle("New Announcement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        print("🔔 SEND BUTTON TAPPED knotID=\(knotID) title=\(title)")
                        guard !isSending else { return }
                        isSending = true
                        let t   = title.trimmingCharacters(in: .whitespaces)
                        let b   = messageBody.trimmingCharacters(in: .whitespaces)
                        let pin = isPinned
                        let images = selectedImages
                        Task {
                            let didSend = await profile.sendAnnouncement(
                                knotID: knotID,
                                title: t,
                                body: b,
                                isPinned: pin,
                                images: images
                            )
                            await MainActor.run {
                                isSending = false
                                if didSend {
                                    dismiss()
                                } else {
                                    showSendError = true
                                }
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSend || isSending)
                }
            }
            .alert("Couldn’t Send Alert", isPresented: $showSendError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try again in a moment. If you added photos, try sending fewer photos or sending the alert without photos first.")
            }
        }
    }
}

// MARK: - Settings Tab
struct SettingsTab: View {
    let group: CommunityGroup
    @Environment(UserProfile.self) var profile
    @State private var editTarget              : CommunityGroup? = nil
    @State private var showSendAnnouncement    = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.knotSurface).frame(width: 60, height: 60)
                        Image(systemName: group.imageName).font(.system(size: 30)).foregroundColor(.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).font(.headline)
                        Text(group.category.isEmpty ? "No category" : group.category)
                            .font(.caption).foregroundColor(.secondary)
                        Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button(action: { editTarget = group }) {
                    Label("Edit Knot Settings", systemImage: "pencil")
                        .foregroundColor(.primary)
                }
                Button(action: { showSendAnnouncement = true }) {
                    Label("Send Announcement", systemImage: "bell.badge")
                        .foregroundColor(.primary)
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
            }

            if !group.description.isEmpty {
                Section("Description") {
                    Text(group.description)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.85))
                }
            }
        }
        // .sheet(item:) captures the snapshot ONCE when opening — parent re-renders
        // won't pump new `existingGroup` values into CreateGroupView mid-edit, which
        // was killing menu/picker state mid-tap.
        .sheet(item: $editTarget) { snapshot in
            CreateGroupView(existingGroup: snapshot)
        }
        .sheet(isPresented: $showSendAnnouncement) {
            SendAnnouncementSheet(knotID: group.id, knotName: group.name)
                .environment(profile)
        }
    }

}


// MARK: - Members Tab
struct KnotMemberID: Identifiable { let id: String }

struct MembersTab: View {
    let groupID   : UUID
    let isCreator : Bool
    let isViewerAdmin : Bool
    @Environment(UserProfile.self) var profile
    @State private var selectedMember: KnotMemberID? = nil

    private var group: CommunityGroup? {
        profile.managedKnotSnapshot(groupID)
    }

    private var sortedMembers: [String] {
        guard let g = group else { return [] }
        let listed = Set([g.adminName] + g.coAdminNames)
        let regularMembers = g.memberNames.filter { !listed.contains($0) }
        return [g.adminName] + g.coAdminNames + regularMembers
    }

    var body: some View {
        Group {
            if let g = group {
                memberList(g: g).task { await profile.loadKnotMembers(for: groupID) }
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { profile.adminActionError != nil },
            set: { if !$0 { profile.adminActionError = nil } }
        )) {
            Button("OK", role: .cancel) { profile.adminActionError = nil }
        } message: {
            Text(profile.adminActionError ?? "")
        }
    }

    @ViewBuilder
    private func memberList(g: CommunityGroup) -> some View {
        List {
            Section("\(g.memberCount) Members") {
                ForEach(sortedMembers, id: \.self) { member in
                    // UUID-based identity. Names are display only — renaming a user
                    // doesn't change who is admin / creator / "me".
                    let memberID      = g.memberUUIDs[member]
                    let isThisCreator = memberID != nil && memberID == g.creatorID
                    let isThisAdmin   = memberID.map { g.coAdminIDs.contains($0) } ?? false
                    let isMe          = memberID != nil && memberID == profile.currentUserID

                    Button(action: { selectedMember = KnotMemberID(id: member) }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isThisCreator ? Color.knotAccent : (isThisAdmin ? Color.knotMuted : Color.knotSurface))
                                    .frame(width: 38, height: 38)
                                Text(String(member.prefix(1)).uppercased())
                                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isMe ? "\(member) (You)" : member)
                                    .font(.subheadline).foregroundColor(.primary)
                                if isThisCreator {
                                    Text("Creator").font(.caption).foregroundColor(.secondary)
                                } else if isThisAdmin {
                                    Text("Admin").font(.caption).foregroundColor(.secondary)
                                } else if g.isPaid, let uid = memberID,
                                          let lastPaid = g.memberLastPaidAt[uid] {
                                    Text("Last paid \(formatDate(lastPaid))")
                                        .font(.caption).foregroundColor(.secondary)
                                } else if g.isPaid, memberID != nil, !isThisCreator {
                                    Text("Not yet paid")
                                        .font(.caption).foregroundColor(Color(.systemOrange))
                                }
                            }
                            Spacer()
                            if isThisCreator {
                                Image(systemName: "crown.fill").font(.system(size: 12)).foregroundColor(.primary)
                            } else if isThisAdmin {
                                Image(systemName: "star.fill").font(.system(size: 12)).foregroundColor(Color.knotMuted)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color.knotMuted)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedMember) { m in
            KnotMemberProfileView(memberName: m.id, groupID: groupID,
                                  isViewerCreator: isCreator, isViewerAdmin: isViewerAdmin)
                .environment(profile)
        }
    }
}

// MARK: - Knot Member Profile View
struct KnotMemberProfileView: View {
    let memberName     : String
    let groupID        : UUID
    let isViewerCreator: Bool
    var isViewerAdmin  : Bool = false
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    // Single enum drives ALL alerts — avoids the SwiftUI multiple-alert drop bug.
    enum ActiveAlert: Identifiable {
        case confirmMakeAdmin, confirmDismissAdmin, confirmKick
        case error(String)
        var id: String {
            switch self {
            case .confirmMakeAdmin:    return "makeAdmin"
            case .confirmDismissAdmin: return "dismissAdmin"
            case .confirmKick:         return "kick"
            case .error(let m):        return "error-\(m)"
            }
        }
    }

    @State private var showProfile  = false
    @State private var activeAlert  : ActiveAlert? = nil
    @State private var isWorking    = false

    private var group: CommunityGroup? {
        profile.managedKnotSnapshot(groupID)
    }
    /// UUID for the member this view is showing. All identity checks below use this,
    /// not the display name — so a profile rename can never grant or revoke admin power.
    private var memberID: UUID? { group?.memberUUIDs[memberName] }

    /// UUID-based "already connected" check — survives renames and is reliable
    /// immediately after accepting/removing a connection.
    private var isConnectedToMember: Bool {
        guard let me = profile.currentUserID else { return false }
        if let mid = memberID {
            return profile.dbConnections.contains { c in
                c.status == "accepted" &&
                ((c.requesterId == me && c.recipientId == mid) ||
                 (c.requesterId == mid && c.recipientId == me))
            }
        }
        return profile.connections.contains(memberName)
    }

    /// UUID-based "request already sent" check — updates immediately after the
    /// send without waiting for `connectionProfiles` to be hydrated.
    private var isPendingConnectionToMember: Bool {
        guard let me = profile.currentUserID else { return false }
        if let mid = memberID {
            return profile.dbConnections.contains { c in
                c.status == "pending" && c.requesterId == me && c.recipientId == mid
            }
        }
        return profile.sentConnectionRequests.contains(memberName)
    }

    private var isThisCreator: Bool {
        guard let mid = memberID, let cid = group?.creatorID else { return false }
        return mid == cid
    }
    private var isThisAdmin  : Bool {
        guard let mid = memberID else { return false }
        return group?.coAdminIDs.contains(mid) ?? false
    }
    private var isMe         : Bool {
        guard let mid = memberID, let me = profile.currentUserID else { return false }
        return mid == me
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile header
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.knotAccent).frame(width: 90, height: 90)
                            Text(String(memberName.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .semibold)).foregroundColor(Color.knotOnAccent)
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

                        if isConnectedToMember {
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
                                Label("View Profile", systemImage: "person.crop.circle").foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color.knotMuted)
                            }
                            .padding()
                        }
                        Divider().padding(.leading, 52)
                        Button(action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                // memberID is resolved from the knot's memberUUIDs map.
                                // Use it for a reliable open; name fallback as last resort.
                                if let mid = memberID {
                                    profile.openConversation(withUserID: mid, name: memberName)
                                } else {
                                    profile.openConversation(with: memberName)
                                }
                            }
                        }) {
                            HStack {
                                Label("Message", systemImage: "message").foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color.knotMuted)
                            }
                            .padding()
                        }

                        if !isMe {
                            Divider().padding(.leading, 52)
                            if !isConnectedToMember && !isPendingConnectionToMember {
                                Button(action: {
                                    if let mid = memberID {
                                        Task { await profile.sendConnectionRequest(to: mid) }
                                    }
                                }) {
                                    HStack {
                                        Label("Add Connection", systemImage: "person.badge.plus").foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding()
                                }
                            } else if isPendingConnectionToMember {
                                HStack {
                                    Label("Request Sent", systemImage: "clock").foregroundColor(Color.knotMuted)
                                    Spacer()
                                }
                                .padding()
                            }

                            if !isThisCreator {
                                // ── Make / Dismiss Admin — creator only (changing the
                                //    admin roster is an ownership action). Co-admins send
                                //    a request to the creator instead.
                                Divider().padding(.leading, 52)
                                if !isThisAdmin {
                                    Button(action: {
                                        if isViewerCreator {
                                            activeAlert = .confirmMakeAdmin
                                        } else {
                                            profile.requestAdminAction(groupID: groupID, groupName: group?.name ?? "", requestingAdmin: profile.name, target: memberName, action: .makeAdmin)
                                            dismiss()
                                        }
                                    }) {
                                        HStack {
                                            Label(isViewerCreator ? "Make Admin" : "Request: Make Admin", systemImage: "star.circle.fill").foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding()
                                    }
                                } else {
                                    Button(action: {
                                        if isViewerCreator {
                                            activeAlert = .confirmDismissAdmin
                                        } else {
                                            profile.requestAdminAction(groupID: groupID, groupName: group?.name ?? "", requestingAdmin: profile.name, target: memberName, action: .dismissAdmin)
                                            dismiss()
                                        }
                                    }) {
                                        HStack {
                                            Label(isViewerCreator ? "Dismiss as Admin" : "Request: Dismiss Admin", systemImage: "star.slash").foregroundColor(.orange)
                                            Spacer()
                                        }
                                        .padding()
                                    }
                                }

                                // ── Kick — any admin (creator or co-admin) can kick a
                                //    member directly (server RLS allows is_knot_admin).
                                Divider().padding(.leading, 52)
                                Button(action: {
                                    if isViewerAdmin {
                                        activeAlert = .confirmKick
                                    } else {
                                        profile.requestAdminAction(groupID: groupID, groupName: group?.name ?? "", requestingAdmin: profile.name, target: memberName, action: .kick)
                                        dismiss()
                                    }
                                }) {
                                    HStack {
                                        Label(isViewerAdmin ? "Kick Out" : "Request: Kick Out", systemImage: "person.fill.xmark").foregroundColor(.red)
                                        Spacer()
                                    }
                                    .padding()
                                }
                            }
                        }
                    }
                    .background(Color.knotSurface)
                    .cornerRadius(12)
                    // Hairline outline keeps the members card visible in dark mode.
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showProfile) {
                UserProfileView(name: memberName, userID: memberID).environment(profile)
            }
            // ONE alert handles confirmations + errors — no multiple-alert conflicts.
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .confirmMakeAdmin:
                    return Alert(
                        title: Text("Make \(memberName) an admin?"),
                        message: Text("They will become an admin of this Knot."),
                        primaryButton: .default(Text("Make Admin")) {
                            isWorking = true
                            Task {
                                let err = await profile.makeCoAdminInKnotAsync(groupID: groupID, memberName: memberName)
                                isWorking = false
                                if let err { activeAlert = .error(err) } else { dismiss() }
                            }
                        },
                        secondaryButton: .cancel()
                    )
                case .confirmDismissAdmin:
                    return Alert(
                        title: Text("Dismiss \(memberName) as admin?"),
                        message: Text("They will lose admin powers."),
                        primaryButton: .destructive(Text("Dismiss")) {
                            isWorking = true
                            Task {
                                let err = await profile.dismissCoAdminInKnotAsync(groupID: groupID, memberName: memberName)
                                isWorking = false
                                if let err { activeAlert = .error(err) } else { dismiss() }
                            }
                        },
                        secondaryButton: .cancel()
                    )
                case .confirmKick:
                    return Alert(
                        title: Text("Kick \(memberName) out?"),
                        message: Text("They will be removed from this Knot."),
                        primaryButton: .destructive(Text("Kick Out")) {
                            isWorking = true
                            Task {
                                let err = await profile.kickMemberFromKnotAsync(groupID: groupID, memberName: memberName)
                                isWorking = false
                                if let err { activeAlert = .error(err) } else { dismiss() }
                            }
                        },
                        secondaryButton: .cancel()
                    )
                case .error(let message):
                    return Alert(
                        title: Text("Couldn't Complete Action"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .overlay {
                if isWorking {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView().tint(.white).scaleEffect(1.5)
                    }
                }
            }
        }
    }
}

// MARK: - Requests Tab
struct RequestsTab: View {
    let groupID: UUID
    @Environment(UserProfile.self) var profile
    @State private var selectedProfile: JoinRequest? = nil   // profile view


    private var group: CommunityGroup? {
        profile.managedKnotSnapshot(groupID)
    }
    // Only show pending — answered requests disappear automatically
    private var pendingRequests: [JoinRequest] {
        (profile.joinRequests[groupID] ?? []).filter { $0.status == .pending }
    }
    var body: some View {
        List {
            Section {
                if pendingRequests.isEmpty {
                    Text("No pending requests.")
                        .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 4)
                } else {
                    ForEach(pendingRequests) { req in
                        RequestRow(
                            request: req
                        ) {
                            selectedProfile = req
                        } onApprove: {
                            Task {
                                if let dbID = req.dbID, let applicantID = req.applicantID {
                                    await profile.approveJoinRequest(requestID: dbID, knotID: groupID, applicantID: applicantID)
                                } else {
                                    profile.updateRequest(id: req.id, inGroup: groupID, status: .approved)
                                }
                            }
                        } onReject: {
                            Task {
                                if let dbID = req.dbID {
                                    await profile.rejectJoinRequest(requestID: dbID, knotID: groupID)
                                } else {
                                    profile.updateRequest(id: req.id, inGroup: groupID, status: .rejected)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Join Requests")
                    if pendingRequests.count > 0 {
                        Text("\(pendingRequests.count) pending")
                            .font(.caption).fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.knotAccent).cornerRadius(8)
                    }
                }
            }
        }
        .sheet(item: $selectedProfile) { req in
            UserProfileView(name: req.applicantName, userID: req.applicantID).environment(profile)
        }
        .task { await profile.loadJoinRequests(for: groupID) }
    }
}

// MARK: - Request Row
struct RequestRow: View {
    let request      : JoinRequest
    let onViewProfile: () -> Void
    let onApprove    : () -> Void
    let onReject     : () -> Void

    @State private var showOptions = false

    var body: some View {
        HStack {
            ZStack {
                Circle().fill(Color.knotAccent).frame(width: 34, height: 34)
                Text(String(request.applicantName.prefix(1)))
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.knotOnAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(request.applicantName).font(.subheadline).fontWeight(.semibold)
                Text(request.submittedAt, style: .date).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { showOptions = true }
        Text("Swipe right to approve · left to reject")
            .font(.caption2).foregroundColor(Color.knotMuted)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onApprove) {
                Label("Approve", systemImage: "checkmark")
            }
            .tint(Color.knotAccent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onReject) {
                Label("Reject", systemImage: "xmark")
            }
        }
        .confirmationDialog(request.applicantName, isPresented: $showOptions, titleVisibility: .visible) {
            Button("View Profile") { onViewProfile() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
