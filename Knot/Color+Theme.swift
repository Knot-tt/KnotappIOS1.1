import SwiftUI
import UIKit

// MARK: - Knot Brand Color Tokens
//
// Every semantic color resolves automatically for light and dark mode via
// UIColor(dynamicProvider:). Add new tokens here — never hardcode colors
// in view files. Use Color.knotXxx in SwiftUI, UIColor.knotXxx in UIKit.
//
// ┌─────────────────────┬──────────────┬──────────────┐
// │ Token               │ Light        │ Dark (OLED)  │
// ├─────────────────────┼──────────────┼──────────────┤
// │ knotBackground      │ #F2EDE6      │ #060708      │  near-pure black
// │ knotSurface         │ #FFFFFF      │ #141518      │  lifted charcoal (cards, tab bar, sheets)
// │ knotWell            │ #EDE8E0      │ #1E2127      │  inset wells, search fields, received bubbles
// │ knotBorder          │ #E2DACE      │ #26292E      │  hairline borders
// │ knotDivider         │ #DDD8D0      │ #1F2125      │  dividers
// │ knotAccent          │ #2D9E53      │ #34AF60      │  vivid green — CTAs, badges, sent bubbles
// │ knotOnAccent        │ #FFFFFF      │ #06130B      │  text / icons sitting on accent green
// │ knotInk             │ #1A1714      │ #F4F5F6      │  primary text
// │ knotMuted           │ #8A8175      │ #8B8F96      │  secondary text
// │ knotPlaceholder     │ #A89E8E      │ #5E626A      │  tertiary / placeholder text
// │ knotAvatarBg        │ #DDD8D0      │ #2A2D31      │  neutral avatar / group icon background
// └─────────────────────┴──────────────┴──────────────┘

extension UIColor {

    // MARK: Backgrounds

    /// Page / screen background — warm cream in light, near-pure OLED black in dark.
    static let knotBackground = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#060708")
            : UIColor(hex: "#F2EDE6")
    }

    /// Cards, sections, sheets, and the tab bar — white in light, lifted charcoal in dark.
    static let knotSurface = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#141518")
            : UIColor(hex: "#FFFFFF")
    }

    /// Inset wells — search fields, chips, image placeholders, received chat bubbles.
    static let knotWell = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#1E2127")
            : UIColor(hex: "#EDE8E0")
    }

    // MARK: Borders & Dividers

    /// Hairline borders and card outlines.
    static let knotBorder = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#26292E")
            : UIColor(hex: "#E2DACE")
    }

    /// Dividers (slightly darker than border).
    static let knotDivider = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#1F2125")
            : UIColor(hex: "#DDD8D0")
    }

    // MARK: Accent

    /// Primary action color — vivid green. Used for CTAs, active tab, unread badges, sent bubbles.
    static let knotAccent = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#34AF60")
            : UIColor(hex: "#4A7A5D")
    }

    /// Text / icons sitting on top of the accent green (dark green-black in dark, white in light).
    static let knotOnAccent = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#06130B")
            : UIColor(hex: "#FFFFFF")
    }

    // MARK: Text

    /// Primary text / ink — near-white in dark, near-black in light.
    static let knotInk = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#F4F5F6")
            : UIColor(hex: "#1A1714")
    }

    /// Secondary / muted text.
    static let knotMuted = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#8B8F96")
            : UIColor(hex: "#8A8175")
    }

    /// Tertiary / placeholder text.
    static let knotPlaceholder = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#5E626A")
            : UIColor(hex: "#A89E8E")
    }

    // MARK: Misc

    /// Neutral avatar / group icon background — never the accent green.
    static let knotAvatarBg = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#2A2D31")
            : UIColor(hex: "#DDD8D0")
    }

    // MARK: - Hex initialiser (private)
    private convenience init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value   = UInt64(cleaned, radix: 16) ?? 0
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >>  8) & 0xFF) / 255
        let b = CGFloat( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - SwiftUI convenience wrappers

extension Color {
    /// Page / screen background.
    static let knotBackground  = Color(UIColor.knotBackground)
    /// Cards, sections, sheets, tab bar.
    static let knotSurface     = Color(UIColor.knotSurface)
    /// Inset wells — search fields, chips, received bubbles.
    static let knotWell        = Color(UIColor.knotWell)
    /// Hairline borders and card outlines.
    static let knotBorder      = Color(UIColor.knotBorder)
    /// Dividers.
    static let knotDivider     = Color(UIColor.knotDivider)
    /// Primary action — vivid green. CTAs, active state, sent bubbles, badges.
    static let knotAccent      = Color(UIColor.knotAccent)
    /// Text / icons on top of the accent green.
    static let knotOnAccent    = Color(UIColor.knotOnAccent)
    /// Primary text / ink.
    static let knotInk         = Color(UIColor.knotInk)
    /// Secondary / muted text.
    static let knotMuted       = Color(UIColor.knotMuted)
    /// Tertiary / placeholder text.
    static let knotPlaceholder = Color(UIColor.knotPlaceholder)
    /// Neutral avatar / group icon background.
    static let knotAvatarBg    = Color(UIColor.knotAvatarBg)
}
