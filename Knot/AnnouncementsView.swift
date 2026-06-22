import SwiftUI
import UIKit

// MARK: - Announcement Model

struct Announcement: Identifiable {
    var id               : UUID   = UUID()
    var knotID           : UUID?  = nil   // nil = platform-wide
    var title            : String
    var body             : String
    var sender           : String
    var senderID         : UUID?  = nil
    var date             : String
    var isRead           : Bool
    var knotName         : String
    var isPinned         : Bool   = false
    var paymentRequestId : UUID?  = nil   // set on payment request announcements
    var imageURLs        : [String] = []
}

// MARK: - Sample Announcements
// TODO: replace with real data from Supabase (Phase 5)

let sampleAnnouncements: [Announcement] = [
    Announcement(
        title   : "Sunday Run — Time Change",
        body    : "This Sunday's run is moved to 7:30 AM instead of 7:00 AM. Meet at the usual spot near the fountain entrance.",
        sender  : "Wei Ming",
        date    : "Today, 9:14 AM",
        isRead  : false,
        knotName: "Sunday Runners",
        isPinned: true
    ),
    Announcement(
        title   : "New Recipe Night Theme",
        body    : "Next session we're doing Japanese home cooking. Bring an ingredient or a favourite recipe to share!",
        sender  : "Sarah Tan",
        date    : "Yesterday, 6:45 PM",
        isRead  : false,
        knotName: "Neighbourhood Cooks"
    ),
    Announcement(
        title   : "This Month's Book",
        body    : "We're reading \"Tomorrow, and Tomorrow, and Tomorrow\" by Gabrielle Zevin. Pick up your copy before the 25th.",
        sender  : "Priya Nair",
        date    : "Mon, 11:00 AM",
        isRead  : true,
        knotName: "Book Club"
    ),
    Announcement(
        title   : "Photography Walk — New Route",
        body    : "Saturday's walk will go through the heritage shophouses at Emerald Hill. Bring a wide-angle lens if you have one.",
        sender  : "James Lim",
        date    : "Sun, 3:22 PM",
        isRead  : true,
        knotName: "Photography Walk"
    ),
]

// MARK: - Announcements Tab View

struct AnnouncementsTabView: View {
    private enum RequestPreview: Identifiable {
        case received(connectionID: UUID, name: String)
        case sent(name: String)

        var id: String {
            switch self {
            case .received(let connectionID, _):
                return "received-\(connectionID.uuidString.lowercased())"
            case .sent(let name):
                return "sent-\(name.lowercased())"
            }
        }
    }

    @Environment(UserProfile.self) var profile
    @State private var selectedAnnouncement: Announcement? = nil
    @State private var showClearConfirm     = false
    @State private var showWelcomeGuide     = false
    @State private var showAllAlerts        = false
    @State private var showAllOrders        = false

    private var pinned      : [Announcement] { profile.announcements.filter { $0.isPinned } }
    private var regular     : [Announcement] { profile.announcements.filter { !$0.isPinned } }
    private var unreadCount : Int            { profile.announcements.filter { !$0.isRead }.count }
    private var alertPreviews: [Announcement] { pinned + regular }
    private var requestPreviews: [RequestPreview] {
        let received = profile.pendingReceivedRequests.map {
            RequestPreview.received(connectionID: $0.connectionID, name: $0.name)
        }
        let sent = profile.sentConnectionRequests.map {
            RequestPreview.sent(name: $0)
        }
        return received + sent
    }
    private var visibleAlerts: [Announcement] {
        showAllAlerts ? alertPreviews : Array(alertPreviews.prefix(1))
    }
    private var visibleOrders: [KnotOrder] {
        showAllOrders ? orderUpdates : Array(orderUpdates.prefix(1))
    }
    private var orderUpdates: [KnotOrder] {
        profile.orders
            .filter { order in
                if order.status == .complete || order.status == .cancelled {
                    let date = latestOrderUpdateDate(order)
                    return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0 <= 30
                }
                return true
            }
            .sorted { latestOrderUpdateDate($0) > latestOrderUpdateDate($1) }
    }

    private var hasAnything: Bool {
        !profile.announcements.isEmpty ||
        !orderUpdates.isEmpty ||
        !profile.pendingReceivedRequests.isEmpty ||
        !profile.sentConnectionRequests.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text("Alerts")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                if !profile.announcements.isEmpty {
                    Menu {
                        Button(action: markAllRead) {
                            Label("Mark All as Read", systemImage: "envelope.open")
                        }
                        .disabled(unreadCount == 0)

                        Button(role: .destructive, action: { showClearConfirm = true }) {
                            Label("Clear All Alerts", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                    }
                    // Anchor the confirmation popover to the ellipsis button
                    // so the popup visually points at what triggered it,
                    // instead of floating in the centre of the screen.
                    .popover(isPresented: $showClearConfirm, arrowEdge: .top) {
                        ConfirmPopoverContent(
                            title  : "Clear All Alerts?",
                            message: "This will permanently remove all alerts.",
                            confirmLabel: "Clear All",
                            onConfirm: {
                                profile.dismissAllAnnouncements()
                                showClearConfirm = false
                            },
                            onCancel: { showClearConfirm = false }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            List {
                // ── Welcome Guide (always at top) ────────────────
                Section {
                    WelcomeGuideRow()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { showWelcomeGuide = true }
                } header: {
                    Label("Getting Started", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .textCase(nil)
                }

                // The rest is conditional on having actual alerts/requests
                if hasAnything {
                    // ── Received connection requests ─────────────────
                    if !requestPreviews.isEmpty {
                        Section {
                            ForEach(requestPreviews) { request in
                                Group {
                                    switch request {
                                    case .received(let connectionID, let name):
                                        ConnectionRequestRow(name: name) {
                                            Task { await profile.acceptConnectionRequest(connectionID: connectionID) }
                                        } onDecline: {
                                            Task { await profile.declineConnectionRequest(connectionID: connectionID) }
                                        }
                                    case .sent(let name):
                                        SentConnectionRow(name: name)
                                    }
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Label("Your Requests", systemImage: "person.badge.plus")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .textCase(nil)
                        }
                    }

                    // ── Alerts ────────────────────────────────────────
                    if !alertPreviews.isEmpty {
                        Section {
                            ForEach(visibleAlerts) { a in
                                AnnouncementRow(announcement: a)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture { markReadAndOpen(a) }
                            }
                            if alertPreviews.count > 1 {
                                SeeMoreRow(
                                    title: showAllAlerts ? "See Less" : "See More"
                                ) {
                                    showAllAlerts.toggle()
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Label("Alerts", systemImage: "bell.fill")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .textCase(nil)
                        }
                    }

                    // ── Order updates ────────────────────────────────
                    if !orderUpdates.isEmpty {
                        Section {
                            ForEach(visibleOrders) { order in
                                OrderUpdateAlertRow(order: order, date: formatOrderAlertDate(latestOrderUpdateDate(order)))
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture { profile.openOrdersFromNotification(orderID: order.id) }
                            }
                            if orderUpdates.count > 1 {
                                SeeMoreRow(
                                    title: showAllOrders ? "See Less" : "See More"
                                ) {
                                    showAllOrders.toggle()
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Label("Order Updates", systemImage: "bag.badge.clock")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.knotBackground)
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .sheet(isPresented: $showWelcomeGuide) { WelcomeGuideSheet() }
        .sheet(item: $selectedAnnouncement) { AnnouncementDetailView(announcement: $0).environment(profile) }
        .task { await profile.loadOrders() }
        // Clear-all confirmation is now a popover anchored to the ellipsis
        // button (see the header Menu above) so it visually points at its
        // source instead of appearing centred or at the bottom.
    }

    private func markReadAndOpen(_ announcement: Announcement) {
        if let i = profile.announcements.firstIndex(where: { $0.id == announcement.id }) {
            profile.announcements[i].isRead = true
        }
        selectedAnnouncement = announcement
        Task {
            do { try await AnnouncementService.markRead(announcementID: announcement.id) }
            catch { print("[AnnouncementsView] markRead error: \(error)") }
        }
    }

    private func markAllRead() {
        let unread = profile.announcements.filter { !$0.isRead }
        for i in profile.announcements.indices {
            profile.announcements[i].isRead = true
        }
        Task {
            for a in unread {
                try? await AnnouncementService.markRead(announcementID: a.id)
            }
        }
    }

    private func latestOrderUpdateDate(_ order: KnotOrder) -> Date {
        order.stepDates[order.status.rawValue] ?? order.stepDates.values.max() ?? order.date
    }

    private func formatOrderAlertDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(Color.knotMuted)
            Text("No Alerts")
                .font(.headline)
                .foregroundColor(Color.knotMuted)
            Text("Alerts from your Knots and the shop will appear here.")
                .font(.caption)
                .foregroundColor(Color.knotMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.knotBackground.ignoresSafeArea())
    }
}

private struct SeeMoreRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.knotAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.knotAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.knotSurface)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connection Request Row (incoming)

struct ConnectionRequestRow: View {
    let name      : String
    let onAccept  : () -> Void
    let onDecline : () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.knotAccent).frame(width: 36, height: 36)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.knotOnAccent)
            }

            Text(name)
                .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Button(action: onAccept) {
                Text("Accept")
                    .font(.caption).fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.knotAccent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button(action: onDecline) {
                Text("Decline")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.knotSurface)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.knotSurface)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Sent Connection Row (outgoing)

struct SentConnectionRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.knotSurface).frame(width: 40, height: 40)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                Text("Connection request sent")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text("Pending")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.knotSurface)
                .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.knotSurface)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Order Update Row

struct OrderUpdateAlertRow: View {
    let order: KnotOrder
    let date: String
    @Environment(UserProfile.self) private var profile

    private var isSeller: Bool { order.sellerId == profile.currentUserID }

    private var title: String {
        switch order.status {
        case .pending:
            return isSeller ? "New order to review" : "Order placed"
        case .sellerAccepted:
            return isSeller ? "Order accepted" : "Seller accepted your order"
        case .meetupAgreed:
            return "Meetup confirmed"
        case .awaitingConfirmation:
            return isSeller ? "Waiting for buyer confirmation" : "Confirm when received"
        case .complete:
            return "Order closed"
        case .disputed:
            return "Order disputed"
        case .cancelled:
            return "Order cancelled"
        }
    }

    private var bodyText: String {
        switch order.status {
        case .pending:
            return isSeller ? "Review \(order.listing.name) and accept or cancel the order." : "Waiting for the seller to accept \(order.listing.name)."
        case .sellerAccepted:
            return order.fulfilment == .meetup ? "Review or propose meetup details for \(order.listing.name)." : "The seller is preparing \(order.listing.name)."
        case .meetupAgreed:
            return "Meetup is set for \(order.listing.name)."
        case .awaitingConfirmation:
            return isSeller ? "The buyer needs to confirm receipt for \(order.listing.name)." : "Tap when you have received \(order.listing.name) to close the order."
        case .complete:
            return "\(order.listing.name) is complete."
        case .disputed:
            return "A problem was reported for \(order.listing.name)."
        case .cancelled:
            return "\(order.listing.name) was cancelled."
        }
    }

    private var tint: Color {
        switch order.status {
        case .pending:              return Color(.systemOrange)
        case .sellerAccepted,
             .meetupAgreed:         return Color(.systemBlue)
        case .awaitingConfirmation,
             .complete:             return Color(.systemGreen)
        case .disputed,
             .cancelled:            return Color(.systemRed)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "bag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Order \(order.id)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(date)
                        .font(.caption2)
                        .foregroundColor(Color.knotMuted)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(bodyText)
                    .font(.caption)
                    .foregroundColor(Color.knotMuted)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.knotSurface)
    }
}

// MARK: - Announcement Row (used in Dashboard + Alerts tab)

struct AnnouncementRow: View {
    let announcement: Announcement

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread dot
            Circle()
                .fill(announcement.isRead ? Color.clear : Color.primary)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(announcement.knotName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    if announcement.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(announcement.date)
                        .font(.caption2)
                        .foregroundColor(Color.knotMuted)
                }

                Text(announcement.title)
                    .font(.subheadline)
                    .fontWeight(announcement.isRead ? .regular : .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(announcement.body)
                    .font(.caption)
                    .foregroundColor(Color.knotMuted)
                    .lineLimit(2)

                if !announcement.imageURLs.isEmpty {
                    AnnouncementPhotoStrip(
                        imageURLs: announcement.imageURLs,
                        tileSize: 64
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.knotSurface)
    }
}

private struct AnnouncementPhotoStrip: View {
    let imageURLs: [String]
    var tileSize: CGFloat = 84
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                    Group {
                        if let onTap {
                            Button(action: { onTap(index) }) {
                                thumbnail(url: url)
                            }
                            .buttonStyle(.plain)
                        } else {
                            thumbnail(url: url)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func thumbnail(url: String) -> some View {
        MessageImageView(urlString: url, maxWidth: tileSize, maxHeight: tileSize)
            .frame(width: tileSize, height: tileSize)
            .clipped()
    }
}

// MARK: - Announcement Detail View (opened from Dashboard / SearchView)

struct AnnouncementDetailView: View {
    let announcement: Announcement
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) private var profile
    @State private var expandedPhotoIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Knot + sender chip
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(announcement.knotName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(Color.knotMuted)
                        Text("by \(announcement.sender)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if announcement.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(announcement.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)

                    Text(announcement.date)
                        .font(.caption)
                        .foregroundColor(Color.knotMuted)

                    Text(announcement.body)
                        .font(.body)
                        .foregroundColor(.primary.opacity(0.85))
                        .lineSpacing(5)

                    if !announcement.imageURLs.isEmpty {
                        AnnouncementPhotoStrip(
                            imageURLs: announcement.imageURLs,
                            tileSize: 92,
                            onTap: { expandedPhotoIndex = $0 }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { expandedPhotoIndex != nil },
                set: { if !$0 { expandedPhotoIndex = nil } }
            )
        ) {
            if let initialIndex = expandedPhotoIndex {
                AnnouncementPhotoViewer(
                    imageURLs: announcement.imageURLs,
                    initialIndex: initialIndex
                )
            }
        }
    }
}

private struct AnnouncementPhotoViewer: View {
    let imageURLs: [String]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, urlString in
                    GeometryReader { geo in
                        ZStack {
                            Color.black

                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geo.size.width, height: geo.size.height)
                                    } else if phase.error != nil {
                                        Image(systemName: "photo")
                                            .font(.system(size: 36, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.7))
                                    } else {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Button("Close") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(currentIndex + 1) / \(imageURLs.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.knotAccent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .onAppear {
            currentIndex = min(max(initialIndex, 0), max(imageURLs.count - 1, 0))
        }
    }
}

// MARK: - Welcome Guide Row (persistent, top of Alerts tab)

struct WelcomeGuideRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.knotAccent)
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.knotOnAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Welcome to Knot")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Text("Your full guide to using the app — what every feature does and how to make the most of it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.knotSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 1))
        .padding(.horizontal, 4)
    }
}

// MARK: - Welcome Guide Sheet (full walkthrough)

struct WelcomeGuideSheet: View {
    @Environment(\.dismiss) var dismiss

    private struct Feature {
        let icon       : String
        let title      : String
        let purpose    : String
        let howTo      : [String]
    }

    private let features: [Feature] = [
        Feature(
            icon   : "person.3.fill",
            title  : "Knots",
            purpose: "Knots are communities — your neighbourhood, your school, your hobby group. They're where conversations and local activity actually happen.",
            howTo  : [
                "Open the Knots tab to browse public groups near you.",
                "Tap a Knot to see details. Press Join (or Request to Join for approval-only Knots).",
                "Press Open Knot Group Chat to talk to all members.",
                "Tap Create Knot to start your own — set whether it's public, paid, age-restricted, or a one-off event."
            ]
        ),
        Feature(
            icon   : "tag.fill",
            title  : "Hub",
            purpose: "The Hub is the marketplace inside your Knots. Items, services, and small ads — but only visible to the people you share a Knot with. No strangers, no spam.",
            howTo  : [
                "Open the Hub tab to see what's for sale in your Knots.",
                "Tap a listing to view details, message the seller, or buy.",
                "Use the + button to post your own listing — pick item, service, or advertisement.",
                "Manage your active orders from the Active Orders banner on your home screen."
            ]
        ),
        Feature(
            icon   : "message.fill",
            title  : "Messages",
            purpose: "All your conversations in one place — one-to-one chats, group chats, and Knot chats.",
            howTo  : [
                "Open Messages to see all your chats sorted by recent activity.",
                "Tap the + button to start a new chat — search by name to add anyone on Knot.",
                "Filter chats by Favourites or Connections using the menu at the top.",
                "Long-press a message to star or copy it."
            ]
        ),
        Feature(
            icon   : "bell.fill",
            title  : "Alerts",
            purpose: "Important updates from your Knots, connection requests, and events all live here.",
            howTo  : [
                "Knot admins post announcements that show up in this tab.",
                "Accept or decline incoming connection requests from the top of this list.",
                "Swipe to delete alerts you no longer need.",
                "Tap any alert to read the full details."
            ]
        ),
        Feature(
            icon   : "person.crop.circle.fill",
            title  : "Profile & Connections",
            purpose: "Your profile is how neighbours recognise you. Connections are people you've added — like a Knot-only friend list.",
            howTo  : [
                "Tap your profile circle on the home screen to edit your name, bio, photo, and address.",
                "Search for people from the Messages tab to send a connection request.",
                "Use Privacy & Security in your profile to control who sees your address, Knots, listings, and connections.",
                "Sign out from the bottom of the profile sheet."
            ]
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Welcome to Knot")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Knot is the simplest way to stay connected with the people around you — your neighbourhood, your community, your local life.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Feature sections
                    ForEach(features.indices, id: \.self) { i in
                        featureCard(features[i])
                            .padding(.horizontal)
                    }

                    // Footer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.primary)
                        bullet("Join a few Knots first — that's where everything else (Hub, Knot chats, alerts) becomes useful.")
                        bullet("Add your address in your profile so we can show you local Knots automatically.")
                        bullet("Mark important chats as Favourites for quick access.")
                        bullet("You can always come back to this guide from the Alerts tab.")
                    }
                    .padding(16)
                    .background(Color.knotSurface)
                    .cornerRadius(14)
                    .padding(.horizontal)

                    Spacer().frame(height: 12)
                }
                .padding(.vertical, 20)
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func featureCard(_ f: Feature) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.knotAccent)
                        .frame(width: 38, height: 38)
                    Image(systemName: f.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color.knotOnAccent)
                }
                Text(f.title)
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            Text(f.purpose)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("How to use it")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.primary)
                ForEach(f.howTo, id: \.self) { step in
                    bullet(step)
                }
            }
        }
        .padding(16)
        .background(Color.knotSurface)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ConfirmPopoverContent
// Reusable popover body for destructive confirmations. Used wherever we want
// the confirmation popup anchored to its trigger button instead of floating
// in the centre of the screen (see `.popover` call sites). Pair it with
// `.presentationCompactAdaptation(.popover)` to keep it as a popover on iPhone.
struct ConfirmPopoverContent: View {
    let title       : String
    let message     : String
    let confirmLabel: String
    let onConfirm   : () -> Void
    let onCancel    : () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.knotSurface)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemRed))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 280)
    }
}

#Preview {
    AnnouncementsTabView()
        .environment(UserProfile(name: "Ruhaan"))
}
