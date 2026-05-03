import SwiftUI

// MARK: - Setting Entry (for settings search)
struct SettingEntry: Identifiable {
    let id      : String
    let name    : String
    let icon    : String
    let keywords: [String]
}

let allSettings: [SettingEntry] = [
    SettingEntry(id: "editProfile",    name: "Edit Profile",       icon: "person.fill",                  keywords: ["edit", "profile", "name", "bio", "photo", "picture", "address", "description"]),
    SettingEntry(id: "notifications",  name: "Notifications",      icon: "bell.fill",                    keywords: ["notification", "notifications", "alert", "push", "buzz", "remind"]),
    SettingEntry(id: "private",        name: "Private Account",    icon: "lock.fill",                    keywords: ["private", "public", "account", "lock", "hidden", "visibility"]),
    SettingEntry(id: "profileDisplay", name: "Profile Display",    icon: "eye.fill",                     keywords: ["display", "show", "hide", "profile", "listing", "knot", "connection", "visible"]),
    SettingEntry(id: "privacy",        name: "Privacy & Security", icon: "shield.fill",                  keywords: ["privacy", "security", "block", "blocked", "data", "safe", "protect", "two factor", "password", "2fa"]),
    SettingEntry(id: "wallet",         name: "Wallet & Payments",  icon: "creditcard.fill",               keywords: ["wallet", "payment", "pay", "buy", "purchase", "stripe", "balance", "top up", "credit"]),
    SettingEntry(id: "help",           name: "Help & Support",     icon: "questionmark.circle.fill",     keywords: ["help", "support", "contact", "faq", "question", "problem", "report", "feedback", "bug", "issue"]),
    SettingEntry(id: "faq",            name: "FAQ",                icon: "doc.text.fill",                keywords: ["faq", "frequently", "asked", "question", "how", "guide", "learn"]),
    SettingEntry(id: "feedback",       name: "Send Feedback",      icon: "star.fill",                    keywords: ["feedback", "rating", "review", "rate", "star", "opinion", "suggest"]),
    SettingEntry(id: "terms",          name: "Terms of Service",   icon: "doc.plaintext.fill",           keywords: ["terms", "service", "legal", "agreement", "tos", "conditions"]),
    SettingEntry(id: "policyPrivacy",  name: "Privacy Policy",     icon: "hand.raised.fill",             keywords: ["privacy", "policy", "gdpr", "data", "legal"]),
]

// MARK: - Message Match (wraps a conversation + snippet for display)
struct MessageMatch: Identifiable {
    let id           = UUID()
    let conversation : Conversation
    let snippet      : String
}

// MARK: - Search View
struct SearchView: View {
    @State private var searchText        = ""
    @State private var selectedGroup     : CommunityGroup? = nil
    @State private var selectedListing   : ShopListing?    = nil
    @State private var selectedPerson    : String?         = nil
    @State private var selectedAlert     : Announcement?   = nil
    @State private var selectedSetting   : SettingEntry?   = nil
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    // MARK: - Search scopes

    var knotResults: [CommunityGroup] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return (sampleGroups + profile.createdGroups).filter {
            $0.name.lowercased().contains(q)        ||
            $0.category.lowercased().contains(q)    ||
            $0.location.lowercased().contains(q)    ||
            $0.description.lowercased().contains(q) ||
            $0.adminName.lowercased().contains(q)
        }
    }

    var listingResults: [ShopListing] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return (sampleListings + profile.myListings).filter {
            $0.name.lowercased().contains(q)        ||
            $0.description.lowercased().contains(q) ||
            $0.sellerName.lowercased().contains(q)  ||
            $0.category.rawValue.lowercased().contains(q) ||
            $0.type.rawValue.lowercased().contains(q)     ||
            $0.condition.rawValue.lowercased().contains(q)
        }
    }

    var peopleResults: [String] {
        guard !searchText.isEmpty else { return [] }
        let q      = searchText.lowercased()
        let all    = Set(profile.connections + suggestedPeople +
                        profile.conversations.flatMap { c in
                            c.isGroup ? c.participants : [c.participantName]
                        })
        return all.filter { $0.lowercased().contains(q) }.sorted()
    }

    var alertResults: [Announcement] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return profile.announcements.filter {
            $0.title.lowercased().contains(q)    ||
            $0.body.lowercased().contains(q)     ||
            $0.sender.lowercased().contains(q)   ||
            $0.knotName.lowercased().contains(q)
        }
    }

    var messageResults: [MessageMatch] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        var out: [MessageMatch] = []
        for convo in profile.conversations {
            // Match on conversation name
            if convo.displayName.lowercased().contains(q) {
                out.append(MessageMatch(conversation: convo, snippet: convo.lastText))
                continue
            }
            // Match on any message text
            if let hit = convo.messages.first(where: { $0.text.lowercased().contains(q) }) {
                out.append(MessageMatch(conversation: convo, snippet: hit.text))
            }
        }
        return out
    }

    var settingResults: [SettingEntry] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return allSettings.filter {
            $0.name.lowercased().contains(q) ||
            $0.keywords.contains { $0.contains(q) }
        }
    }

    var hasResults: Bool {
        !knotResults.isEmpty || !listingResults.isEmpty || !peopleResults.isEmpty ||
        !alertResults.isEmpty || !messageResults.isEmpty || !settingResults.isEmpty
    }

    let suggestions = ["My Knots", "Hub listings", "Wallet & Payments", "Connections", "Edit Profile", "Alerts", "Privacy"]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Search bar ────────────────────────────────────────────
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Search people, knots, messages, settings…", text: $searchText)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color(.systemGray3))
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // ── Empty state: suggestions ──────────────────────────────
                if searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggestions")
                            .font(.caption).foregroundColor(.gray).padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(action: { searchText = suggestion }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(Color(.systemGray3)).frame(width: 20)
                                        Text(suggestion).font(.subheadline).foregroundColor(.black)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption).foregroundColor(Color(.systemGray3))
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                }
                                if suggestion != suggestions.last {
                                    Divider().padding(.leading, 48)
                                }
                            }
                        }
                        .background(Color.white).cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 1))
                        .padding(.horizontal)
                    }
                    Spacer()

                // ── No results ────────────────────────────────────────────
                } else if !hasResults {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36)).foregroundColor(Color(.systemGray3))
                        Text("No results for \"\(searchText)\"")
                            .font(.subheadline).foregroundColor(Color(.systemGray3))
                        Text("Try searching for a person's name, message, listing, knot, alert, or setting")
                            .font(.caption).foregroundColor(Color(.systemGray4))
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    Spacer()

                // ── Results ───────────────────────────────────────────────
                } else {
                    List {

                        // People
                        if !peopleResults.isEmpty {
                            Section("People") {
                                ForEach(peopleResults, id: \.self) { person in
                                    Button(action: { selectedPerson = person }) {
                                        SearchRow(
                                            icon: "person.circle.fill",
                                            iconColor: .black,
                                            title: person,
                                            subtitle: profile.connections.contains(person) ? "Connected" : nil
                                        )
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Knots
                        if !knotResults.isEmpty {
                            Section("Knots") {
                                ForEach(knotResults) { group in
                                    Button(action: { selectedGroup = group }) {
                                        SearchRow(
                                            icon: group.imageName,
                                            iconColor: .black,
                                            title: group.name,
                                            subtitle: group.category
                                        )
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Shop
                        if !listingResults.isEmpty {
                            Section("Hub") {
                                ForEach(listingResults) { listing in
                                    Button(action: { selectedListing = listing }) {
                                        SearchRow(
                                            icon: listing.type.icon,
                                            iconColor: listing.type == .service ? .blue : listing.type == .advertisement ? .orange : .black,
                                            title: listing.name,
                                            subtitle: "\(listing.sellerName) · \(listing.category.rawValue)"
                                        )
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Messages
                        if !messageResults.isEmpty {
                            Section("Messages") {
                                ForEach(messageResults) { match in
                                    Button(action: {
                                        profile.pendingChatConversationID = match.conversation.id
                                        profile.selectedTab = .messages
                                        dismiss()
                                    }) {
                                        SearchRow(
                                            icon: match.conversation.isGroup ? "person.3.fill" : "message.fill",
                                            iconColor: match.conversation.isGroup ? Color(.systemGray) : .black,
                                            title: match.conversation.displayName,
                                            subtitle: match.snippet.isEmpty ? nil : match.snippet
                                        )
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Alerts
                        if !alertResults.isEmpty {
                            Section("Alerts") {
                                ForEach(alertResults) { alert in
                                    Button(action: { selectedAlert = alert }) {
                                        SearchRow(
                                            icon: "bell.fill",
                                            iconColor: .black,
                                            title: alert.title,
                                            subtitle: alert.sender
                                        )
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Settings
                        if !settingResults.isEmpty {
                            Section("Settings") {
                                ForEach(settingResults) { entry in
                                    Button(action: { selectedSetting = entry }) {
                                        SearchRow(
                                            icon: entry.icon,
                                            iconColor: .black,
                                            title: entry.name,
                                            subtitle: "Settings"
                                        )
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }

            // ── Navigation sheets ─────────────────────────────────────────
            .sheet(item: $selectedGroup)   { KnotDetailView(group: $0).environment(profile) }
            .sheet(item: $selectedListing) { ShopItemDetailView(listing: $0).environment(profile) }
            .sheet(item: $selectedAlert)   { AnnouncementDetailView(announcement: $0) }
            .sheet(item: $selectedPerson)  { UserProfileView(name: $0).environment(profile) }
            .sheet(item: $selectedSetting) { entry in
                SettingDestinationView(entry: entry).environment(profile)
            }
        }
    }
}

// MARK: - Search Row (shared row layout)
struct SearchRow: View {
    let icon      : String
    let iconColor : Color
    let title     : String
    var subtitle  : String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).foregroundColor(.black)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundColor(.gray).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color(.systemGray3))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Setting Destination View (routes to the right settings screen)
struct SettingDestinationView: View {
    let entry: SettingEntry
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch entry.id {
                case "editProfile":    EditProfileView()
                case "notifications":  NotificationsSettingsView()
                case "profileDisplay": ProfileDisplaySettingsView()
                case "privacy":        PrivacySecurityView()
                case "wallet":         WalletPaymentsView()
                case "help":           HelpSupportView()
                case "faq":            FAQView()
                case "feedback":       FeedbackView()
                case "terms":          WebContentView(title: "Terms of Service")
                case "policyPrivacy":  WebContentView(title: "Privacy Policy")
                case "private":
                    List {
                        Section {
                            Toggle("Private Account", isOn: Binding(
                                get: { profile.isPrivateAccount },
                                set: { profile.isPrivateAccount = $0 }
                            ))
                        } footer: {
                            Text("When your account is private, only connections can see your Knots and listings.")
                        }
                    }
                    .navigationTitle("Private Account")
                    .navigationBarTitleDisplayMode(.inline)
                default:
                    Text("Settings").padding()
                }
            }
            .environment(profile)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
