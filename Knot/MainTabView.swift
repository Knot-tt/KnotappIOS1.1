//
//  MainTabView.swift
//  Knot
//

import SwiftUI
import Auth

// MARK: - Tab Enum
enum AppTab { case buy, alerts, home, groups, messages }

// MARK: - Main Tab View

struct MainTabView: View {
    let onLogout: () -> Void
    @State private var profile: UserProfile
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastPhase: ScenePhase = .active

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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Only reload when returning from background — not from inactive
            // (inactive fires whenever system menus, pickers, or alerts appear)
            if newPhase == .active && oldPhase == .background {
                Task { await profile.loadConnections() }
            }
            lastPhase = newPhase
        }
        .task {
            // Wire auth → profile load. Called once when the tab view appears.
            // AuthManager fires this on every subsequent sign-in too.
            authManager.onSignedIn = { [weak profile] user in
                await profile?.loadFromSupabase(userID: user.id)
            }
            // If already signed in (restored session), load now.
            if let user = authManager.currentUser {
                await profile.loadFromSupabase(userID: user.id)
            }
        }
    }
}
