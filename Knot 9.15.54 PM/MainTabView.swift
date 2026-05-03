import SwiftUI

// MARK: - Tab Enum
enum AppTab { case buy, alerts, home, groups, messages }

// MARK: - Main Tab View (iOS 26 — native Liquid Glass)
struct MainTabView: View {
    let onLogout: () -> Void
    @State private var profile: UserProfile

    init(name: String, onLogout: @escaping () -> Void) {
        self.onLogout = onLogout
        _profile = State(initialValue: UserProfile(name: name))
    }

    var body: some View {
        TabView(selection: Binding(
            get: { profile.selectedTab },
            set: { profile.selectedTab = $0 }
        )) {
            Tab("Hub", systemImage: "tag", value: AppTab.buy) {
                ShopView()
            }
            Tab("Alerts", systemImage: "bell", value: AppTab.alerts) {
                AnnouncementsTabView()
            }
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack {
                    DashboardView(onLogout: onLogout)
                }
            }
            Tab("Knots", systemImage: "person.3", value: AppTab.groups) {
                NavigationStack {
                    CommunitiesView()
                }
            }
            Tab("Messages", systemImage: "message", value: AppTab.messages) {
                MessagesView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(profile)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

