# Knot — Design System

The design philosophy is Apple-inspired: clean, minimal, purposeful. Every element earns its place. Nothing decorative, nothing harsh.

---

## Core Philosophy

- **Calm and refined.** The app should feel like it belongs next to the iOS system apps.
- **Nothing sharp or loud.** No heavy drop shadows, no rainbow gradients, no aggressive accent usage.
- **Generous whitespace.** Things should breathe. Padding is intentional.
- **Function first, beauty second — but both matter.**
- **If it looks like a free Figma kit, push further.**

---

## Colour System

All colours are defined in `Color+Theme.swift` as `UIColor` dynamic providers and bridged to SwiftUI `Color` extensions. They adapt to dark mode automatically.

### Brand palette

| Light mode hex | Dark mode hex | Role |
|----------------|---------------|------|
| `#F2EDE6` | `#1A1714` | Page background |
| `#FFFFFF` | `#262019` | Card / sheet surface |
| `#4A7A5D` | `#6FA782` | Primary accent (brand green) |
| `#1A1714` | `#F2EDE6` | Primary text (ink) |
| `#8A8175` | `#A89E8E` | Muted / secondary text |
| `#A89E8E` | `#6E6557` | Placeholder text |
| `#E2DACE` | `#382F26` | Borders / dividers |

### Semantic tokens (always use these — never raw hex or system grays)

| Token | SwiftUI | Usage |
|-------|---------|-------|
| `Color.knotBackground` | Page / screen background | `.ignoresSafeArea()` behind all content |
| `Color.knotSurface` | Cards, sheets, input fields | Any elevated surface |
| `Color.knotAccent` | Primary action / brand colour | Buttons, active states, badges, tints |
| `Color.knotInk` | Primary text | When `.primary` would not adapt correctly |
| `Color.knotMuted` | Secondary / caption text | Subtitles, metadata |
| `Color.knotPlaceholder` | TextField placeholder | Pass via `.foregroundColor` on prompt |
| `Color.knotBorder` | Borders, dividers, separators | `stroke`, `Rectangle().fill()` |

### Status / semantic accent colours (kept intentional, not brand)

| Colour | Usage |
|--------|-------|
| `.green` | "Free" price label, "Connected" status |
| `.orange` | Advertisement badge, warning nudge, star ratings |
| `.red` / `.role(.destructive)` | Destructive actions only |
| `.secondary` | Pending / clock states |

### What to never do

- `.foregroundColor(.black)` or `.foregroundColor(.white)` — invisible in one mode
- `.background(Color.black)` — same issue
- Hardcoded hex colours — always use the semantic token
- `Color(.systemGray6)` / `Color(.systemGray4)` etc. — replaced by `knotBackground` / `knotBorder`
- Raw `.blue` as brand accent — use `Color.knotAccent`

---

## Typography

SF Pro (system font) throughout. No custom fonts.

### Scale

| Role | SwiftUI |
|------|---------|
| Screen title (large) | `.font(.system(size: 34, weight: .bold))` |
| Section title | `.font(.system(size: 22, weight: .bold))` |
| Card title | `.font(.subheadline).fontWeight(.semibold)` |
| Body | `.font(.body)` |
| Caption / metadata | `.font(.caption)` |
| Tiny label / badge | `.font(.caption2).fontWeight(.bold)` |

### Rules

- Screen titles are left-aligned, large, bold.
- Inline titles use `.navigationBarTitleDisplayMode(.inline)`.
- Limit line lengths — use `.lineLimit()` and `.multilineTextAlignment(.center)` where appropriate.
- Never use all-caps styling manually — let the system handle it.

---

## Spacing

Use multiples of 4. Common values:

| Context | Value |
|---------|-------|
| Screen horizontal padding | `16` |
| Card internal padding | `12–16` |
| Section gap (VStack) | `24` |
| Item gap within a section | `8–12` |
| Small gap (label + value) | `4–6` |
| Bottom padding (above tab bar) | `100` |

---

## Shapes & Surfaces

### Corner radii

| Element | Radius |
|---------|--------|
| Full cards / sheets | `16` |
| Buttons / input fields | `12` |
| Small badges / pills | `8` or `.clipShape(Capsule())` |
| Avatars | `.clipShape(Circle())` |
| Image thumbnails | `10` |

### Cards

Standard card pattern:
```swift
VStack { ... }
.background(Color.knotSurface)
.cornerRadius(16)
.overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.knotBorder, lineWidth: 1))
```

Use `Color.knotBackground` as the page background behind cards.

### Grid cards (GroupCard / ShopItemCard)

Two-column grid cards have a fixed image area and a fixed-height info strip:
- Image area fills the top ~65% of the card
- A `Rectangle().fill(Color.knotBorder).frame(height: 1.5)` separator sits between image and info
- Info strip text is horizontally and vertically centred within its fixed height frame
- Padding: `.padding(.horizontal, 8)` only (no top/bottom to preserve centering in the frame)

### Buttons

**Primary (filled):**
```swift
Text("Action")
    .fontWeight(.semibold)
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.knotAccent)
    .cornerRadius(12)
```

**Secondary (outlined or ghost):**
```swift
Text("Action")
    .foregroundColor(.primary)
    .padding(.horizontal, 14).padding(.vertical, 8)
    .background(Color.knotSurface)
    .cornerRadius(10)
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.knotBorder, lineWidth: 1))
```

**Destructive:**
Use `.role(.destructive)` on `Button` — the system applies red automatically.

---

## Avatars

### User avatar (letter fallback)
```swift
ZStack {
    Circle().fill(Color.knotAccent).frame(width: 44, height: 44)
    if let img = profileImage {
        Image(uiImage: img).resizable().scaledToFill()
            .frame(width: 44, height: 44).clipShape(Circle())
    } else {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
    }
}
```

### Other user avatar (async from URL)
```swift
if let url = URL(string: avatarURLString) {
    AsyncImage(url: url) { phase in
        if let img = phase.image {
            img.resizable().scaledToFill().frame(...).clipShape(Circle())
        } else {
            // fallback letter circle
        }
    }
}
```

### Group chat avatar
```swift
ZStack {
    Circle().fill(Color.knotMuted).frame(width: 50, height: 50)
    Image(systemName: "person.3.fill")
        .font(.system(size: 18)).foregroundColor(.white)
}
```

---

## List / Feed Rows

Standard row pattern (used in Messages, Knots, connections):
- Avatar on the left (44–50pt circle)
- Title + subtitle stacked
- Right-side metadata (time, badge, chevron)
- Minimum 16pt horizontal padding
- Rows separated by `Divider()` or a list separator

---

## Sheets & Navigation

- Sheets use `NavigationStack` inside with `.navigationTitle()` and a "Close" `ToolbarItem(.cancellationAction)`.
- Full-screen content uses `.navigationBarTitleDisplayMode(.large)` on main views, `.inline` on sheets.
- Always provide a way to dismiss — never trap users.
- Sheets that allow editing: provide a "Save" / "Done" button. Disable it while saving (`isSaving` state).

---

## Dark Mode Rules

1. Page backgrounds → `Color.knotBackground.ignoresSafeArea()`
2. Card / surface backgrounds → `Color.knotSurface`
3. All text → `.primary` or `.secondary` (never `.black` / `.white`)
4. Borders / dividers → `Color.knotBorder`
5. Image overlays / scrims → `Color.black.opacity(0.55)` is acceptable (scrim over a photo, not text)
6. Filled primary buttons → `Color.knotAccent` background + `.white` text
7. Icons → `.foregroundColor(.primary)` or `Color.knotAccent` for active/brand icons

Run the app in dark mode simulator after any UI changes to verify.

---

## Tab Bar

5 tabs, left to right: **Hub · Alerts · Home · Knots · Messages**

- `.tabBarMinimizeBehavior(.onScrollDown)` — tab bar hides when scrolling down.
- Home is the default selected tab (centre position).
- Tab icons use SF Symbols.

---

## Keyboard Handling

- All scrollable views: `.scrollDismissesKeyboard(.interactively)`
- Input fields: `.submitLabel(.send)` on message inputs
- Text-heavy forms: `.scrollDismissesKeyboard(.interactively)` on the wrapping `ScrollView`
