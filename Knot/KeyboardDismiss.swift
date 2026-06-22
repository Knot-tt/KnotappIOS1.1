import SwiftUI
import UIKit

// MARK: - Global keyboard dismiss
/// Installs a tap-recognizer on every window so a tap anywhere outside a
/// TextField dismisses the keyboard — no per-view wiring required.
///
/// Robust install path:
///  1. Try immediately for any window that's already up.
///  2. Observe `UIWindow.didBecomeKeyNotification` so any window created later
///     (new scene, sheet hosting a presentation, etc.) also gets the gesture.
enum KeyboardDismiss {

    private static var didStart = false

    /// Screen regions where a tap must NOT dismiss the keyboard — e.g. the
    /// message input bar, so tapping "Send" doesn't bounce the keyboard down
    /// and immediately back up. Views register via `KeepKeyboardOnTap`. Weak
    /// refs so entries auto-clear when the SwiftUI view goes away.
    static let keepUpRegions = NSHashTable<UIView>.weakObjects()

    /// Call once from `RootView.onAppear`.
    static func installGlobalTap() {
        if didStart { return }   // notification observer registered once per process
        didStart = true

        // Install on any windows already created (e.g. when the app re-opens).
        for window in allKnownWindows() { install(on: window) }

        // Listen for any future windows.
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object : nil,
            queue  : .main
        ) { notification in
            if let win = notification.object as? UIWindow {
                install(on: win)
            }
        }
    }

    /// Force an immediate retry — useful if you just presented a new sheet /
    /// fullScreenCover that might have spawned a new internal window.
    static func refresh() {
        for window in allKnownWindows() { install(on: window) }
    }

    // MARK: helpers

    /// Only the app's own window is eligible. Keyboard and text-effect windows
    /// ALSO fire `didBecomeKeyNotification` when the keyboard appears — if we
    /// install the tap on one of those, every on-screen keyboard key press is
    /// seen as a tap and resigns first responder, so you can't type past the
    /// first character. The app window sits at `.normal`; system windows sit far
    /// above it, so the level check filters them out (the class-name check is a
    /// belt-and-suspenders guard).
    private static func isEligible(_ window: UIWindow) -> Bool {
        guard window.windowLevel == UIWindow.Level.normal else { return false }
        let className = NSStringFromClass(type(of: window))
        return !className.contains("Keyboard") && !className.contains("TextEffects")
    }

    private static func install(on window: UIWindow) {
        // TEMP (diagnostic): global tap-to-dismiss disabled to confirm whether
        // this gesture is what steals first-responder after the first keystroke.
        // If typing works with this in place, this recognizer is the culprit and
        // we re-add tap-to-dismiss the safe (SwiftUI-native) way.
        return

        guard isEligible(window) else { return }
        if window.gestureRecognizers?.contains(where: { $0 is KeyboardDismissTap }) == true {
            return
        }
        let tap = KeyboardDismissTap()
        tap.addTarget(KeyboardDismissTarget.shared,
                      action: #selector(KeyboardDismissTarget.handleTap(_:)))
        tap.cancelsTouchesInView      = false   // don't swallow taps
        tap.delaysTouchesBegan        = false
        tap.delaysTouchesEnded        = false
        tap.requiresExclusiveTouchType = false
        tap.delegate                  = KeyboardDismissDelegate.shared
        window.addGestureRecognizer(tap)
    }

    private static func allKnownWindows() -> [UIWindow] {
        var windows: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            if let s = scene as? UIWindowScene {
                windows.append(contentsOf: s.windows)
            }
        }
        return windows
    }
}

// MARK: - Tap target (separate object so we don't capture the UIWindow weakly)
private final class KeyboardDismissTarget: NSObject {
    static let shared = KeyboardDismissTarget()

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // Both flavors — endEditing for the focused window, and the broadcast
        // resignFirstResponder for any nested responders SwiftUI may have.
        if let window = gesture.view as? UIWindow {
            window.endEditing(true)
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

/// Marker subclass so we don't double-install.
private final class KeyboardDismissTap: UITapGestureRecognizer {}

/// Lets every other gesture keep working — we only observe, never block.
/// Taps on buttons, switches, rows, and other controls dismiss the keyboard
/// while still allowing the control's own action to run. Taps inside text inputs
/// are ignored so moving the cursor or switching between fields behaves normally.
private final class KeyboardDismissDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissDelegate()

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var v: UIView? = touch.view
        while let view = v {
            if view is UITextField || view is UITextView { return false }
            v = view.superview
        }
        // Don't dismiss when the tap lands inside a registered "keep up" region
        // (e.g. the message input bar / Send button). SwiftUI Buttons aren't
        // UIControls, so the walk-up above can't catch them — we match by frame.
        if let window = touch.window {
            let point = touch.location(in: window)
            for region in KeyboardDismiss.keepUpRegions.allObjects where region.window != nil {
                if region.convert(region.bounds, to: window).contains(point) {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: - Keep-keyboard-up region marker
/// Place as a `.background(KeepKeyboardOnTap())` behind any bar (e.g. the chat
/// input bar) whose buttons should NOT dismiss the keyboard when tapped. It
/// registers its frame with the global recognizer and is non-interactive, so it
/// never interferes with the controls in front of it.
struct KeepKeyboardOnTap: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        KeyboardDismiss.keepUpRegions.add(v)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - SwiftUI convenience modifier
extension View {
    /// Adds a tap-anywhere keyboard dismiss to this view tree.  The global tap
    /// recognizer covers ~99% of cases — call this only on the rare screen
    /// that hosts non-window UI (e.g. UIKit-presented controllers).
    func dismissKeyboardOnTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
    }
}
