import SwiftUI
import UIKit

// MARK: - Announcement Model

struct Announcement: Identifiable {
    var id       : UUID   = UUID()
    var knotID   : UUID?  = nil   // nil = platform-wide
    var title    : String
    var body     : String
    var sender   : String
    var date     : String
    var isRead   : Bool
    var knotName : String
    var isPinned : Bool   = false
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
    @Environment(UserProfile.self) var profile
    @State private var selectedAnnouncement: Announcement? = nil
    @State private var showClearConfirm     = false

    private var pinned      : [Announcement] { profile.announcements.filter { $0.isPinned } }
    private var regular     : [Announcement] { profile.announcements.filter { !$0.isPinned } }
    private var unreadCount : Int            { profile.announcements.filter { !$0.isRead }.count }

    private var hasAnything: Bool {
        !profile.announcements.isEmpty ||
        !profile.pendingReceivedRequests.isEmpty ||
        !profile.sentConnectionRequests.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text("Alerts")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.black)
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
                            .foregroundColor(.black)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if !hasAnything {
                emptyState
            } else {
                List {
                    // ── Received connection requests ─────────────────
                    if !profile.pendingReceivedRequests.isEmpty {
                        Section {
                            ForEach(profile.pendingReceivedRequests, id: \.connectionID) { request in
                                ConnectionRequestRow(name: request.name) {
                                    Task { await profile.acceptConnectionRequest(connectionID: request.connectionID) }
                                } onDecline: {
                                    Task { await profile.declineConnectionRequest(connectionID: request.connectionID) }
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Label("Connection Requests", systemImage: "person.badge.plus")
                                .font(.caption)
                                .foregroundColor(.black)
                                .textCase(nil)
                        }
                    }

                    // ── Sent connection requests ─────────────────────
                    if !profile.sentConnectionRequests.isEmpty {
                        Section {
                            ForEach(profile.sentConnectionRequests, id: \.self) { name in
                                SentConnectionRow(name: name)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 2)
                            }
                        } header: {
                            Label("Sent Requests", systemImage: "paperplane")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .textCase(nil)
                        }
                    }

                    // ── Pinned alerts ────────────────────────────────
                    if !pinned.isEmpty {
                        Section {
                            ForEach(pinned) { a in
                                AnnouncementRow(announcement: a)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture { markReadAndOpen(a) }
                            }
                        } header: {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.black)
                                .textCase(nil)
                        }
                    }

                    // ── Regular alerts ───────────────────────────────
                    if !regular.isEmpty {
                        Section {
                            ForEach(regular) { a in
                                AnnouncementRow(announcement: a)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture { markReadAndOpen(a) }
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { regular[$0].id }
                                profile.announcements.removeAll { ids.contains($0.id) }
                            }
                        } header: {
                            Text(pinned.isEmpty ? "Alerts" : "Other Alerts")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(UIColor.systemGray6))
            }
        }
        .background(Color(UIColor.systemGray6).ignoresSafeArea())
        .sheet(item: $selectedAnnouncement) { AnnouncementDetailView(announcement: $0) }
        .confirmationDialog("Clear all alerts?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { profile.announcements.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all alerts.")
        }
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(Color(UIColor.systemGray3))
            Text("No Alerts")
                .font(.headline)
                .foregroundColor(Color(UIColor.systemGray))
            Text("Alerts from your Knots and the shop will appear here.")
                .font(.caption)
                .foregroundColor(Color(UIColor.systemGray3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGray6).ignoresSafeArea())
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
                Circle().fill(Color.black).frame(width: 36, height: 36)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(name)
                .font(.subheadline).fontWeight(.semibold).foregroundColor(.black)
                .lineLimit(1)

            Spacer()

            Button(action: onAccept) {
                Text("Accept")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button(action: onDecline) {
                Text("Decline")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(UIColor.systemGray5))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }
}

// MARK: - Sent Connection Row (outgoing)

struct SentConnectionRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(UIColor.systemGray4)).frame(width: 40, height: 40)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.black)
                Text("Connection request sent")
                    .font(.caption).foregroundColor(.gray)
            }

            Spacer()

            Text("Pending")
                .font(.caption2).foregroundColor(.gray)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }
}

// MARK: - Announcement Row (used in Dashboard + Alerts tab)

struct AnnouncementRow: View {
    let announcement: Announcement

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread dot
            Circle()
                .fill(announcement.isRead ? Color.clear : Color.black)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(announcement.knotName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                    Spacer()
                    if announcement.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Text(announcement.date)
                        .font(.caption2)
                        .foregroundColor(Color(UIColor.systemGray3))
                }

                Text(announcement.title)
                    .font(.subheadline)
                    .fontWeight(announcement.isRead ? .regular : .semibold)
                    .foregroundColor(.black)
                    .lineLimit(1)

                Text(announcement.body)
                    .font(.caption)
                    .foregroundColor(Color(UIColor.systemGray))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }
}

// MARK: - Announcement Detail View (opened from Dashboard / SearchView)

struct AnnouncementDetailView: View {
    let announcement: Announcement
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Knot + sender chip
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(announcement.knotName)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("·")
                            .foregroundColor(Color(UIColor.systemGray3))
                        Text("by \(announcement.sender)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        if announcement.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }

                    Text(announcement.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)

                    Text(announcement.date)
                        .font(.caption)
                        .foregroundColor(Color(UIColor.systemGray3))

                    Divider()

                    Text(announcement.body)
                        .font(.body)
                        .foregroundColor(.black.opacity(0.8))
                        .lineSpacing(5)
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AnnouncementsTabView()
        .environment(UserProfile(name: "Ruhaan"))
}
