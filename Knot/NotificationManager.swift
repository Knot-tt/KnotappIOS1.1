import Foundation
import UserNotifications
import UIKit
import Supabase

enum NotificationRoute: Equatable, Sendable {
    case conversation(UUID)
    case alerts
    case orders(String?)
    case hub
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Set by MainTabView once the profile is ready. It switches to the right
    /// tab/screen for a notification tap.
    var onOpenRoute: ((NotificationRoute) -> Void)?
    /// Holds a tapped-notification target that arrived before the handler was
    /// registered (e.g. cold launch from a notification). Drained on register.
    private var pendingRoute: NotificationRoute?
    private var latestDeviceToken: String?

    override init() {
        super.init()
        // Become the notification center delegate so we can show banners
        // while the app is in the foreground.
        UNUserNotificationCenter.current().delegate = self
    }

    /// MainTabView calls this once `profile` exists. Wires the open handler and
    /// immediately replays any notification tap that arrived before we were ready.
    func registerOpenHandler(_ handler: @escaping (NotificationRoute) -> Void) {
        onOpenRoute = handler
        if let pending = pendingRoute {
            pendingRoute = nil
            handler(pending)
        }
    }

    private func route(_ route: NotificationRoute) {
        if let handler = onOpenRoute {
            handler(route)
        } else {
            // App launched cold from the tap — stash until the handler registers.
            pendingRoute = route
        }
    }

    // Called when a push arrives while the app is in the foreground.
    // Suppress foreground presentation so users don't get banners/sounds
    // while they're already inside the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    // Called when the user TAPS a notification. Reads the route keys we attach
    // to pushes and opens the matching area of the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = Self.route(from: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let route {
                self.route(route)
            }
            completionHandler()
        }
    }

    nonisolated private static func route(from userInfo: [AnyHashable: Any]) -> NotificationRoute? {
        if let convString = stringValue(userInfo["conversation_id"]),
           let id = UUID(uuidString: convString) {
            return .conversation(id)
        }

        let target = stringValue(userInfo["target"])?.lowercased()
        if target == "orders" || stringValue(userInfo["order_id"]) != nil {
            return .orders(stringValue(userInfo["order_id"]))
        }
        if target == "alerts" || stringValue(userInfo["announcement_id"]) != nil {
            return .alerts
        }
        if target == "hub" {
            return .hub
        }
        return nil
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let uuid as UUID:
            return uuid.uuidString
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    func requestPermission() async {
        print("[NotificationManager] requestPermission called")
        let current = await UNUserNotificationCenter.current().notificationSettings()
        print("[NotificationManager] current auth status: \(current.authorizationStatus.rawValue)")
        do {
            let granted: Bool
            switch current.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                granted = true
            case .notDetermined:
                granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
            case .denied:
                granted = false
            @unknown default:
                granted = false
            }
            print("[NotificationManager] permission granted: \(granted)")
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                await retrySavingDeviceToken()
            }
        } catch {
            print("[NotificationManager] Permission request error: \(error)")
        }
    }

    func saveToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        latestDeviceToken = token
        print("[NotificationManager] Device token: \(token)")
        await persistToken(token)
    }

    func retrySavingDeviceToken() async {
        if let latestDeviceToken {
            await persistToken(latestDeviceToken)
        }
    }

    private func persistToken(_ token: String) async {
        guard let userID = try? await supabase.auth.session.user.id else {
            print("[NotificationManager] No user session yet; will retry token save after sign-in")
            return
        }
        do {
            try await supabase
                .from("device_tokens")
                .upsert([
                    "user_id"   : userID.uuidString,
                    "token"     : token,
                    "platform"  : "apns",
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ], onConflict: "user_id")
                .execute()
            print("[NotificationManager] Token saved for user \(userID)")
        } catch {
            print("[NotificationManager] Token save error: \(error)")
        }
    }

    static func notify(
        userID: UUID,
        title: String,
        body: String,
        conversationID: UUID? = nil,
        target: String? = nil,
        orderID: String? = nil,
        announcementID: UUID? = nil
    ) async {
        do {
            var payload: [String: String] = [
                "user_id": userID.uuidString,
                "title"  : title,
                "body"   : body
            ]
            // Carried into the APNs payload so a tap can deep-link into the app.
            if let conversationID {
                payload["target"] = target ?? "conversation"
                payload["conversation_id"] = conversationID.uuidString
            } else if let target {
                payload["target"] = target
            }
            if let orderID { payload["order_id"] = orderID }
            if let announcementID { payload["announcement_id"] = announcementID.uuidString }
            try await supabase.functions.invoke(
                "send-notification",
                options: .init(body: payload)
            )
        } catch {
            print("[NotificationManager] notify error: \(error)")
        }
    }

    func clearToken() async {
        guard let userID = try? await supabase.auth.session.user.id else { return }
        try? await supabase
            .from("device_tokens")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .execute()
        print("[NotificationManager] Token cleared")
    }
}
