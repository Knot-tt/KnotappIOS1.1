import SwiftUI
import Supabase
import Auth

// MARK: - Media Source (local UIImage or remote URL string)
enum MediaSource: Equatable, Hashable {
    case local(UIImage)
    case remote(String)
    case video(poster: String, video: String)   // poster image URL + playable video URL
}

// MARK: - Media Viewer Request (used to bundle images + index for fullScreenCover)
struct MediaViewRequest: Identifiable {
    let id         = UUID()
    let sources    : [MediaSource]
    let startIndex : Int
}

struct VideoViewRequest: Identifiable {
    let id = UUID()
    let url: URL
}

private enum ChatRenderItem: Identifiable {
    case single(message: ChatMessage, index: Int)
    case imageGroup(messages: [ChatMessage], startIndex: Int)

    var id: UUID {
        switch self {
        case .single(let message, _):
            return message.id
        case .imageGroup(let messages, _):
            return messages.first?.id ?? UUID()
        }
    }

    var anchorMessage: ChatMessage {
        switch self {
        case .single(let message, _):
            return message
        case .imageGroup(let messages, _):
            return messages[0]
        }
    }

    var anchorIndex: Int {
        switch self {
        case .single(_, let index):
            return index
        case .imageGroup(_, let startIndex):
            return startIndex
        }
    }
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
    var id        : UUID     = UUID()   // var so DB UUID can be assigned on load
    var text      : String   = ""
    var image     : UIImage? = nil      // local/optimistic image (pre-upload)
    var imageURL  : String?  = nil      // public URL once persisted to Supabase Storage
    var videoURL  : String?  = nil      // public URL of a video clip (imageURL = poster frame)
    let sender    : String        // DISPLAY ONLY — derived from senderID at render time
    let senderID  : UUID?         // IDENTITY — used for "is this me?" so renames don't break attribution
    let timestamp : Date
    var status    : ReadStatus = .sent
    var replyToID : UUID?      = nil
    var isStarred : Bool       = false
    var isSystem  : Bool       = false  // true for system events like "X left the group"
    var listingContext: ListingMessageContext? = nil

    var hasImage: Bool { image != nil || imageURL != nil }
    var hasVideo: Bool { videoURL != nil }
}

struct ListingMessageContext: Equatable {
    let listingID: UUID
    let listingName: String
}

let listingContextPrefix = "__knot_listing_context__:"

func makeListingContextMessageText(listingID: UUID, listingName: String, body: String) -> String {
    let escapedName = listingName
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "|", with: "\\|")
    return "\(listingContextPrefix)\(listingID.uuidString.lowercased())|\(escapedName)\n\(body)"
}

func parseListingContextMessage(_ text: String) -> (context: ListingMessageContext, body: String)? {
    guard text.hasPrefix(listingContextPrefix) else { return nil }
    let payload = String(text.dropFirst(listingContextPrefix.count))
    guard let separatorIndex = payload.firstIndex(of: "|") else { return nil }
    let idPart = String(payload[..<separatorIndex])
    let remainder = String(payload[payload.index(after: separatorIndex)...])
    let namePart: String
    let body: String
    if let newlineIndex = remainder.firstIndex(of: "\n") {
        namePart = String(remainder[..<newlineIndex])
        body = String(remainder[remainder.index(after: newlineIndex)...])
    } else {
        namePart = remainder
        body = ""
    }
    let unescapedName = namePart
        .replacingOccurrences(of: "\\|", with: "|")
        .replacingOccurrences(of: "\\\\", with: "\\")
    guard let listingID = UUID(uuidString: idPart) else { return nil }
    return (
        context: ListingMessageContext(listingID: listingID, listingName: unescapedName),
        body: body
    )
}

// MARK: - Conversation
struct Conversation: Identifiable {
    var id              : UUID     = UUID()   // var so DB UUID can be assigned on load
    var participantName : String   = ""   // 1-to-1 chat — DISPLAY ONLY
    var participantID   : UUID?    = nil  // 1-to-1 chat — IDENTITY (used for all checks)
    var isGroup         : Bool     = false
    var groupName       : String   = ""
    var groupDescription: String   = ""   // group chat description (group chats only)
    var groupImageURL   : String?  = nil  // persisted group photo URL (hydrates groupImage display)
    var participants    : [String] = []   // group members (excluding self) — DISPLAY ONLY
    var memberIDsByName : [String: UUID] = [:]  // name → UUID lookup for member rows
    var isFavourite     : Bool     = false
    var messages        : [ChatMessage] = []
    var unreadCount     : Int      = 0
    var sourceKnotID    : UUID?    = nil  // set when started via "Message Knot"
    var sourceKnotName  : String   = ""
    var adminNames      : [String] = []  // group admins (group chats only) — DISPLAY ONLY
    var adminIDs        : Set<UUID> = []  // group admins — IDENTITY (used for privilege checks)
    var creatorName     : String   = ""  // creator display name — DISPLAY ONLY
    var creatorID       : UUID?    = nil // creator IDENTITY — survives renames, prevents impersonation
    var groupImage      : UIImage? = nil // optional group chat profile picture
    var hasLeft         : Bool     = false // true after user leaves — keeps chat visible but read-only
    /// Sourced from the DB `conversations.updated_at` on load, then bumped locally when
    /// a message is sent/received. Used for sorting so new chats rise to the top even
    /// before `loadMessages()` has been called (avoids the `Date()` fallback problem).
    var lastActivityAt  : Date     = .distantPast
    var pendingListingContext: ListingMessageContext? = nil

    var displayName: String { isGroup ? groupName : participantName }
    var latestMessage: ChatMessage? {
        messages.max { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    var lastText: String {
        guard let last = latestMessage else { return "" }
        let body = last.hasImage && last.text.isEmpty ? "📷 Photo" : last.text
        if isGroup { return "\(last.sender): \(body)" }
        return body
    }
    /// Use the later of the DB-sourced activity timestamp or the newest loaded message.
    var lastTimestamp: Date {
        let msgTime = latestMessage?.timestamp ?? .distantPast
        return max(lastActivityAt, msgTime)
    }
}

// MARK: - Sample Conversations (TODO: replace with Supabase)
func makeSampleConversations(myName: String) -> [Conversation] {
    [
        Conversation(participantName: "Wei Ming", isFavourite: true, messages: [
            ChatMessage(text: "Hey! See you at the run Sunday?",    sender: "Wei Ming", senderID: nil, timestamp: Date().addingTimeInterval(-3600),  status: .read),
            ChatMessage(text: "Definitely! What time?",             sender: myName, senderID: nil,     timestamp: Date().addingTimeInterval(-3500),  status: .read),
            ChatMessage(text: "7am at Botanic Gardens entrance 🏃", sender: "Wei Ming", senderID: nil, timestamp: Date().addingTimeInterval(-3400),  status: .read),
        ]),
        Conversation(participantName: "Sarah Tan", isFavourite: true, messages: [
            ChatMessage(text: "The recipe was amazing, thank you!", sender: "Sarah Tan", senderID: nil, timestamp: Date().addingTimeInterval(-7200), status: .read),
            ChatMessage(text: "So glad you liked it 😊",            sender: myName, senderID: nil,     timestamp: Date().addingTimeInterval(-7100), status: .delivered),
        ]),
        Conversation(participantName: "James Lim", messages: [
            ChatMessage(text: "Are you coming to the photography walk?", sender: "James Lim", senderID: nil, timestamp: Date().addingTimeInterval(-86400), status: .read),
        ], unreadCount: 1),
        Conversation(participantName: "Priya Nair", messages: [
            ChatMessage(text: "Book club this Saturday at 3pm!",          sender: "Priya Nair", senderID: nil, timestamp: Date().addingTimeInterval(-172800), status: .read),
            ChatMessage(text: "Can't wait! Loved this month's book 📚",   sender: myName, senderID: nil,       timestamp: Date().addingTimeInterval(-172700), status: .read),
        ]),
        {
            var g = Conversation(isGroup: true, groupName: "Sunday Runners 🏃", participants: ["Wei Ming", "Ahmad Khalid", "Lin Hui"], messages: [
                ChatMessage(text: "Don't forget Sunday morning!",       sender: "Wei Ming", senderID: nil,    timestamp: Date().addingTimeInterval(-250000), status: .read),
                ChatMessage(text: "I'll be there 💪",                   sender: myName, senderID: nil,        timestamp: Date().addingTimeInterval(-249900), status: .read),
                ChatMessage(text: "Same! See you all at 7am",           sender: "Ahmad Khalid", senderID: nil,timestamp: Date().addingTimeInterval(-249800), status: .read),
            ])
            g.adminNames  = ["Wei Ming", myName]  // myName added so you can test admin features
            g.creatorName = "Wei Ming"
            return g
        }(),
        {
            var g = Conversation(isGroup: true, groupName: "📸 Neighbourhood Photography", participants: ["James Lim", "Priya Nair", "Sarah Tan", "Lin Hui"], messages: [
                ChatMessage(text: "Next walk is Saturday at Botanic Gardens 🌿",  sender: "James Lim", senderID: nil,  timestamp: Date().addingTimeInterval(-43200),  status: .read),
                ChatMessage(text: "I'll bring my wide-angle lens this time!",     sender: "Priya Nair", senderID: nil, timestamp: Date().addingTimeInterval(-43100),  status: .read),
                ChatMessage(text: "Looking forward to it 📷",                     sender: myName, senderID: nil,       timestamp: Date().addingTimeInterval(-43000),  status: .read),
                ChatMessage(text: "Anyone know the opening time?",                sender: "Sarah Tan", senderID: nil,  timestamp: Date().addingTimeInterval(-3600),   status: .read),
                ChatMessage(text: "Opens at 5am 🌅",                             sender: "Lin Hui", senderID: nil,    timestamp: Date().addingTimeInterval(-3500),   status: .read),
            ])
            g.adminNames  = ["James Lim"]
            g.creatorName = "James Lim"
            return g
        }(),
    ]
}

// MARK: - Suggested People
// No mock list — "Add People" sheets and search use real connection + conversation
// data only. People discovery happens via ProfileService.search() against Supabase.
let suggestedPeople: [String] = []

// MARK: - Messages View
struct MessagesView: View {
    @Environment(UserProfile.self) var profile
    @State private var filter         : MessageFilter  = .all
    @State private var showAddPeople  : Bool           = false
    @State private var searchText     : String         = ""
    @State private var navigationPath : NavigationPath = NavigationPath()
    @FocusState private var isSearchFocused: Bool

    var displayed: [Conversation] {
        var base: [Conversation]
        switch filter {
        case .all:         base = profile.conversations
        case .favourites:  base = profile.conversations.filter { $0.isFavourite }
        case .connections: base = profile.conversations.filter { profile.connections.contains($0.participantName) }
        }
        if !searchText.isEmpty {
            base = base.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
        // Purely chronological — newest activity first. An unread message does NOT
        // bump a conversation up; ordering is determined only by last activity time.
        return base.sorted { $0.lastTimestamp > $1.lastTimestamp }
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
                                .font(.system(size: 34, weight: .bold)).foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.knotMuted)
                        }
                    }
                    Spacer()
                    Button(action: { showAddPeople = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                            .padding(8).background(Color.knotWell).clipShape(Circle())
                            .overlay(Circle().stroke(Color.knotBorder, lineWidth: 1))
                    }
                }
                .padding(.horizontal).padding(.top, 16).padding(.bottom, 8)

                // Active filter pill
                if filter != .all {
                    HStack {
                        Label(filter.rawValue, systemImage: filterPillIcon)
                            .font(.caption).fontWeight(.medium).foregroundColor(Color.knotOnAccent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.knotAccent).cornerRadius(10)
                        Spacer()
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                }

                // ── Search ────────────────────────────────────────────────
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search", text: $searchText)
                        .autocapitalization(.none)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color(.systemGray3))
                        }
                    }
                }
                .padding(10).background(Color.knotWell).cornerRadius(12)
                .knotSurfaceBorder(cornerRadius: 12)
                .padding(.horizontal).padding(.bottom, 8)

                // ── Chat List / Connections Page ──────────────────────────
                if filter == .connections {
                    ConnectionsListView(searchText: searchText)
                } else if displayed.isEmpty && !profile.hasLoadedConversations {
                    // First load still in flight — spinner, not "no messages yet".
                    Spacer()
                    ProgressView()
                    Spacer()
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
                            // Button gives an immediate, full-row tap response.
                            // NavigationLink(value:) has a built-in selection delay
                            // that causes the "sometimes doesn't open" issue.
                            Button {
                                isSearchFocused = false
                                openConversation(convo.id)
                            } label: {
                                ConversationRow(conversation: convo, myName: profile.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.knotBackground)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparatorTint(Color.knotBorder)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    profile.deleteConversation(id: convo.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            // Swipe the other way (from the left) to favourite / unfavourite.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    profile.setConversationFavourite(id: convo.id,
                                                                     isFavourite: !convo.isFavourite)
                                } label: {
                                    Label(convo.isFavourite ? "Unfavourite" : "Favourite",
                                          systemImage: convo.isFavourite ? "star.slash.fill" : "star.fill")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.knotBackground)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            // NOTE: deliberately no tap/drag gesture on this container. Any tap
            // gesture wrapping the List fights the row NavigationLinks in the
            // gesture arena and stops chats from opening. Keyboard dismissal is
            // already handled globally (KeyboardDismiss window tap) and by the
            // List's .scrollDismissesKeyboard(.interactively).
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                ChatView(conversationID: id).environment(profile)
            }
            .onChange(of: profile.pendingChatConversationID) { _, id in
                if let id {
                    profile.pendingChatConversationID = nil
                    // Delay so any open sheets finish dismissing before we push
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        openConversation(id)
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

    private func openConversation(_ id: UUID) {
        var path = NavigationPath()
        path.append(id)
        navigationPath = path
    }
}

private struct AuthenticatedAvatarView<Placeholder: View>: View {
    let urlString: String
    let size: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                placeholder()
            }
        }
        .task(id: urlString) {
            if let cached = MessageImageCache.shared.get(urlString) {
                image = cached
                return
            }
            await ChatImageLoader.shared.load(urlString: urlString) { loaded in
                image = loaded
            }
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation
    let myName      : String
    @Environment(UserProfile.self) private var profile

    var body: some View {
        HStack(spacing: 14) {
            // Avatar — no left dot, sits flush at the leading edge
            Group {
                if let img = conversation.groupImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 62, height: 62).clipShape(Circle())
                } else if conversation.isGroup,
                          let urlStr = conversation.groupImageURL,
                          let url = URL(string: urlStr) {
                    AuthenticatedAvatarView(urlString: url.absoluteString, size: 62) {
                        ZStack {
                            Circle().fill(Color.knotAvatarBg).frame(width: 62, height: 62)
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 24)).foregroundColor(Color.knotMuted)
                        }
                    }
                } else if !conversation.isGroup,
                          let pid = conversation.participantID,
                          let urlStr = profile.connectionAvatarURLs[pid],
                          let url = URL(string: urlStr) {
                    AuthenticatedAvatarView(urlString: url.absoluteString, size: 62) {
                        ZStack {
                            Circle().fill(Color.knotAvatarBg).frame(width: 62, height: 62)
                            Text(String(conversation.participantName.prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .semibold)).foregroundColor(Color.knotMuted)
                        }
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.knotAvatarBg)
                            .frame(width: 62, height: 62)
                        if conversation.isGroup {
                            Image(systemName: "person.3.fill").font(.system(size: 22)).foregroundColor(Color.knotMuted)
                        } else {
                            Text(String(conversation.participantName.prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .semibold)).foregroundColor(Color.knotMuted)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if conversation.isFavourite {
                    Image(systemName: "star.fill").font(.system(size: 10))
                        .foregroundColor(.white).padding(2.5)
                        .background(Color.orange).clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(conversation.displayName)
                        .font(.body)
                        .fontWeight(conversation.unreadCount > 0 ? .bold : .semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    // Timestamp + unread badge on the right
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(timeAgo(conversation.lastTimestamp))
                            .font(.caption)
                            .foregroundColor(conversation.unreadCount > 0 ? Color.knotAccent : Color(.systemGray))
                        if conversation.unreadCount > 0 {
                            Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.knotOnAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.knotAccent)
                                .clipShape(Capsule())
                        }
                    }
                }
                HStack(spacing: 4) {
                    if let last = conversation.latestMessage,
                       last.senderID != nil && last.senderID == profile.currentUserID {
                        tickView(last.status)
                    }
                    Text(conversation.lastText)
                        .font(.subheadline)
                        .foregroundColor(conversation.unreadCount > 0 ? .primary : Color(.systemGray))
                        .lineLimit(2)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
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
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color.knotAccent)
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color.knotAccent)
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var messageText           = ""
    @FocusState private var isInputFocused  : Bool
    @State private var showContactProfile   = false
    @State private var showAttachSheet      = false   // bottom "Add photos" sheet
    @State private var showGalleryPicker    = false   // full-screen custom gallery
    @State private var showCameraFull       = false   // full-screen custom camera
    @State private var reviewItems          : [MediaReviewItem] = []  // photos pending review
    @State private var showReview           = false   // photo review/caption screen
    @State private var pendingVideoURL      : URL?    = nil
    @State private var showVideoReview      = false   // video review/caption screen
    @State private var selectedVideoRequest : VideoViewRequest? = nil
    @State private var mediaViewRequest     : MediaViewRequest? = nil
    @State private var selectedListing      : ShopListing?      = nil
    @State private var didInitialScroll     = false

    /// Stable id for the empty view pinned to the very bottom of the message list.
    /// Scrolling to a fixed anchor is reliable even as messages load in above it
    /// (the last message's own id changes, which a bottom anchor avoids).
    private let bottomAnchorID = "CHAT_BOTTOM_ANCHOR"

    private var isBlockedByParticipant: Bool {
        guard let pid = conversation?.participantID else { return false }
        return profile.blockedByUserIDs.contains(pid)
    }

    private var allMedia: [MediaSource] {
        (conversation?.messages.compactMap { msg -> MediaSource? in
            if let video = msg.videoURL, let poster = msg.imageURL { return .video(poster: poster, video: video) }
            if let img = msg.image     { return .local(img) }
            if let url = msg.imageURL  { return .remote(url) }
            return nil
        }) ?? []
    }

    private var renderItems: [ChatRenderItem] {
        guard let messages = conversation?.messages else { return [] }

        var items: [ChatRenderItem] = []
        var index = 0

        while index < messages.count {
            let message = messages[index]

            guard canStartImageGroup(with: message) else {
                items.append(.single(message: message, index: index))
                index += 1
                continue
            }

            var groupedMessages: [ChatMessage] = [message]
            var nextIndex = index + 1
            var previous = message

            while nextIndex < messages.count {
                let candidate = messages[nextIndex]
                guard canJoinImageGroup(candidate, after: previous) else { break }
                groupedMessages.append(candidate)
                previous = candidate
                nextIndex += 1
            }

            if groupedMessages.count >= 4 {
                items.append(.imageGroup(messages: groupedMessages, startIndex: index))
                index = nextIndex
            } else {
                for offset in groupedMessages.indices {
                    items.append(.single(message: groupedMessages[offset], index: index + offset))
                }
                index = nextIndex
            }
        }

        return items
    }

    private var convoIndex: Int? { profile.conversations.firstIndex { $0.id == conversationID } }
    private var conversation: Conversation? { convoIndex.map { profile.conversations[$0] } }
    private var chatTitle: String { conversation?.displayName ?? "" }
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Pin the message list to the newest message (the bottom anchor). A small
    /// delay lets SwiftUI lay out any newly-loaded rows first, so the scroll
    /// lands at the true bottom instead of mid-list.
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            didInitialScroll = true
        }
    }

    private func canStartImageGroup(with message: ChatMessage) -> Bool {
        message.hasImage &&
        !message.hasVideo &&
        !message.isSystem &&
        message.listingContext == nil &&
        message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func canJoinImageGroup(_ candidate: ChatMessage, after previous: ChatMessage) -> Bool {
        guard canStartImageGroup(with: candidate) else { return false }
        guard candidate.senderID == previous.senderID else { return false }
        guard candidate.sender == previous.sender else { return false }
        return abs(candidate.timestamp.timeIntervalSince(previous.timestamp)) <= 20
    }

    private func mediaIndex(for message: ChatMessage, in media: [MediaSource]) -> Int {
        if let video = message.videoURL {
            return media.firstIndex(where: {
                if case .video(_, let v) = $0 { return v == video }
                return false
            }) ?? 0
        }

        if let image = message.image {
            return media.firstIndex(where: {
                if case .local(let localImage) = $0 {
                    return localImage === image
                }
                return false
            }) ?? 0
        }

        if let url = message.imageURL {
            return media.firstIndex(where: {
                if case .remote(let remoteURL) = $0 {
                    return remoteURL == url
                }
                return false
            }) ?? 0
        }

        return 0
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Messages ──────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if let convo = conversation {
                            ForEach(renderItems) { item in
                                let anchorMessage = item.anchorMessage
                                let anchorIndex = item.anchorIndex

                                if shouldShowDateDivider(for: anchorMessage, at: anchorIndex, in: convo.messages) {
                                    ChatDateDivider(title: dateDividerTitle(for: anchorMessage.timestamp))
                                }

                                switch item {
                                case .single(let msg, _):
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
                                            isMe: msg.senderID != nil && msg.senderID == profile.currentUserID,
                                            showSenderName: convo.isGroup,
                                            onStar: { toggleStar(msgID: msg.id) },
                                            onOpenListing: msg.listingContext == nil ? nil : {
                                                guard let listingContext = msg.listingContext else { return }
                                                Task { await openListing(context: listingContext) }
                                            },
                                            onVideoTap: msg.hasVideo ? {
                                                guard let urlString = msg.videoURL,
                                                      let url = URL(string: urlString) else { return }
                                                selectedVideoRequest = VideoViewRequest(url: url)
                                            } : nil,
                                            onImageTap: msg.hasImage ? {
                                                let media = allMedia
                                                mediaViewRequest = MediaViewRequest(
                                                    sources: media,
                                                    startIndex: mediaIndex(for: msg, in: media)
                                                )
                                            } : nil
                                        )
                                        .id(msg.id)
                                    }
                                case .imageGroup(let messages, _):
                                    GroupedImageBubble(
                                        messages: messages,
                                        isMe: anchorMessage.senderID != nil && anchorMessage.senderID == profile.currentUserID,
                                        showSenderName: convo.isGroup,
                                        onImageTap: { tappedMessage in
                                            let media = allMedia
                                            mediaViewRequest = MediaViewRequest(
                                                sources: media,
                                                startIndex: mediaIndex(for: tappedMessage, in: media)
                                            )
                                        }
                                    )
                                    .id(anchorMessage.id)
                                }
                            }
                        }
                        // Always-last anchor so we can reliably pin to the bottom.
                        Color.clear.frame(height: 1).id(bottomAnchorID)
                    }
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    // Jump straight to the newest message on open (no animation).
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: conversation?.messages.count ?? 0) { _, _ in
                    // Fires when the full history finishes loading and when new
                    // messages arrive. Instant for the first load, animated after.
                    scrollToBottom(proxy, animated: didInitialScroll)
                }
                .onChange(of: isInputFocused) { _, focused in
                    // Scroll to newest message when the keyboard appears.
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
                        }
                    }
                }
            }

            // ── Input Bar ─────────────────────────────────────────────────
            if conversation?.hasLeft == true {
                HStack {
                    Spacer()
                    Text("You are not a member of this chat anymore")
                        .font(.subheadline)
                        .foregroundColor(Color.knotMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Color.knotSurface)
                .overlay(Divider(), alignment: .top)
            } else if let pid = conversation?.participantID,
                      profile.blockedUserIDs.contains(pid) {
                // You blocked this person — show a locked bar with unblock option
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(Color.knotMuted)
                    Text("You've blocked \(conversation?.participantName ?? "this person")")
                        .font(.subheadline)
                        .foregroundColor(Color.knotMuted)
                    Spacer()
                    Button("Unblock") {
                        Task { await profile.unblockUser(userID: pid) }
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.knotAccent)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.knotSurface)
                .overlay(Divider(), alignment: .top)
            } else if isBlockedByParticipant {
                HStack {
                    Spacer()
                    Text("\(conversation?.participantName ?? "This user") has blocked you")
                        .font(.subheadline)
                        .foregroundColor(Color.knotMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Color.knotSurface)
                .overlay(Divider(), alignment: .top)
            } else {
                HStack(spacing: 10) {
                    Button(action: { showAttachSheet = true }) {
                        Image(systemName: "photo").font(.system(size: 20)).foregroundColor(Color.knotMuted)
                    }

                    TextField("Message", text: $messageText, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.knotWell).cornerRadius(20)
                        .knotSurfaceBorder(cornerRadius: 20)

                    Button(action: { sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(canSend ? Color.knotAccent : Color.knotBorder)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.knotSurface)
                // Taps inside the input bar (incl. Send) must not dismiss the
                // keyboard — otherwise it bounces down then back up on send.
                .background(KeepKeyboardOnTap())
                .overlay(Divider(), alignment: .top)
                // ── Custom photo/video attachment flow ────────────────────
                .sheet(isPresented: $showAttachSheet) {
                    PhotoAttachSheet(
                        onTakePhoto: {
                            pendingVideoURL = nil
                            reviewItems = []
                            showReview = false
                            showVideoReview = false
                            // Slight delay so the bottom sheet fully dismisses
                            // before the full-screen camera presents.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCameraFull = true }
                        },
                        onChooseGallery: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGalleryPicker = true }
                        }
                    )
                }
                .fullScreenCover(isPresented: $showCameraFull) {
                    ChatCameraView(
                        onCapture: { img in
                            pendingVideoURL = nil
                            showVideoReview = false
                            reviewItems = [MediaReviewItem(image: img)]
                        },
                        onVideo: { url in
                            reviewItems = []
                            showReview = false
                            pendingVideoURL = url
                        }
                    )
                }
                .fullScreenCover(isPresented: $showGalleryPicker) {
                    ChatGalleryPicker { imgs in
                        reviewItems = imgs.map { MediaReviewItem(image: $0) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showReview = true }
                    }
                }
                .fullScreenCover(isPresented: $showReview) {
                    MediaReviewView(recipientName: chatTitle, items: reviewItems) { sent in
                        sendReviewedPhotos(sent)
                    }
                }
                .fullScreenCover(isPresented: $showVideoReview) {
                    if let url = pendingVideoURL {
                        VideoReviewView(recipientName: chatTitle, videoURL: url) { fileURL, caption in
                            sendReviewedVideo(fileURL, caption: caption)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Hide the main tab bar while a chat is open for a focused, full-height view.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: { showContactProfile = true }) {
                    HStack(spacing: 8) {
                        Group {
                            if let img = conversation?.groupImage {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 32, height: 32).clipShape(Circle())
                            } else if conversation?.isGroup == true,
                                      let urlStr = conversation?.groupImageURL,
                                      let url = URL(string: urlStr) {
                                AuthenticatedAvatarView(urlString: url.absoluteString, size: 32) {
                                    ZStack {
                                        Circle().fill(Color.knotAvatarBg).frame(width: 32, height: 32)
                                        Image(systemName: "person.3.fill").font(.system(size: 11)).foregroundColor(Color.knotMuted)
                                    }
                                }
                            } else if let pid = conversation?.participantID,
                                      let urlStr = profile.connectionAvatarURLs[pid],
                                      let url = URL(string: urlStr) {
                                AuthenticatedAvatarView(urlString: url.absoluteString, size: 32) {
                                    ZStack {
                                        Circle().fill(Color.knotAvatarBg).frame(width: 32, height: 32)
                                        Text(String(chatTitle.prefix(1)).uppercased())
                                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.knotMuted)
                                    }
                                }
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.knotAvatarBg)
                                        .frame(width: 32, height: 32)
                                    if conversation?.isGroup == true {
                                        Image(systemName: "person.3.fill").font(.system(size: 11)).foregroundColor(Color.knotMuted)
                                    } else {
                                        Text(String(chatTitle.prefix(1)).uppercased())
                                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.knotMuted)
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chatTitle).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
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
        .sheet(item: $selectedListing) { listing in
            ShopItemDetailView(listing: listing).environment(profile)
        }
        .fullScreenCover(item: $selectedVideoRequest) { request in
            VideoPlayerScreen(url: request.url)
        }
        .fullScreenCover(item: $mediaViewRequest) { req in
            ChatMediaViewer(sources: req.sources, startIndex: req.startIndex)
        }
        .task {
            await profile.loadMessages(conversationID: conversationID)
            profile.startMessagingRealtime(conversationID: conversationID)
            // Mark conversation as read on entry and zero out the local unread count.
            await profile.markConversationRead(conversationID: conversationID)
            // Check if the other person has blocked us (so we can show the banner).
            if let pid = conversation?.participantID, !conversation!.isGroup {
                await profile.checkIfBlockedBy(userID: pid)
            }
        }
        .onChange(of: conversation?.messages.count ?? 0) { _, _ in
            // Each new message that arrives while the chat is open is implicitly read.
            Task { await profile.markConversationRead(conversationID: conversationID) }
        }
        .onChange(of: showCameraFull) { _, isPresented in
            guard !isPresented else { return }
            if pendingVideoURL != nil {
                showVideoReview = true
            } else if !reviewItems.isEmpty {
                showReview = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Backgrounding tears down the realtime socket, which can end the
            // postgres-changes stream for good. When we come back to the
            // foreground, refetch any messages we missed and rebuild the live
            // subscription so new ones keep arriving without leaving the chat.
            guard newPhase == .active else { return }
            Task {
                await profile.loadMessages(conversationID: conversationID)
                profile.startMessagingRealtime(conversationID: conversationID)
                await profile.markConversationRead(conversationID: conversationID)
            }
        }
        .onDisappear {
            profile.stopMessagingRealtime()
        }
    }

    private func shouldShowDateDivider(for message: ChatMessage, at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(message.timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateDividerTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // Clear input immediately for a responsive feel.
        messageText    = ""
        isInputFocused = true   // keep keyboard up after sending

        Task { await profile.sendMessage(text: text, conversationID: conversationID, replyToID: nil) }
    }

    /// Send the photos confirmed on the review screen — each as its own image
    /// message carrying its own caption, with an optimistic local bubble.
    private func sendReviewedPhotos(_ items: [MediaReviewItem]) {
        guard let ci = convoIndex, !items.isEmpty else { return }
        for item in items {
            let localID = UUID()
            var localMsg = ChatMessage(
                text: item.caption, image: item.image, sender: profile.name,
                senderID: profile.currentUserID, timestamp: Date(), status: .sent, replyToID: nil
            )
            localMsg.id = localID
            profile.conversations[ci].messages.append(localMsg)

            let convID = conversationID
            let caption = item.caption
            let img = item.image
            Task {
                let ok = await profile.sendImageMessage(image: img, caption: caption, conversationID: convID)
                guard ok else { return }
                if let idx = profile.conversations.firstIndex(where: { $0.id == convID }),
                   let mi  = profile.conversations[idx].messages.firstIndex(where: { $0.id == localID }) {
                    profile.conversations[idx].messages.remove(at: mi)
                }
            }
        }
    }

    /// Send a reviewed video clip with its caption.
    private func sendReviewedVideo(_ fileURL: URL, caption: String) {
        let convID = conversationID
        Task { _ = await profile.sendVideoMessage(fileURL: fileURL, caption: caption, conversationID: convID) }
    }

    private func toggleStar(msgID: UUID) {
        guard let ci = convoIndex,
              let mi = profile.conversations[ci].messages.firstIndex(where: { $0.id == msgID })
        else { return }
        profile.conversations[ci].messages[mi].isStarred.toggle()
    }

    private func openListing(context: ListingMessageContext) async {
        if let cached = profile.allListings.first(where: { $0.id == context.listingID }) {
            selectedListing = cached
            return
        }

        do {
            guard let row = try await ShopService.fetch(listingID: context.listingID) else { return }
            let sellerName: String
            if let cachedName = profile.connectionProfiles[row.sellerId] {
                sellerName = cachedName
            } else if let fetchedProfile = try? await ProfileService.fetch(userID: row.sellerId) {
                sellerName = fetchedProfile.name
                profile.connectionProfiles[row.sellerId] = fetchedProfile.name
            } else {
                sellerName = "Unknown"
            }
            selectedListing = ShopListing(
                id: row.id,
                type: row.listingType.lowercased() == "service" ? .service : row.listingType.lowercased() == "advertisement" ? .advertisement : .item,
                category: ShopCategory.fromDB(row.category),
                condition: ItemCondition.fromDB(row.condition),
                name: row.name,
                description: row.description,
                link: row.link,
                price: row.priceCents / 100,
                sellerName: sellerName,
                sellerID: row.sellerId,
                isActive: row.isActive,
                isRecurring: row.isRecurring,
                acceptsCash: row.acceptsCash,
                acceptsCard: row.acceptsCard,
                imageURLs: row.imageUrls,
                date: row.createdAt
            )
        } catch {
            print("[ChatView] openListing error: \(error)")
        }
    }
}

struct InlineListingContextChip: View {
    let context: ListingMessageContext
    let isMe: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 60) }
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Re: \(context.listingName)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(isMe ? Color.knotOnAccent : Color.knotAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isMe ? Color.knotAccent.opacity(0.9) : Color.knotSurface)
                .overlay(
                    Capsule()
                        .stroke(isMe ? Color.knotAccent : Color.knotBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            if !isMe { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Chat Date Divider
struct ChatDateDivider: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(Color.knotMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.knotSurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.knotBorder, lineWidth: 1))
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message       : ChatMessage
    let isMe          : Bool
    var showSenderName: Bool = false
    var onStar        : () -> Void
    var onOpenListing : (() -> Void)? = nil

    var onVideoTap: (() -> Void)?  = nil
    var onImageTap: (() -> Void)?  = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {

                // Sender name (group chats)
                if showSenderName && !isMe {
                    Text(message.sender)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(Color(.systemGray))
                        .padding(.horizontal, 4)
                }

                if let listingContext = message.listingContext,
                   let onOpenListing {
                    InlineListingContextChip(
                        context: listingContext,
                        isMe: isMe,
                        onOpen: onOpenListing
                    )
                }

                // Bubble content — a message may carry an image, text, or BOTH
                // (a photo with a caption). Render the image first, then the
                // caption/text beneath it. Treating them as either/or hid the
                // caption on photo-with-text messages (common from Android).
                if message.videoURL != nil,
                   let posterURL = message.imageURL {
                    Button(action: { onVideoTap?() }) {
                        ZStack {
                            MessageImageView(urlString: posterURL)
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.48))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.leading, 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let img = message.image {
                    Button(action: { onImageTap?() }) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                } else if let urlStr = message.imageURL {
                    Button(action: { onImageTap?() }) {
                        MessageImageView(urlString: urlStr)
                    }
                    .buttonStyle(.plain)
                }

                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundColor(isMe ? Color.knotOnAccent : Color.knotInk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMe ? Color.knotAccent : Color.knotWell)
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
                Button(action: onStar)  { Label(message.isStarred ? "Unstar" : "Star",
                                                systemImage: message.isStarred ? "star.slash" : "star") }
            }

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
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color.knotAccent)
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color.knotAccent)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

struct GroupedImageBubble: View {
    let messages: [ChatMessage]
    let isMe: Bool
    var showSenderName: Bool = false
    let onImageTap: (ChatMessage) -> Void

    private let gridSpacing: CGFloat = 4
    private let bubbleSize: CGFloat = 220

    private var visibleMessages: [ChatMessage] {
        Array(messages.prefix(4))
    }

    private var overflowCount: Int {
        max(messages.count - 3, 0)
    }

    private var timestamp: Date {
        messages.last?.timestamp ?? messages[0].timestamp
    }

    private var senderName: String {
        messages.first?.sender ?? ""
    }

    private var itemSize: CGFloat {
        (bubbleSize - gridSpacing) / 2
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                if showSenderName && !isMe {
                    Text(senderName)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(Color(.systemGray))
                        .padding(.horizontal, 4)
                }

                VStack(spacing: gridSpacing) {
                    HStack(spacing: gridSpacing) {
                        gridCell(for: visibleMessages[0])
                        gridCell(for: visibleMessages[1])
                    }

                    HStack(spacing: gridSpacing) {
                        gridCell(for: visibleMessages[2])
                        trailingGridCell
                    }
                }
                .frame(width: bubbleSize, height: bubbleSize)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                HStack(spacing: 4) {
                    Text(timeString(timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(Color(.systemGray))
                    if isMe, let status = messages.last?.status {
                        ticksView(status)
                    }
                }
            }

            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
    }

    @ViewBuilder
    private var trailingGridCell: some View {
        if visibleMessages.count > 3 {
            let message = visibleMessages[3]
            Button(action: { onImageTap(message) }) {
                ZStack {
                    gridImage(for: message)
                    if messages.count > 4 {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.black.opacity(0.45))
                        Text("+\(overflowCount)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: itemSize, height: itemSize)
            }
            .buttonStyle(.plain)
        }
    }

    private func gridCell(for message: ChatMessage) -> some View {
        Button(action: { onImageTap(message) }) {
            gridImage(for: message)
                .frame(width: itemSize, height: itemSize)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridImage(for message: ChatMessage) -> some View {
        if let image = message.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if let url = message.imageURL {
            MessageImageView(urlString: url, maxWidth: itemSize, maxHeight: itemSize)
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.knotWell)
        }
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
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color.knotAccent)
                Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Color.knotAccent)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
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
    @State private var profileUserID          : UUID?   = nil   // companion UUID for profileName sheet
    @State private var mediaViewRequest       : MediaViewRequest? = nil
    @State private var selectedKnot           : CommunityGroup?   = nil
    @State private var showEditGroup           = false

    // Member management
    @State private var memberProfileTarget      : String? = nil  // tapped member — shows profile sheet
    @State private var showLeaveConfirm         = false
    @State private var showDeleteConfirm        = false

    // Creator or admin — has management powers. UUID compare so renames can't
    // grant access (impersonation) or revoke access (data loss).
    private var amIPrivileged: Bool {
        guard let convo = liveConvo, let me = profile.currentUserID else { return false }
        if convo.creatorID == me || convo.adminIDs.contains(me) { return true }
        // Admins of the source knot are also admins of that knot's group chat.
        if let knotID = convo.sourceKnotID { return profile.isKnotAdmin(knotID) }
        return false
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
        return profile.publicKnots.filter { $0.adminName == convo.participantName }
    }

    private var canAddToKnotGroupChat: Bool {
        guard let convo = liveConvo, !convo.isGroup, let knotID = convo.sourceKnotID else { return false }
        return profile.createdGroups.contains { $0.id == knotID }
    }

    @ViewBuilder
    private func avatarHeader(convo: Conversation) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = convo.groupImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 80, height: 80).clipShape(Circle())
            } else if convo.isGroup, let urlStr = convo.groupImageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .frame(width: 80, height: 80).clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(Color.knotAvatarBg).frame(width: 80, height: 80)
                            Image(systemName: "person.3.fill").font(.system(size: 32)).foregroundColor(Color.knotMuted)
                        }
                    }
                }
            } else if convo.isGroup {
                ZStack {
                    Circle().fill(Color.knotAvatarBg).frame(width: 80, height: 80)
                    Image(systemName: "person.3.fill").font(.system(size: 32)).foregroundColor(Color.knotMuted)
                }
            } else if let pid = convo.participantID,
                      let urlStr = profile.connectionAvatarURLs[pid],
                      let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .frame(width: 80, height: 80).clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(Color.knotAvatarBg).frame(width: 80, height: 80)
                            Text(String(convo.participantName.prefix(1)).uppercased())
                                .font(.system(size: 32, weight: .semibold)).foregroundColor(Color.knotMuted)
                        }
                    }
                }
            } else {
                ZStack {
                    Circle().fill(Color.knotAvatarBg).frame(width: 80, height: 80)
                    Text(String(convo.participantName.prefix(1)).uppercased())
                        .font(.system(size: 32, weight: .semibold)).foregroundColor(Color.knotMuted)
                }
            }
            if convo.isGroup && amIPrivileged {
                Button(action: { showEditGroup = true }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color.knotAccent)
                        .background(Color(.systemBackground).clipShape(Circle()))
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
        let starred : [ChatMessage]  = convo.messages.filter { $0.isStarred }
        let media   : [MediaSource]  = convo.messages.compactMap { msg in
            if let video = msg.videoURL, let poster = msg.imageURL { return .video(poster: poster, video: video) }
            if let img = msg.image     { return .local(img) }
            if let url = msg.imageURL  { return .remote(url) }
            return nil
        }

        NavigationStack {
            List {

                // ── Header ────────────────────────────────────────────────
                Section {
                    VStack(spacing: 10) {
                        avatarHeader(convo: convo)

                        Text(convo.displayName).font(.system(size: 20, weight: .bold))

                        if convo.isGroup {
                            Text("\(convo.participants.count + 1) members")
                                .font(.caption).foregroundColor(.secondary)
                            if !convo.groupDescription.isEmpty {
                                Text(convo.groupDescription)
                                    .font(.subheadline).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24).padding(.top, 2)
                            }
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
                            // UUID-based identity — survives renames + prevents impersonation.
                            let memberID      = convo.memberIDsByName[member]
                            let isThisCreator = memberID != nil && memberID == convo.creatorID
                            let isThisAdmin   = memberID.map { convo.adminIDs.contains($0) } ?? false
                            let isMe          = memberID != nil && memberID == profile.currentUserID
                            let avatarColor: Color = isThisCreator ? .primary : (isThisAdmin ? Color(.systemGray2) : Color(.systemGray3))
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
                                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Color(.systemBackground))
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(isMe ? "\(member) (You)" : member)
                                            .font(.subheadline).foregroundColor(.primary)
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
                                            .font(.system(size: 11)).foregroundColor(.primary)
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
                if !media.isEmpty {
                    Section("Media") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(media.indices, id: \.self) { i in
                                    Button(action: {
                                        mediaViewRequest = MediaViewRequest(sources: media, startIndex: i)
                                    }) {
                                        Group {
                                            switch media[i] {
                                            case .local(let img):
                                                Image(uiImage: img)
                                                    .resizable().scaledToFill()
                                            case .remote(let url):
                                                MessageImageView(urlString: url, maxWidth: 80, maxHeight: 80)
                                            case .video(let poster, _):
                                                ZStack {
                                                    MessageImageView(urlString: poster, maxWidth: 80, maxHeight: 80)
                                                    Image(systemName: "play.circle.fill")
                                                        .font(.system(size: 24))
                                                        .foregroundColor(.white.opacity(0.9))
                                                        .shadow(radius: 2)
                                                }
                                            }
                                        }
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
                                    Text((msg.senderID != nil && msg.senderID == profile.currentUserID) ? "You" : msg.sender)
                                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                                    Text(msg.hasImage && msg.text.isEmpty ? "📷 Photo" : msg.text)
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
                                        Image(systemName: knot.imageName).font(.system(size: 16)).foregroundColor(.primary)
                                    }
                                    Text(knot.name).font(.subheadline).foregroundColor(.primary)
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
                        Button(action: {
                            profileName   = convo.participantName
                            profileUserID = convo.participantID
                        }) {
                            Label("View Profile", systemImage: "person.circle").foregroundColor(.primary)
                        }
                    }
                    if canAddToKnotGroupChat {
                        Button(action: { addToKnotGroupChat(convo: convo) }) {
                            Label("Add to \(convo.sourceKnotName) Knot Chat",
                                  systemImage: "person.badge.plus").foregroundColor(.primary)
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

            // ── Edit group details (name + description + photo) ───────────
            .sheet(isPresented: $showEditGroup) {
                EditGroupChatView(conversationID: conversationID).environment(profile)
            }

            .sheet(item: $profileName) { name in
                UserProfileView(name: name, userID: profileUserID).environment(profile)
            }
            .sheet(item: $memberProfileTarget) { name in
                GroupMemberProfileView(name: name, conversationID: conversationID)
                    .environment(profile)
            }
            .sheet(item: $selectedKnot) { knot in
                KnotDetailView(group: knot).environment(profile)
            }
            .fullScreenCover(item: $mediaViewRequest) { req in
                ChatMediaViewer(sources: req.sources, startIndex: req.startIndex)
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
    @State private var searchResults       : [DBProfile] = []
    @State private var isSearching         = false
    @State private var selectedPerson      : DBProfile? = nil
    @State private var showCreateGroupChat = false

    var body: some View {
        NavigationStack {
            List {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search by name", text: $searchText)
                        .autocapitalization(.none)
                        .onChange(of: searchText) { _, q in
                            Task { await runSearch(q) }
                        }
                    if isSearching {
                        ProgressView().scaleEffect(0.7)
                    } else if !searchText.isEmpty {
                        Button(action: { searchText = ""; searchResults = [] }) {
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
                                Image(systemName: "person.3.fill").font(.system(size: 16)).foregroundColor(Color(.systemBackground))
                            }
                            Text("New Group Chat").font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                        }
                    }
                }

                if !searchResults.isEmpty {
                    Section(searchText.isEmpty ? "Suggested People" : "Results") {
                        ForEach(searchResults, id: \.id) { result in
                            Button(action: { selectedPerson = result }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.primary).frame(width: 40, height: 40)
                                        Text(String(result.name.prefix(1)).uppercased())
                                            .font(.system(size: 16, weight: .semibold)).foregroundColor(Color(.systemBackground))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                                        if profile.connections.contains(result.name) {
                                            Text("Connected").font(.caption).foregroundColor(.green)
                                        } else if profile.sentConnectionRequests.contains(result.name) {
                                            Text("Request sent").font(.caption).foregroundColor(.secondary)
                                        } else {
                                            Text("Neighbour").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if profile.connections.contains(result.name) {
                                        Image(systemName: "person.fill.checkmark").foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                } else if !searchText.isEmpty && !isSearching {
                    Section {
                        Text("No people found for \"\(searchText)\"")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await runSearch("") }
            .sheet(item: $selectedPerson) { person in
                UserProfileView(name: person.name, userID: person.id).environment(profile)
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

    @MainActor
    private func runSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let currentID = supabase.auth.currentUser?.id
            let results = try await ProfileService.search(query: query, limit: 30)
            print("[AddPeopleSheet] search '\(query)' returned \(results.count) results, currentID=\(String(describing: currentID))")
            searchResults = results.filter { $0.id != currentID }
        } catch {
            print("[AddPeopleSheet] search error: \(error)")
        }
    }
}

// MARK: - Edit Group Chat View (name, description, photo)
/// Admin/creator editor opened from the edit circle on the group avatar.
struct EditGroupChatView: View {
    let conversationID: UUID
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    @State private var name             = ""
    @State private var groupDescription = ""
    @State private var pickedImage      : UIImage? = nil
    @State private var showSourceChoice = false
    @State private var showCamera       = false
    @State private var showLibrary      = false
    @State private var didLoad          = false

    private var convo: Conversation? { profile.conversations.first { $0.id == conversationID } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Button(action: {
                            if CameraPicker.isAvailable { showSourceChoice = true } else { showLibrary = true }
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let img = pickedImage {
                                        Image(uiImage: img).resizable().scaledToFill()
                                    } else if let urlStr = convo?.groupImageURL, let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { phase in
                                            if let i = phase.image { i.resizable().scaledToFill() }
                                            else { placeholderAvatar }
                                        }
                                    } else if let img = convo?.groupImage {
                                        Image(uiImage: img).resizable().scaledToFill()
                                    } else {
                                        placeholderAvatar
                                    }
                                }
                                .frame(width: 88, height: 88).clipShape(Circle())
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 24)).foregroundColor(Color.knotAccent)
                                    .background(Color(.systemBackground).clipShape(Circle()))
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Group Name") {
                    TextField("Group name", text: $name)
                }
                Section("Description") {
                    TextField("What's this group about?", text: $groupDescription, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("Group Photo", isPresented: $showSourceChoice, titleVisibility: .visible) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showLibrary) {
                SingleImagePicker { img in
                    pickedImage = img
                    showLibrary = false
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { img in pickedImage = img }
            }
            .onAppear {
                guard !didLoad, let c = convo else { return }
                name = c.groupName
                groupDescription = c.groupDescription
                didLoad = true
            }
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(Color.knotAvatarBg)
            Image(systemName: "person.3.fill").font(.system(size: 30)).foregroundColor(Color.knotMuted)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        profile.updateGroupDetails(id: conversationID, name: trimmedName,
                                   description: groupDescription.trimmingCharacters(in: .whitespaces))
        if let img = pickedImage {
            profile.updateConversationImage(id: conversationID, image: img)
        }
        dismiss()
    }
}

// MARK: - Create Group Chat View
struct CreateGroupChatView: View {
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var groupName            = ""
    @State private var selectedParticipants : Set<UUID> = []
    @State private var groupImage            : UIImage?    = nil
    @State private var showGroupPhotoPicker  = false

    private var connectionPeople: [(id: UUID, name: String)] {
        guard let currentUserID = profile.currentUserID else { return [] }

        return profile.dbConnections
            .filter { $0.status == "accepted" }
            .compactMap { connection -> (id: UUID, name: String)? in
                let otherID = connection.requesterId == currentUserID ? connection.recipientId : connection.requesterId
                guard !profile.blockedUserIDs.contains(otherID),
                      !profile.blockedByUserIDs.contains(otherID),
                      let name = profile.connectionProfiles[otherID]
                else { return nil }
                return (otherID, name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var canCreate: Bool { !groupName.trimmingCharacters(in: .whitespaces).isEmpty && selectedParticipants.count >= 1 }

    var body: some View {
        NavigationStack {
            List {
                // ── Group photo + name ─────────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        Button(action: { showGroupPhotoPicker = true }) {
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
                                                .font(.system(size: 22)).foregroundColor(Color(.systemBackground))
                                        }
                                    }
                                }
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.primary)
                                    .background(Color(.systemBackground).clipShape(Circle()))
                            }
                        }
                        .sheet(isPresented: $showGroupPhotoPicker) {
                            SingleImagePicker { img in
                                groupImage = img
                                showGroupPhotoPicker = false
                            }
                        }

                        TextField("e.g. Book Club Chat", text: $groupName)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }

                Section("Add Participants") {
                    if connectionPeople.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No connections yet")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("Connect with people before adding them to a group chat.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(connectionPeople, id: \.id) { person in
                            Button(action: {
                                if selectedParticipants.contains(person.id) { selectedParticipants.remove(person.id) }
                                else { selectedParticipants.insert(person.id) }
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.primary).frame(width: 36, height: 36)
                                        Text(String(person.name.prefix(1)).uppercased())
                                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Color(.systemBackground))
                                    }
                                    Text(person.name).font(.subheadline).foregroundColor(.primary)
                                    Spacer()
                                    if selectedParticipants.contains(person.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.primary)
                                    } else {
                                        Image(systemName: "circle").foregroundColor(Color(.systemGray3))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Group Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createGroup() }
                        .fontWeight(.semibold).disabled(!canCreate)
                }
            }
            .task {
                await profile.loadConnections()
            }
        }
    }

    private func createGroup() {
        let participantIDs = Array(selectedParticipants)
        let participantNames = participantIDs.compactMap { profile.connectionProfiles[$0] }
        let trimmedName  = groupName.trimmingCharacters(in: .whitespaces)
        let img          = groupImage
        dismiss()
        Task {
            await profile.createGroupConversation(
                name            : trimmedName,
                participantIDs  : participantIDs,
                participantNames: participantNames,
                groupImage      : img
            )
        }
    }
}

private struct MessageMediaComposerView: View {
    @Binding var images: [UIImage]
    @Binding var caption: String
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var showInlineCamera = false
    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if images.isEmpty {
                    Color.clear
                        .onAppear { dismiss() }
                } else {
                    VStack(spacing: 0) {
                        TabView(selection: $currentIndex) {
                            ForEach(images.indices, id: \.self) { index in
                                Image(uiImage: images[index])
                                    .resizable()
                                    .scaledToFit()
                                    .tag(index)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        HStack {
                            if images.count > 1 {
                                Text("\(currentIndex + 1) / \(images.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Color.knotAccent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.knotAccent.opacity(0.55), lineWidth: 1)
                                    )
                                    .cornerRadius(12)
                            }
                            Spacer()
                            Button(role: .destructive, action: deleteCurrentImage) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.red.opacity(0.85))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 16)

                        HStack(spacing: 10) {
                            Button(action: { showInlineCamera = true }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color.knotMuted)
                                    .frame(width: 38, height: 38)
                                    .background(Color.knotSurface)
                                    .clipShape(Circle())
                            }

                            TextField("Add a caption...", text: $caption, axis: .vertical)
                                .lineLimit(1...4)
                                .focused($isCaptionFocused)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.knotWell)
                                .cornerRadius(20)
                                .knotSurfaceBorder(cornerRadius: 20)

                            Button(action: onSend) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(Color.knotAccent)
                            }
                            .disabled(images.isEmpty)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.knotSurface)
                    }
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Color.knotOnAccent)
                }
            }
            .sheet(isPresented: $showInlineCamera) {
                CameraPicker { img in
                    images.append(img)
                    currentIndex = images.count - 1
                }
            }
        }
    }

    private func deleteCurrentImage() {
        guard images.indices.contains(currentIndex) else { return }
        images.remove(at: currentIndex)
        if images.isEmpty {
            dismiss()
            return
        }
        currentIndex = min(currentIndex, images.count - 1)
    }
}

// MARK: - Chat Media Viewer (full-screen image viewer with Save / Share)
struct ChatMediaViewer: View {
    let sources    : [MediaSource]
    let startIndex : Int
    @State private var currentIndex   : Int
    @State private var loadedImages   : [Int: UIImage] = [:]   // cache for remote pages
    @State private var saveToast      : String? = nil
    @State private var videoRequest   : VideoViewRequest? = nil
    @Environment(\.dismiss) var dismiss

    init(sources: [MediaSource], startIndex: Int) {
        self.sources    = sources
        self.startIndex = startIndex
        _currentIndex   = State(initialValue: startIndex)
    }

    /// The visible image (if loaded) for the current page — used by Save / Share.
    private var currentImage: UIImage? {
        guard sources.indices.contains(currentIndex) else { return nil }
        switch sources[currentIndex] {
        case .local(let img):  return img
        case .remote(let url): return loadedImages[currentIndex] ?? MessageImageCache.shared.get(url)
        case .video(let poster, _): return loadedImages[currentIndex] ?? MessageImageCache.shared.get(poster)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(sources.indices, id: \.self) { i in
                    ZoomableImagePage(
                        source     : sources[i],
                        onLoaded   : { img in loadedImages[i] = img },
                        cachedImage: cachedFor(sources[i]),
                        onPlayVideo: { videoStr in
                            if let url = URL(string: videoStr) { videoRequest = VideoViewRequest(url: url) }
                        }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // ── Top bar ───────────────────────────────────────────────────
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color.knotOnAccent)
                            .padding(10)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    Spacer()
                    if sources.count > 1 {
                        Text("\(currentIndex + 1) / \(sources.count)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.knotAccent)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.knotAccent.opacity(0.55), lineWidth: 1)
                            )
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }

            // ── Bottom action bar ─────────────────────────────────────────
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Button(action: saveCurrent) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 22, weight: .medium))
                            Text("Save").font(.caption2)
                        }
                        .foregroundColor(Color.knotOnAccent)
                        .frame(width: 64, height: 56)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(currentImage == nil)
                    .opacity(currentImage == nil ? 0.5 : 1)

                    Button(action: shareCurrent) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 22, weight: .medium))
                            Text("Share").font(.caption2)
                        }
                        .foregroundColor(Color.knotOnAccent)
                        .frame(width: 64, height: 56)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(currentImage == nil)
                    .opacity(currentImage == nil ? 0.5 : 1)
                }
                .padding(.bottom, 40)
            }

            // ── Save toast ────────────────────────────────────────────────
            if let msg = saveToast {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(Color.knotOnAccent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                    Spacer().frame(height: 130)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden()
        .fullScreenCover(item: $videoRequest) { req in
            VideoPlayerScreen(url: req.url)
        }
    }

    // MARK: helpers
    private func cachedFor(_ s: MediaSource) -> UIImage? {
        if case .remote(let url) = s { return MessageImageCache.shared.get(url) }
        if case .local(let img) = s  { return img }
        if case .video(let poster, _) = s { return MessageImageCache.shared.get(poster) }
        return nil
    }

    private func saveCurrent() {
        guard let img = currentImage else { return }
        ImageSaver.save(img) { result in
            switch result {
            case .success:
                showToast("Saved to Photos")
            case .failure(let err):
                showToast("Couldn't save: \(err.localizedDescription)")
            }
        }
    }

    private func shareCurrent() {
        guard let img = currentImage else { return }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root  = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let activity = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = top.view
        top.present(activity, animated: true)
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { saveToast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.25)) { saveToast = nil }
        }
    }
}

// MARK: - Zoomable single-page (pinch to zoom, double-tap to toggle)
private struct ZoomableImagePage: View {
    let source     : MediaSource
    let onLoaded   : (UIImage) -> Void
    let cachedImage: UIImage?
    var onPlayVideo: ((String) -> Void)? = nil

    /// The playable video URL string when this page is a video.
    private var videoString: String? {
        if case .video(_, let v) = source { return v }
        return nil
    }

    @State private var image     : UIImage? = nil
    @State private var scale     : CGFloat  = 1.0
    @State private var lastScale : CGFloat  = 1.0
    @State private var offset    : CGSize   = .zero
    @State private var lastOffset: CGSize   = .zero
    @State private var failed    : Bool     = false

    init(
        source: MediaSource,
        onLoaded: @escaping (UIImage) -> Void,
        cachedImage: UIImage?,
        onPlayVideo: ((String) -> Void)? = nil
    ) {
        self.source = source
        self.onLoaded = onLoaded
        self.cachedImage = cachedImage
        self.onPlayVideo = onPlayVideo
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Group {
                        if scale > 1.0 {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(scale)
                                .offset(offset)
                                .gesture(magnifyGesture)
                                .simultaneousGesture(panGesture)
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if scale > 1.0 {
                                            scale      = 1.0
                                            lastScale  = 1.0
                                            offset     = .zero
                                            lastOffset = .zero
                                        } else {
                                            scale     = 2.5
                                            lastScale = 2.5
                                        }
                                    }
                                }
                        } else {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(scale)
                                .offset(offset)
                                .gesture(magnifyGesture)
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if scale > 1.0 {
                                            scale      = 1.0
                                            lastScale  = 1.0
                                            offset     = .zero
                                            lastOffset = .zero
                                        } else {
                                            scale     = 2.5
                                            lastScale = 2.5
                                        }
                                    }
                                }
                        }
                    }
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36)).foregroundColor(.white.opacity(0.6))
                        Text("Couldn't load image")
                            .font(.subheadline).foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    ProgressView().tint(.white)
                }

                // Play button overlaid on a video page's poster.
                if let videoString, image != nil {
                    Button(action: { onPlayVideo?(videoString) }) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.5)).frame(width: 74, height: 74)
                            Image(systemName: "play.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white).padding(.leading, 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: identityKey) { await loadIfNeeded() }
    }

    private var identityKey: String {
        switch source {
        case .local(let img):  return "local:\(ObjectIdentifier(img).hashValue)"
        case .remote(let url): return "remote:\(url)"
        case .video(let poster, let video): return "video:\(poster)|\(video)"
        }
    }

    private func loadIfNeeded() async {
        if let cached = cachedImage {
            image = cached
            onLoaded(cached)
            return
        }
        switch source {
        case .local(let img):
            image = img
            onLoaded(img)
        case .remote(let url):
            // Reuse the same loading path as MessageImageView (SDK + URLSession).
            await ChatImageLoader.shared.load(urlString: url) { img in
                if let img {
                    image = img
                    onLoaded(img)
                } else {
                    failed = true
                }
            }
        case .video(let poster, _):
            await ChatImageLoader.shared.load(urlString: poster) { img in
                if let img {
                    image = img
                    onLoaded(img)
                } else {
                    failed = true
                }
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, min(lastScale * value, 5.0))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.0 {
                    withAnimation(.spring(response: 0.3)) {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width : lastOffset.width  + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }
}

// MARK: - Loader used by the viewer (mirrors MessageImageView's logic)
@MainActor
final class ChatImageLoader {
    static let shared = ChatImageLoader()
    func load(urlString: String, completion: @escaping (UIImage?) -> Void) async {
        if let cached = MessageImageCache.shared.get(urlString) {
            completion(cached); return
        }
        // Try Supabase SDK download first, then URLSession.
        if let (bucket, path) = Self.parseSupabaseStorageURL(urlString) {
            do {
                let data = try await supabase.storage.from(bucket).download(path: path)
                if let img = UIImage(data: data) {
                    MessageImageCache.shared.set(img, for: urlString)
                    completion(img); return
                }
            } catch {
                print("[ChatImageLoader] SDK download failed: \(error)")
            }
        }
        guard let url = URL(string: urlString) else { completion(nil); return }
        var req = URLRequest(url: url)
        if let token = try? await supabase.auth.session.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let img = UIImage(data: data) {
                MessageImageCache.shared.set(img, for: urlString)
                completion(img)
            } else { completion(nil) }
        } catch {
            print("[ChatImageLoader] URLSession failed: \(error)")
            completion(nil)
        }
    }

    private static func parseSupabaseStorageURL(_ s: String) -> (String, String)? {
        guard let url = URL(string: s) else { return nil }
        var parts = url.pathComponents
        if parts.first == "/" { parts.removeFirst() }
        guard let i = parts.firstIndex(of: "object") else { return nil }
        var rest = Array(parts.dropFirst(i + 1))
        if let first = rest.first, first == "public" || first == "sign" || first == "authenticated" {
            rest.removeFirst()
        }
        guard let bucket = rest.first, rest.count > 1 else { return nil }
        return (bucket, rest.dropFirst().joined(separator: "/"))
    }
}

// MARK: - ImageSaver (NSObject so we can use the selector-based callback)
final class ImageSaver: NSObject {
    typealias Completion = (Result<Void, Error>) -> Void
    private var completion: Completion?

    /// Save `image` to Photos. Calls `completion` on the main thread.
    static func save(_ image: UIImage, completion: @escaping Completion) {
        let saver = ImageSaver()
        saver.completion = completion
        // Retain until the callback fires.
        objc_setAssociatedObject(image, &saverKey, saver, .OBJC_ASSOCIATION_RETAIN)
        UIImageWriteToSavedPhotosAlbum(image,
                                       saver,
                                       #selector(ImageSaver.didFinishSaving(_:didFinishSavingWithError:contextInfo:)),
                                       nil)
    }

    @objc private func didFinishSaving(_ image: UIImage,
                                       didFinishSavingWithError error: Error?,
                                       contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            if let error { self.completion?(.failure(error)) }
            else         { self.completion?(.success(())) }
            objc_setAssociatedObject(image, &saverKey, nil, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
private nonisolated(unsafe) var saverKey: UInt8 = 0

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
        // Resolve the contact's UUID first, then match the conversation by participantID.
        // Name comparison alone would let an impersonator hijack DM routing if two
        // contacts share a display name.
        let targetID = profile.connectionProfiles.first { $0.value == name }?.key
        guard let tid = targetID else { return nil }
        return profile.conversations.first { $0.participantID == tid && !$0.isGroup }
    }

    var body: some View {
        if let convo = conversation {
            NavigationLink(value: convo.id) {
                ConversationRow(conversation: convo, myName: profile.name)
            }
        } else {
            Button(action: {
                // Prefer UUID-based opener — same lookup used by `conversation` above.
                if let uid = profile.connectionProfiles.first(where: { $0.value == name })?.key {
                    profile.openConversation(withUserID: uid, name: name)
                } else {
                    profile.openConversation(with: name)
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.primary).frame(width: 50, height: 50)
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .semibold)).foregroundColor(Color(.systemBackground))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
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
    @State private var memberIsPrivate        = false

    private var convo: Conversation? { profile.conversations.first { $0.id == conversationID } }
    /// UUID of the member this view is showing. Looked up from name via the conversation's
    /// memberIDsByName map so all privilege checks below are UUID-based.
    private var memberID: UUID? { convo?.memberIDsByName[name] }
    private var isThisCreator: Bool {
        guard let mid = memberID, let cid = convo?.creatorID else { return false }
        return mid == cid
    }
    private var isThisAdmin  : Bool {
        guard let mid = memberID else { return false }
        return convo?.adminIDs.contains(mid) ?? false
    }
    private var amIPrivileged: Bool {
        guard let c = convo, let me = profile.currentUserID else { return false }
        return c.creatorID == me || c.adminIDs.contains(me)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Profile header ────────────────────────────────────
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.primary).frame(width: 90, height: 90)
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .semibold)).foregroundColor(Color(.systemBackground))
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
                                Label("View Profile", systemImage: "person.crop.circle").foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                            }
                            .padding()
                        }
                        Divider().padding(.leading, 52)

                        let canMessage = profile.connections.contains(name) || !memberIsPrivate
                        if canMessage {
                            Button(action: {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    // memberID is the conversation participant's UUID — use it
                                    // for a reliable open, fall back to name only as last resort.
                                    if let mid = memberID {
                                        profile.openConversation(withUserID: mid, name: name)
                                    } else {
                                        profile.openConversation(with: name)
                                    }
                                }
                            }) {
                                HStack {
                                    Label("Message", systemImage: "message").foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
                                }
                                .padding()
                            }
                            Divider().padding(.leading, 52)
                        }

                        if !profile.connections.contains(name) && !profile.sentConnectionRequests.contains(name) {
                            Button(action: {
                                profile.sendConnectionRequest(to: name)
                            }) {
                                HStack {
                                    Label("Add Connection", systemImage: "person.badge.plus").foregroundColor(.primary)
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
                                        Label("Make Admin", systemImage: "star.badge.plus").foregroundColor(.primary)
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
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    // Hairline outline so the card stays distinct from the page in dark mode.
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Member")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Load the member's privacy setting so we can gate the Message button
                if let mid = memberID {
                    if let p = try? await ProfileService.fetch(userID: mid) {
                        memberIsPrivate = p.isPrivate
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showProfile) {
                UserProfileView(name: name, userID: memberID).environment(profile)
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
    let profile = UserProfile(name: "Ruhaan")
    profile.conversations = makeSampleConversations(myName: "Ruhaan")
    return MessagesView().environment(profile)
}
