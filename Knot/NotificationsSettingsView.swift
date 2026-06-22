import SwiftUI

// MARK: - Notifications Settings View
// Preferences persist in Supabase (user_settings table) so they sync across devices.
// Actual push delivery is wired up post-launch — these flags are read by the future
// notification sender to decide whether to fan-out a given event to a given user.
struct NotificationsSettingsView: View {
    @State private var groupsEnabled        = true
    @State private var messagesEnabled      = true
    @State private var announcementsEnabled = true
    @State private var marketplaceEnabled   = false
    @State private var isLoading            = true

    var body: some View {
        List {
            Section {
                Toggle("Knots",        isOn: $groupsEnabled)
                Toggle("Messages",     isOn: $messagesEnabled)
                Toggle("Alerts",       isOn: $announcementsEnabled)
                Toggle("Hub",          isOn: $marketplaceEnabled)
            } header: {
                Text("Notify me about")
            } footer: {
                Text("Your preferences sync across all your devices. You can also manage system permissions in iOS Settings › Knot.")
            }
        }
        .disabled(isLoading)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            if let prefs = try? await SettingsService.fetchNotificationPrefs() {
                withTransaction(transaction) {
                    groupsEnabled        = prefs.notifyKnots
                    messagesEnabled      = prefs.notifyMessages
                    announcementsEnabled = prefs.notifyAnnouncements
                    marketplaceEnabled   = prefs.notifyMarketplace
                }
            }
            withTransaction(transaction) {
                isLoading = false
            }
        }
        // Persist every toggle change.
        .onChange(of: groupsEnabled)        { _, _ in persist() }
        .onChange(of: messagesEnabled)      { _, _ in persist() }
        .onChange(of: announcementsEnabled) { _, _ in persist() }
        .onChange(of: marketplaceEnabled)   { _, _ in persist() }
    }

    private func persist() {
        guard !isLoading else { return }
        let prefs = SettingsService.NotificationPrefs(
            notifyKnots:         groupsEnabled,
            notifyMessages:      messagesEnabled,
            notifyAnnouncements: announcementsEnabled,
            notifyMarketplace:   marketplaceEnabled
        )
        Task { try? await SettingsService.updateNotificationPrefs(prefs) }
    }
}
