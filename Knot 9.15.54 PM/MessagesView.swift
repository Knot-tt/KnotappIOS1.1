import SwiftUI
import PhotosUI

// MARK: - Media Viewer Request (used to bundle images + index for fullScreenCover)
struct MediaViewRequest: Identifiable {
    let id         = UUID()
    let images     : [UIImage]
    let startIndex : Int
}

// MARK: - Message Filter
enum MessageFilter: String, CaseIterable {
    case all         = "All Messages"
    case favourites  = "Favourites"
    case connections = "Connections"
}

// MARK: - Read Status
enum ReadStatus { case sent, delivered, read }

// MARK: - Chat Message
struct ChatMessage: Identifiable {
    let id        : UUID     = UUID()
    var text      : String   = ""
    var image     : UIImage? = nil
    let sender    : String
    let timestamp : Date
    var status    : ReadStatus = .sent
    var replyToID : UUID?      = nil
    var isStarred : Bool       = false
    var isSystem  : Bool       = false  // true for system events like "X left the group"
}

// MARK: - Conversation
struct Conversation: Identifiable {
    let id              : UUID     = UUID()
    var participantName : String   = ""   // 1-to-1 chat
    var isGroup         : Bool     = false
    var groupName       : String   = ""
    var participants    : [String] = []   // group members (excluding self)
    var isFavourite     : Bool     = false
    var messages        : [ChatMessage]
    var unreadCount     : Int      = 0
    var sourceKnotID    : UUID?    = nil  // set when started via "Message Knot"
    var sourceKnotName  : String   = ""
    var adminNames      : [String] = []  // group admins (group chats only)
    var creatorName     : String   = ""  // the user who created this chat — cannot be demoted or removed
    var groupImage      : UIImage? = nil // optional group chat profile picture
    var hasLeft         : Bool     = false // true after user leaves — keeps chat visible but read-only

    var displayName: String { isGroup ? groupName : participantName }

    var lastText: String {
        guard let last = messages.last else { return "" }
        let body = last.image != nil && last.text.isEmpty ? "📷 Photo" : last.text
        if isGroup { return "\(last.sender): \(body)" }
        return body
    }
    var lastTimestamp: Date { messages.last?.timestamp ?? Date() }
}

// MARK: - Sample Conversations (TODO: replace with Supabase)
func makeSampleConversations(myName: String) -> [Conversation] {
    [
        Conversation(participantName: "Wei Ming", isFavourite: true, messages: [
            ChatMessage(text: "Hey! See you at the run Sunday?",    sender: "Wei Ming", timestamp: Date().addingTimeInterval(-3600),  status: .read),
            ChatMessage(text: "Definitely! What time?",             sender: myName,     timestamp: Date().addingTimeInterval(-3500),  status: .read),
            ChatMessage(text: "7am at Botanic Gardens entrance 🏃", sender: "Wei Ming", timestamp: Date().addingTimeInterval(-3400),  status: .read),
        ]),
        Conversation(participantName: "Sarah Tan", isFavourite: true, messages: [
            ChatMessage(text: "The recipe was amazing, thank you!", sender: "Sarah Tan", timestamp: Date().addingTimeInterval(-7200), status: .read),
            ChatMessage(text: "So glad you liked it 😊",            sender: myName,     timestamp: Date().addingTimeInterval(-7100), status: .delivered),
        ]),
        Conversation(participantName: "James Lim", messages: [
            ChatMessage(text: "Are you coming to the photography walk?", sender: "James Lim", timestamp: Date().addingTimeInterval(-86400), status: .read),
        ], unreadCount: 1),
        Conversation(participantName: "Priya Nair", messages: [
            ChatMessage(text: "Book club this Saturday at 3pm!",          sender: "Priya Nair", timestamp: Date().addingTimeInterval(-172800), status: .read),
            ChatMessage(text: "Can't wait! Loved this month's book 📚",   sender: myName,       timestamp: Date().addingTimeInterval(-172700), status: .read),
        ]),
        {
            var g = Conversation(isGroup: true, groupName: "Sunday Runners 🏃", participants: ["Wei Ming", "Ahmad Khalid", "Lin Hui"], messages: [
                ChatMessage(text: "Don't forget Sunday morning!",       sender: "Wei Ming",    timestamp: Date().addingTimeInterval(-250000), status: .read),
                ChatMessage(text: "I'll be there 💪",                   sender: myName,        timestamp: Date().addingTimeInterval(-249900), status: .read),
                ChatMessage(text: "Same! See you all at 7am",           sender: "Ahmad Khalid",timestamp: Date().addingTimeInterval(-249800), status: .read),
            ])
            g.adminNames  = ["Wei Ming", myName]  // myName added so you can test admin features
            g.creatorName = "Wei Ming"
            return g
        }(),
        {
            var g = Conversation(isGroup: true, groupName: "📸 Neighbourhood Photography", participants: ["James Lim", "Priya Nair", "Sarah Tan", "Lin Hui"], messages: [
                ChatMessage(text: "Next walk is Saturday at Botanic Gardens 🌿",  sender: "James Lim",  timestamp: Date().addingTimeInterval(-43200),  status: .read),
                ChatMessage(text: "I'll bring my wide-angle lens this time!",     sender: "Priya Nair", timestamp: Date().addingTimeInterval(-43100),  status: .read),
                ChatMessage(text: "Looking forward to it 📷",                     sender: myName,       timestamp: Date().addingTimeInterval(-43000),  status: .read),
                ChatMessage(text: "Anyone know the opening time?",                sender: "Sarah Tan",  timestamp: Date().addingTimeInterval(-3600),   status: .read),
                ChatMessage(text: "Opens at 5am 🌅",                             sender: "Lin Hui",    timestamp: Date().addingTimeInterval(-3500),   status: .read),
            ])
            g.adminNames  = ["James Lim"]
            g.creatorName = "James Lim"
            return g
        }(),
    ]
}

// MARK: - Suggested People (TODO: Supabase neighbour suggestions)
let suggestedPeople = ["Ahmad Khalid", "Lin Hui", "Ravi Kumar", "Mei Ling", "David Chen", "Aisha Patel"]

// MARK: - Messages View
struct MessagesView: View {
    @Environment(UserProfile.self) var profile
    @State private var filter         : MessageFilter  = .all
    @State private var showAddPeople  : Bool           = false
    @State private var searchText     : String         = ""
    @State private var navigationPath : NavigationPath = NavigationPath()

    var displayed: [Conversation] {
        var base: [Conversation]
        switch filter {
        case .all:         base = profile.conversations
        case .favourites:  base = profile.conversations.filter { $0.isFavourite }
        case .connections: base = profile.conversations.filter { profile.connections.contains($0.participantName) }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.participantName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack {
                    Menu {
                        ForEach(MessageFilter.allCases, id: \.self) { f in
                            Button(action: { filter = f }) {
                                if filter == f { Label(f.rawValue, systemImage: "checkmark") }
                                else           { Text(f.rawValue) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Messages")
                                .font(.system(size: 28, weight: .bold)).foregroundColor(.black)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(Color(.systemGray))
                        }
                    }
                    Spacer()
                    Button(action: { showAddPeople = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.black)
                            .padding(8).background(Color(.systemGray6)).clipShape(Circle())
                    }
                }
                .padding(.horizontal).padding(.top, 16).padding(.bottom, 8)

                // Active filter pill
                if filter != .all {
                    HStack {
                        Label(filter.rawValue, systemImage: filterPillIcon)
                            .font(.caption).fontWeight(.medium).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black).cornerRadius(10)
                        Spacer()
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                }

                // ── Search ────────────────────────────────────────────────
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Search", text: $searchText).autocapitalization(.none)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color(.systemGray3))
                        }
                    }
                }
                .padding(10).background(Color(.systemGray6)).cornerRadius(12)
                .padding(.horizontal).padding(.bottom, 8)

                // ── Chat List / Connections Page ──────────────────────────
                if filter == .connections {
                    ConnectionsListView(searchText: searchText)
                } else if displayed.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "message")
                            .font(.system(size: 48)).foregroundColor(Color(.systemGray3))
                        Text(filter == .all ? "No messages yet" : "No \(filter.rawValue.lowercased())")
                            .font(.headline).foregroundColor(Color(.systemGray))
                        if filter == .all {
                            Text("Tap + to find people and start a conversation")
                                .font(.caption).foregroundColor(Color(.systemGray3))
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(displayed) { convo in
                            NavigationLink(value: convo.id) {
                                ConversationRow(conversation: convo, myName: profile.name)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                ChatView(conversationID: id).environment(profile)
            }
            .onChange(of: profile.pendingChatConversationID) { _, id in
                if let id {
                    profile.pendingChatConversationID = nil
                    // Delay so any open sheets finish dismissing before we push
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        navigationPath.append(id)
                    }
                }
            }
            .sheet(isPresented: $showAddPeople) { AddPeopleSheet(isPresented: $showAddPeople).environment(profile) }
        }
    }

    private var filterPillIcon: String {
        switch filter {
        case .all: return "message"; case .favourites: return "star.fill"; case .connections: return "person.2.fill"
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation
    let myName      : String

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let img = conversation.groupImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 50, height: 50).clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(conversation.isGroup ? Color(.systemGray3) : Color.black)
                            .frame(width: 50, height: 50)
                        if conversation.isGroup {
                            Image(systemName: "person.3.fill").font(.system(size: 18)).foregroundColor(.white)
                        } else {
                            Text(String(conversation.participantName.prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if conversation.isFavourite {
                    Image(systemName: "star.fill").font(.system(size: 9))
                        .foregroundColor(.white).padding(2)
                        .background(Color.orange).clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.displayName)
                        .font(.subheadline)
                        .fontWeight(conversation.unreadCount > 0 ? .bold : .semibold)
                        .foregroundColor(.black)
                    Spacer()
                    Text(timeAgo(conversation.lastTimestamp))
                        .font(.caption2).foregroundColor(Color(.systemGray))
                }
                HStack(spacing: 4) {
                    if let last = conversation.messages.last, last.sender == myName {
                        tickView(last.status)
                    }
                    Text(conversation.lastText)
                        .font(.subheadline)
                        .foregroundColor(conversation.unreadCount > 0 ? .black : Color(.systemGray))
                        .lineLimit(1)
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.black).clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func tickView(_ status: ReadStatus) -> some View {
        switch status {
        case .sent:
            Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color(.systemGray3))
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color(.systemGray3))
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color(.systemGray3))
            }
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.blue)
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.blue)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let diff = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: Date())
        if let d = diff.day,    d >= 2  { return "\(d)d" }
        if let d = diff.day,    d == 1  { return "Yesterday" }
        if let h = diff.hour,   h >= 1  { return "\(h)h" }
        if let m = diff.minute, m >= 1  { return "\(m)m" }
        return "Now"
    }
}

// MARK: - Chat View
struct ChatView: View {
    let conversationID : UUID
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var messageText        = ""
    @State private var replyingTo         : ChatMessage? = nil
    @State private var showContactProfile  = false
    @State private var selectedPhotos      : [PhotosPickerItem] = []
    @State private var pendingImages       : [UIImage]          = []
    @State private var mediaViewRequest    : MediaViewRequest? = nil

    private var allMedia: [UIImage] {
        (conversation?.messages.compactMap { $0.image }) ?? []
    }

    private var convoIndex: Int? { profile.conversations.firstIndex { $0.id == conversationID } }
    private var conversation: Conversation? { convoIndex.map { profile.conversations[$0] } }
    private var chatTitle: String { conversation?.displayName ?? "" }
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespaces).isEmpty || !pendingImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Messages ──────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if let convo = conversation {
                            ForEach(convo.messages) { msg in
                                if msg.isSystem {
                                    Text(msg.text)
                                        .font(.caption2)
                                        .foregroundColor(Color(.systemGray))
                                        .frame(maxWidth: .infinity)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 6)
                                } else {
                                MessageBubble(
                                    message: msg,
                                    isMe: msg.sender == profile.name,
                                    replyMessage: msg.replyToID.flatMap { rid in convo.messages.first { $0.id == rid } },
                                    showSenderName: convo.isGroup,
                                    onReply: { replyingTo = msg },
                                    onStar: { toggleStar(msgID: msg.id) },
                                    onImageTap: msg.image != nil ? {
                                        let media = allMedia
                                        let idx   = msg.image.flatMap { img in
                                            media.firstIndex(where: { $0 === img })
                                        } ?? 0
                                        mediaViewRequest = MediaViewRequest(images: media, startIndex: idx)
                                    } : nil
                                )
                                .id(msg.id)
                                } // end else isSystem
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let last = conversation?.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: conversation?.messages.count ?? 0) { _, _ in
                    if let last = conversation?.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // ── Reply Preview ─────────────────────────────────────────────
            if let reply = replyingTo {
                HStack(spacing: 10) {
                    Rectangle().fill(Color.black).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reply.sender == profile.name ? "You" : reply.sender)
                            .font(.caption).fontWeight(.semibold).foregroundColor(.black)
                        Text(reply.image != nil && reply.text.isEmpty ? "📷 Photo" : reply.text)
                            .font(.caption).foregroundColor(.gray).lineLimit(1)
                    }
                    Spacer()
                    Button(action: { replyingTo = nil }) {
                        Image(systemName: "xmark").font(.caption2).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(.systemGray6))
                .overlay(Divider(), alignment: .top)
            }

            // ── Pending Images Preview ────────────────────────────────────
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages.indices, id: \.self) { i in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: pendingImages[i])
                                    .resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button(action: { pendingImages.remove(at: i) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6).clipShape(Circle()))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .background(Color(.systemGray6))
                .overlay(Divider(), alignment: .top)
            }

            // ── Input Bar ─────────────────────────────────────────────────
            if conversation?.hasLeft == true {
                HStack {
                    Spacer()
                    Text("You are not a member of this chat anymore")
                        .font(.subheadline)
                        .foregroundColor(Color(.systemGray))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .overlay(Divider(), alignment: .top)
            } else {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                        Image(systemName: "photo").font(.system(size: 20)).foregroundColor(.black)
                    }
                    .onChange(of: selectedPhotos) { _, items in
                        guard !items.isEmpty else { return }
                        Task {
                            var loaded: [UIImage] = []
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    loaded.append(img)
                                }
                            }
                            await MainActor.run {
                                pendingImages.append(contentsOf: loaded)
                                selectedPhotos = []
                            }
                        }
                    }

                    TextField("Message", text: $messageText, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.systemGray6)).cornerRadius(20)

                    Button(action: { sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(canSend ? .black : Color(.systemGray3))
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white)
                .overlay(Divider(), alignment: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                }
            }
            ToolbarItem(placement: .principal) {
                Button(action: { showContactProfile = true }) {
                    HStack(spacing: 8) {
                        Group {
                            if let img = conversation?.groupImage {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 32, height: 32).clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(conversation?.isGroup == true ? Color(.systemGray3) : Color.black)
                                        .frame(width: 32, height: 32)
                                    if conversation?.isGroup == true {
                                        Image(systemName: "person.3.fill").font(.system(size: 11)).foregroundColor(.white)
                                    } else {
                                        Text(String(chatTitle.prefix(1)).uppercased())
                                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chatTitle).font(.subheadline).fontWeight(.semibold).foregroundColor(.black)
                            Text(conversation?.isGroup == true
                                 ? "\((conversation?.participants.count ?? 0) + 1) members"
                                 : "tap for info")
                                .font(.system(size: 10)).foregroundColor(Color(.systemGray))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showContactProfile) {
            ChatContactProfileView(conversationID: conversationID)
                .environment(profile)
        }
        .fullScreenCover(item: $mediaViewRequest) { req in
            ChatMediaViewer(images: req.images, startIndex: req.startIndex)
        }
    }

    private func sendMessage() {
        guard let ci = convoIndex else { return }
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }

        // Send each image as its own message
        for img in pendingImages {
            profile.conversations[ci].messages.append(
                ChatMessage(text: "", image: img, sender: profile.name,
                            timestamp: Date(), status: .sent, replyToID: replyingTo?.id)
            )
        }
        // Send the text message (if any)
        if !text.isEmpty {
            profile.conversations[ci].messages.append(
                ChatMessage(text: text, image: nil, sender: profile.name,
                            timestamp: Date(), status: .sent, replyToID: replyingTo?.id)
            )
        }
        messageText   = ""
        replyingTo    = nil
        pendingImages = []
    }

    private func toggleStar(msgID: UUID) {
        guard let ci = convoIndex,
              let mi = profile.conversations[ci].messages.firstIndex(where: { $0.id == msgID })
        else { return }
        profile.conversations[ci].messages[mi].isStarred.toggle()
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message       : ChatMessage
    let isMe          : Bool
    let replyMessage  : ChatMessage?
    var showSenderName: Bool = false
    var onReply       : () -> Void
    var onStar        : () -> Void

    @State private var dragOffset : CGFloat = 0
    var onImageTap: (() -> Void)?  = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if isMe { Spacer(minLength: 60) }

            // Reply arrow (revealed by swipe)
            if !isMe && dragOffset > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16)).foregroundColor(Color(.systemGray3))
                    .opacity(Double(min(dragOffset / 50.0, 1.0)))
                    .padding(.trailing, 2)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {

                // Sender name (group chats)
                if showSenderName && !isMe {
                    Text(message.sender)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(Color(.systemGray))
                        .padding(.horizontal, 4)
                }

                // Quoted reply preview
                if let reply = replyMessage {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(isMe ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                            .frame(width: 2)
                        Text(reply.image != nil && reply.text.isEmpty ? "📷 Photo" : reply.text)
                            .font(.caption)
                            .foregroundColor(isMe ? .white.opacity(0.8) : .black.opacity(0.65))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(isMe ? Color.black.opacity(0.12) : Color(.systemGray5))
                    .cornerRadius(8)
                }

                // Bubble content
                if let img = message.image {
                    Button(action: { onImageTap?() }) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundColor(isMe ? .white : .black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMe ? Color.black : Color(.systemGray5))
                        .cornerRadius(18)
                }

                // Timestamp + star + ticks
                HStack(spacing: 4) {
                    if message.isStarred {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(.orange)
                    }
                    Text(timeString(message.timestamp))
                        .font(.system(size: 10)).foregroundColor(Color(.systemGray))
                    if isMe { ticksView(message.status) }
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button(action: onReply) { Label("Reply",  systemImage: "arrowshape.turn.up.left") }
                Button(action: onStar)  { Label(message.isStarred ? "Unstar" : "Star",
                                                systemImage: message.isStarred ? "star.slash" : "star") }
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        if !isMe && v.translation.width > 0 { dragOffset = min(v.translation.width, 70) }
                        if  isMe && v.translation.width < 0 { dragOffset = max(v.translation.width, -70) }
                    }
                    .onEnded { v in
                        if abs(v.translation.width) > 50 { onReply() }
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
            )

            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
    }

    @ViewBuilder
    private func ticksView(_ status: ReadStatus) -> some View {
        switch status {
        case .sent:
            Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color(.systemGray3))
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color(.systemGray3))
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color(.systemGray3))
            }
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.blue)
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.blue)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Chat Contact Profile View
struct ChatContactProfileView: View {
    let conversationID : UUID
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    // Live lookup so the view reacts to mutations (kicks, renames, etc.)
    private var liveConvo: Conversation? {
        profile.conversations.first { $0.id == conversationID }
    }

    @State private var showUserProfile        = false
    @State private var profileName            : String? = nil
    @State private var mediaViewRequest       : MediaViewRequest? = nil
    @State private var selectedKnot           : CommunityGroup?   = nil
    @State private var selectedGroupPhoto     : PhotosPickerItem? = nil

    // Member management
    @State private var memberProfileTarget      : String? = nil  // tapped member — shows profile sheet
    @State private var showLeaveConfirm         = false
    @State private var showDeleteConfirm        = false
    @State private var showRenameAlert          = false
    @State private var renameText               = ""

    // Creator or admin — has management powers
    private var amIPrivileged: Bool {
        guard let convo = liveConvo else { return false }
        return convo.creatorName == profile.name || convo.adminNames.contains(profile.name)
    }

    private var sortedMembers: [String] {
        guard let convo = liveConvo, convo.isGroup else { return [] }
        let creator   = convo.creatorName
        let admins    = convo.adminNames
        let base      = convo.hasLeft ? convo.participants : ([profile.name] + convo.participants)
        let allPeople = base
        return allPeople.sorted { a, b in
            let aCreator = a == creator
            let bCreator = b == creator
            if aCreator != bCreator { return aCreator }
            let aAdmin = admins.contains(a)
            let bAdmin = admins.contains(b)
            if aAdmin != bAdmin { return aAdmin }
            return a < b
        }
    }

    private var knotsInCommon: [CommunityGroup] {
        guard let convo = liveConvo, !convo.isGroup else { return [] }
        return (sampleGroups + profile.createdGroups).filter { $0.adminName == convo.participantName }
    }

    private var canAddToKnotGroupChat: Bool {
        guard let convo = liveConvo, !convo.isGroup, let knotID = convo.sourceKnotID else { return false }
        return (sampleGroups + profile.createdGroups).contains {
            $0.id == knotID && $0.adminName == profile.name
        }
    }

    @ViewBuilder
    private func avatarHeader(convo: Conversation) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = convo.groupImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 80, height: 80).clipShape(Circle())
            } else if convo.isGroup {
                ZStack {
                    Circle().fill(Color(.systemGray3)).frame(width: 80, height: 80)
                    Image(systemName: "person.3.fill").font(.system(size: 32)).foregroundColor(.white)
                }
            } else {
                ZStack {
                    Circle().fill(Color.black).frame(width: 80, height: 80)
                    Text(String(convo.participantName.prefix(1)).uppercased())
                        .font(.system(size: 32, weight: .semibold)).foregroundColor(.white)
                }
            }
            if convo.isGroup && amIPrivileged {
                PhotosPicker(selection: $selectedGroupPhoto, matching: .images) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.black)
                        .background(Color.white.clipShape(Circle()))
                }
            }
        }
        .onChange(of: selectedGroupPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img  = UIImage(data: data) {
                    await MainActor.run {
                        profile.updateConversationImage(id: conversationID, image: img)
                        selectedGroupPhoto = nil
                    }
                }
            }
        }
    }

    var body: some View {
        guard let convo = liveConvo else {
            return AnyView(Text("Conversation not found").onAppear { dismiss() })
        }
        return AnyView(bodyView(convo: convo))
    }

    @ViewBuilder
    private func bodyView(convo: Conversation) -> some View {
        let starred : [ChatMessage] = convo.messages.filter { $0.isStarred }
        let images  : [UIImage]     = convo.messages.compactMap { $0.image }

        NavigationStack {
            List {

                // ── Header ────────────────────────────────────────────────
                Section {
                    VStack(spacing: 10) {
                        avatarHeader(convo: convo)

                        // Group name — admin or creator can rename
                        if convo.isGroup && amIPrivileged {
                            HStack(spacing: 6) {
                                Text(convo.displayName).font(.system(size: 20, weight: .bold))
                                Button(action: {
                                    renameText = convo.groupName
                                    showRenameAlert = true
                                }) {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 18)).foregroundColor(.gray)
                                }
                            }
                        } else {
                            Text(convo.displayName).font(.system(size: 20, weight: .bold))
                        }

                        if convo.isGroup {
                            Text("\(convo.participants.count + 1) members")
                                .font(.caption).foregroundColor(.gray)
                        } else {
                            Text(profile.connections.contains(convo.participantName) ? "Connected" : "Not connected")
                                .font(.caption)
                                .foregroundColor(profile.connections.contains(convo.participantName) ? .green : .gray)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                // ── Group Members (sorted: admins first) ──────────────────
                if convo.isGroup {
                    Section("Members") {
                        ForEach(sortedMembers, id: \.self) { member in
                            let isThisCreator = member == convo.creatorName
                            let isThisAdmin   = convo.adminNames.contains(member)
                            let isMe          = member == profile.name
                            let avatarColor: Color = isThisCreator ? .black : (isThisAdmin ? Color(.systemGray2) : Color(.systemGray3))
                            Button(action: {
                                guard !isMe else { return }
                                memberProfileTarget = member
                            }) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(avatarColor)
                                            .frame(width: 36, height: 36)
                                        Text(String(member.prefix(1)).uppercased())
                                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(isMe ? "\(member) (You)" : member)
                                            .font(.subheadline).foregroundColor(.black)
                                        if isThisCreator {
                                            Text("Creator")
                                                .font(.system(size: 10)).foregroundColor(Color(.systemGray))
                                        } else if isThisAdmin {
                                            Text("Admin")
                                                .font(.system(size: 10)).foregroundColor(Color(.systemGray))
                                        }
                                    }
                                    Spacer()
                                    if isThisCreator {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 11)).foregroundColor(.black)
                                    } else if isThisAdmin {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11)).foregroundColor(Color(.systemGray2))
                                    }
                                    if !isMe {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundColor(Color(.systemGray3))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isMe)
                        }
                    }
                }

                // ── Shared Media ──────────────────────────────────────────
                if !images.isEmpty {
                    Section("Media") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(images.indices, id: \.self) { i in
                                    Button(action: {
                                        mediaViewRequest = MediaViewRequest(images: images, startIndex: i)
                                    }) {
                                        Image(uiImage: images[i])
                                            .resizable().scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }

                // ── Starred Messages ──────────────────────────────────────
                if !starred.isEmpty {
                    Section("Starred Messages") {
                        ForEach(starred) { msg in
                            HStack(spacing: 10) {
                                Image(systemName: "star.fill").font(.caption).foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(msg.sender == profile.name ? "You" : msg.sender)
                                        .font(.caption).fontWeight(.semibold).foregroundColor(.gray)
                                    Text(msg.image != nil && msg.text.isEmpty ? "📷 Photo" : msg.text)
                                        .font(.subheadline).lineLimit(2)
                                }
                            }
                        }
                    }
                }

                // ── Knots in Common (1:1 only) ────────────────────────────
                if !convo.isGroup && !knotsInCommon.isEmpty {
                    Section("Knots in Common") {
                        ForEach(knotsInCommon) { knot in
                            Button(action: { selectedKnot = knot }) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5)).frame(width: 36, height: 36)
                                        Image(systemName: knot.imageName).font(.system(size: 16)).foregroundColor(.black)
                                    }
                                    Text(knot.name).font(.subheadline).foregroundColor(.black)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // ── Actions ───────────────────────────────────────────────
                Section {
                    if !convo.isGroup {
                        Button(action: { profileName = convo.participantName }) {
                            Label("View Profile", systemImage: "person.circle").foregroundColor(.black)
                        }
                    }
                    if canAddToKnotGroupChat {
                        Button(action: { addToKnotGroupChat(convo: convo) }) {
                            Label("Add to \(convo.sourceKnotName) Knot Chat",
                                  systemImage: "person.badge.plus").foregroundColor(.black)
                        }
                    }
                    if convo.isGroup {
                        if convo.hasLeft {
                            Button(role: .destructive, action: { showDeleteConfirm = true }) {
                                Label("Delete Chat", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive, action: { showLeaveConfirm = true }) {
                                Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    } else {
                        Button(role: .destructive, action: {}) {
                            Label("Block \(convo.participantName)", systemImage: "hand.raised.fill")
                        }
                        Button(role: .destructive, action: { showDeleteConfirm = true }) {
                            Label("Delete Chat", systemImage: "trash")
                        }
                    }
                }
            }

            .navigationTitle(convo.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }

            // ── Leave confirmation ────────────────────────────────────────
            .alert("Leave Group?", isPresented: $showLeaveConfirm) {
                Button("Leave", role: .destructive) {
                    profile.leaveConversation(id: conversationID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if convo.sourceKnotID != nil {
                    Text("You will also be removed from the \(convo.sourceKnotName) Knot.")
                } else {
                    Text("You will no longer have access to this group chat.")
                }
            }
            // ── Delete confirmation ───────────────────────────────────────
            .alert("Delete Chat?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    profile.deleteConversation(id: conversationID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This chat will be removed from your messages. This cannot be undone.")
            }

            // ── Rename alert ──────────────────────────────────────────────
            .alert("Rename Group", isPresented: $showRenameAlert) {
                TextField("Group name", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        profile.renameConversation(id: conversationID, to: trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            .sheet(item: $profileName) { name in
                UserProfileView(name: name).environment(profile)
            }
            .sheet(item: $memberProfileTarget) { name in
                GroupMemberProfileView(name: name, conversationID: conversationID)
                    .environment(profile)
            }
            .sheet(item: $selectedKnot) { knot in
                KnotDetailView(group: knot).environment(profile)
            }
            .fullScreenCover(item: $mediaViewRequest) { req in
                ChatMediaViewer(images: req.images, startIndex: req.startIndex)
            }
        }
    }

    private func addToKnotGroupChat(convo: Conversation) {
        guard let knotID = convo.sourceKnotID else { return }
        let person = convo.participantName
        if let idx = profile.conversations.firstIndex(where: { $0.isGroup && $0.sourceKnotID == knotID }) {
            if !profile.conversations[idx].participants.contains(person) {
                profile.conversations[idx].participants.append(person)
            }
            profile.pendingChatConversationID = profile.conversations[idx].id
        } else {
            var g = Conversation(
                isGroup: true, groupName: "\(convo.sourceKnotName) Chat",
                participants: [person], messages: [],
                sourceKnotID: knotID, sourceKnotName: convo.sourceKnotName
            )
            g.adminNames  = [profile.name]
            g.creatorName = profile.name
            profile.conversations.insert(g, at: 0)
            profile.pendingChatConversationID = g.id
        }
        dismiss()
    }
}

// MARK: - Add People Sheet
struct AddPeopleSheet: View {
    @Binding var isPresented: Bool
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var searchText          = ""
    @State private var selectedPerson      : String? = nil
    @State private var showCreateGroupChat = false

    var results: [String] {
        guard !searchText.isEmpty else { return suggestedPeople }
        return suggestedPeople.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Search by name", text: $searchText).autocapitalization(.none)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color(.systemGray3))
                        }
                    }
                }
                .listRowBackground(Color(.systemGray6))

                Section {
                    Button(action: { showCreateGroupChat = true }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color(.systemGray3)).frame(width: 40, height: 40)
                                Image(systemName: "person.3.fill").font(.system(size: 16)).foregroundColor(.white)
                            }
                            Text("New Knot Chat").font(.subheadline).fontWeight(.semibold).foregroundColor(.black)
                        }
                    }
                }

                Section("Suggested People") {
                    ForEach(results, id: \.self) { name in
                        Button(action: { selectedPerson = name }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.black).frame(width: 40, height: 40)
                                    Text(String(name.prefix(1)).uppercased())
                                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name).font(.subheadline).fontWeight(.semibold).foregroundColor(.black)
                                    if profile.connections.contains(name) {
                                        Text("Connected").font(.caption).foregroundColor(.green)
                                    } else if profile.sentConnectionRequests.contains(name) {
                                        Text("Request sent").font(.caption).foregroundColor(.gray)
                                    } else {
                                        Text("People you may know").font(.caption).foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                if profile.connections.contains(name) {
                                    Image(systemName: "person.fill.checkmark").foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: $selectedPerson) { name in
                UserProfileView(name: name).environment(profile)
            }
            .sheet(isPresented: $showCreateGroupChat) {
                CreateGroupChatView().environment(profile)
            }
            // Close this sheet the moment any chat is queued to open
            .onChange(of: profile.pendingChatConversationID) { _, id in
                if id != nil { isPresented = false }
            }
        }
    }
}

// MARK: - Create Group Chat View
struct CreateGroupChatView: View {
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var groupName            = ""
    @State private var selectedParticipants : Set<String> = []
    @State private var groupImage           : UIImage?    = nil
    @State private var selectedPhoto        : PhotosPickerItem? = nil

    private var allPeople: [String] {
        let known = Array(Set(suggestedPeople + profile.connections))
        return known.sorted()
    }
    private var canCreate: Bool { !groupName.trimmingCharacters(in: .whitespaces).isEmpty && selectedParticipants.count >= 1 }

    var body: some View {
        NavigationStack {
            List {
                // ── Group photo + name ─────────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let img = groupImage {
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(width: 60, height: 60).clipShape(Circle())
                                    } else {
                                        ZStack {
                                            Circle().fill(Color(.systemGray4)).frame(width: 60, height: 60)
                                            Image(systemName: "person.3.fill")
                                                .font(.system(size: 22)).foregroundColor(.white)
                                        }
                                    }
                                }
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.black)
                                    .background(Color.white.clipShape(Circle()))
                            }
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            guard let item else { return }
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let img  = UIImage(data: data) {
                                    await MainActor.run { groupImage = img; selectedPhoto = nil }
                                }
                            }
                        }

                        TextField("e.g. Book Club Chat", text: $groupName)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }

                Section("Add Participants") {
                    ForEach(allPeople, id: \.self) { name in
                        Button(action: {
                            if selectedParticipants.contains(name) { selectedParticipants.remove(name) }
                            else { selectedParticipants.insert(name) }
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.black).frame(width: 36, height: 36)
                                    Text(String(name.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                }
                                Text(name).font(.subheadline).foregroundColor(.black)
                                Spacer()
                                if selectedParticipants.contains(name) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.black)
                                } else {
                                    Image(systemName: "circle").foregroundColor(Color(.systemGray3))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Knot Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createGroup() }
                        .fontWeight(.semibold).disabled(!canCreate)
                }
            }
        }
    }

    private func createGroup() {
        var g = Conversation(
            isGroup: true,
            groupName: groupName.trimmingCharacters(in: .whitespaces),
            participants: Array(selectedParticipants),
            messages: []
        )
        g.adminNames  = [profile.name]
        g.creatorName = profile.name
        g.groupImage  = groupImage
        profile.conversations.insert(g, at: 0)
        profile.pendingChatConversationID = g.id
        dismiss()
    }
}

// MARK: - Chat Media Viewer
struct ChatMediaViewer: View {
    let images     : [UIImage]
    let startIndex : Int
    @State private var currentIndex: Int
    @Environment(\.dismiss) var dismiss

    init(images: [UIImage], startIndex: Int) {
        self.images     = images
        self.startIndex = startIndex
        _currentIndex   = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { i in
                    Image(uiImage: images[i])
                        .resizable()
                        .scaledToFit()
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    Spacer()
                    if images.count > 1 {
                        Text("\(currentIndex + 1) / \(images.count)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }
        }
    }
}

// MARK: - Connections List (shown when Connections filter is active)
struct ConnectionsListView: View {
    @Environment(UserProfile.self) var profile
    let searchText: String

    var filtered: [String] {
        if searchText.isEmpty { return profile.connections }
        return profile.connections.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        if filtered.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 48)).foregroundColor(Color(.systemGray3))
                Text(profile.connections.isEmpty ? "No connections yet" : "No results")
                    .font(.headline).foregroundColor(Color(.systemGray))
                if profile.connections.isEmpty {
                    Text("Accept connection requests to see people here")
                        .font(.caption).foregroundColor(Color(.systemGray3))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(filtered, id: \.self) { name in
                    ConnectionPersonRow(name: name)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Connection Person Row
struct ConnectionPersonRow: View {
    @Environment(UserProfile.self) var profile
    let name: String

    private var conversation: Conversation? {
        profile.conversations.first { $0.participantName == name && !$0.isGroup }
    }

    var body: some View {
        if let convo = conversation {
            NavigationLink(value: convo.id) {
                ConversationRow(conversation: convo, myName: profile.name)
            }
        } else {
            Button(action: { profile.openConversation(with: name) }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.black).frame(width: 50, height: 50)
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.black)
                        Text("Tap to message")
                            .font(.subheadline).foregroundColor(Color(.systemGray))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Group Member Profile View (shown when tapping a member in a group chat)
struct GroupMemberProfileView: View {
    let name           : String
    let conversationID : UUID
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var showProfile             = false
    @State private var showKickConfirm        = false
    @State private var showMakeAdminConfirm   = false
    @State private var showDemoteAdminConfirm = false

    private var convo: Conversation? { profile.conversations.first { $0.id == conversationID } }
    private var isThisCreator: Bool { convo?.creatorName == name }
    private var isThisAdmin  : Bool { convo?.adminNames.contains(name) ?? false }
    private var amIPrivileged: Bool {
        guard let c = convo else { return false }
        return c.creatorName == profile.name || c.adminNames.contains(profile.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Profile header ────────────────────────────────────
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.black).frame(width: 90, height: 90)
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .semibold)).foregroundColor(.white)
                        }
                        .padding(.top, 32)

                        Text(name).font(.system(size: 22, weight: .bold))

                        if isThisCreator {
                            Label("Group Creator", systemImage: "crown.fill")
                                .font(.caption).foregroundColor(.orange)
                        } else if isThisAdmin {
                            Label("Group Admin", systemImage: "star.fill")
                                .font(.caption).foregroundColor(Color(.systemGray))
                        }

                        if profile.connections.contains(name) {
                            Label("Connected", systemImage: "person.fill.checkmark")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)

                    // ── Actions ───────────────────────────────────────────
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
                                profile.openConversation(with: name)
                            }
                        }) {
                            HStack {
                                Label("Message", systemImage: "message").foregroundColor(.black)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                            }
                            .padding()
                        }
                        Divider().padding(.leading, 52)

                        if !profile.connections.contains(name) && !profile.sentConnectionRequests.contains(name) {
                            Button(action: {
                                profile.sendConnectionRequest(to: name)
                            }) {
                                HStack {
                                    Label("Add Connection", systemImage: "person.badge.plus").foregroundColor(.black)
                                    Spacer()
                                }
                                .padding()
                            }
                            Divider().padding(.leading, 52)
                        } else if profile.sentConnectionRequests.contains(name) {
                            HStack {
                                Label("Request Sent", systemImage: "clock").foregroundColor(Color(.systemGray))
                                Spacer()
                            }
                            .padding()
                            Divider().padding(.leading, 52)
                        }

                        if amIPrivileged && !isThisCreator {
                            if !isThisAdmin {
                                Button(action: { showMakeAdminConfirm = true }) {
                                    HStack {
                                        Label("Make Admin", systemImage: "star.badge.plus").foregroundColor(.black)
                                        Spacer()
                                    }
                                    .padding()
                                }
                            } else {
                                Button(action: { showDemoteAdminConfirm = true }) {
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
                UserProfileView(name: name).environment(profile)
            }
            .alert("Make \(name) an admin?", isPresented: $showMakeAdminConfirm) {
                Button("Make Admin") {
                    profile.makeAdminInConversation(id: conversationID, memberName: name)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will be able to manage members of this group.")
            }
            .alert("Remove \(name) as admin?", isPresented: $showDemoteAdminConfirm) {
                Button("Remove Admin", role: .destructive) {
                    profile.demoteAdminInConversation(id: conversationID, memberName: name)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will become a regular member and lose admin powers.")
            }
            .alert("Kick \(name) out?", isPresented: $showKickConfirm) {
                Button("Kick Out", role: .destructive) {
                    profile.kickFromConversation(id: conversationID, memberName: name)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will be removed from this group chat.")
            }
        }
    }
}

#Preview {
    MessagesView().environment(UserProfile(name: "Ruhaan"))
}
