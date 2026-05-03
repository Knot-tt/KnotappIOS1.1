import SwiftUI

// MARK: - Notifications Settings View
struct NotificationsSettingsView: View {
    @State private var groupsEnabled = true
    @State private var messagesEnabled = true
    @State private var announcementsEnabled = true
    @State private var marketplaceEnabled = false

    var body: some View {
        List {
            Section {
                Toggle("Knots", isOn: $groupsEnabled)
                Toggle("Messages", isOn: $messagesEnabled)
                Toggle("Alerts", isOn: $announcementsEnabled)
                Toggle("Marketplace", isOn: $marketplaceEnabled)
            } header: {
                Text("Notify me about")
            } footer: {
                Text("You can also manage notification settings in iOS Settings > Knot.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
