# Knot — Claude Code Context

This is the primary context file for the Knot iOS app. Read this first, then reference the `/docs` files for deeper detail.

---

## What Knot Is

A community platform for neighbourhoods. Users join local groups called **Knots**, message each other, sell/buy things in a marketplace (the **Hub**), and receive announcements from group admins. Think a neighbourhood super-app — community, commerce, and communication in one place.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS frontend | Swift / SwiftUI |
| Backend / DB | Supabase (Postgres + Auth + Storage + Realtime) |
| Payments | Stripe (PaymentSheet + Connect for payouts) |
| State management | `@Observable` (`UserProfile` class) passed via `.environment()` |
| Auth | Supabase Auth — email/password + Google OAuth |

---

## Project Structure

```
Knot/
├── CLAUDE.md                   ← you are here
├── docs/
│   ├── DESIGN.md               ← UI colours, typography, dark mode rules
│   ├── DATABASE.md             ← Supabase schema, RLS, query patterns
│   ├── ARCHITECTURE.md         ← file map, data flow, state management
│   └── FEATURES.md             ← feature status and known issues
│
├── KnotApp.swift               ← app entry, RootView, auth gate
├── MainTabView.swift           ← 5-tab shell, scene reload logic
├── Dashboard.swift             ← Home tab
├── AuthManager.swift           ← Supabase auth wrapper (@Observable)
├── UserProfile.swift           ← ALL app state + business logic (@Observable)
│
├── SupabaseManager.swift       ← All Supabase service enums (ProfileService, etc.)
├── SupabaseModels.swift        ← Codable DB structs (DBProfile, DBKnot, etc.)
├── Configuration.swift         ← reads Config.xcconfig for Supabase URL/key
│
├── MessagesView.swift          ← Messages tab + ChatView
├── Communityview.swift         ← Knots tab + UserProfileView
├── ShopView.swift              ← Hub tab (marketplace)
├── AnnouncementsView.swift     ← Alerts tab
├── ProfileView.swift           ← own profile sheet
├── EditProfileView.swift       ← profile editing
├── SearchView.swift            ← global search
├── CreateGroupView.swift       ← create a new Knot
├── ManageGroupView.swift       ← admin tools for a Knot
├── LoginView.swift             ← login screen
├── SignUpView.swift            ← signup + onboarding flow
│
├── PurchaseFlow.swift          ← buy flow (Stripe PaymentSheet)
├── TransactionFlow.swift       ← order management / timeline
├── WalletPaymentsView.swift    ← seller payout setup (Stripe Connect)
│
├── CommunityModels.swift       ← CommunityGroup, KnotOrder, etc. (UI models)
├── KnotIcon.swift              ← shared KnotIcon component
└── PasswordPolicy.swift        ← password validation rules
```

---

## State Architecture

Everything lives in `UserProfile` — a single `@Observable` class injected at the tab level via `.environment(profile)`. Views read it with `@Environment(UserProfile.self) var profile`.

**Never** create a second `UserProfile` instance. **Never** pass data down as copies — always read from the environment.

Key collections in `UserProfile`:
- `conversations: [Conversation]` — all chats
- `allListings: [ShopListing]` — marketplace listings
- `announcements: [Announcement]` — alerts tab
- `createdGroups / publicKnots / joinedGroupIDs` — knots
- `dbConnections: [DBConnection]` — connection graph
- `connectionProfiles: [UUID: String]` — UUID → name cache
- `connectionAvatarURLs: [UUID: String]` — UUID → profile image URL cache

---

## Data Flow

```
Supabase → DBModel (SupabaseModels.swift)
         → mapped to UI model in UserProfile
         → read by views via @Environment
```

Service calls are in `SupabaseManager.swift` as enums with static methods:
`ProfileService`, `ConnectionService`, `KnotService`, `MessagingService`, `ShopService`, `OrderService`, `AnnouncementService`

---

## Critical Rules

1. **Always include `onboarding_complete` in any explicit `SELECT` on `profiles`.** It is a non-optional `Bool` — omitting it from an explicit column list causes a silent decode failure and returns nothing. Use `select()` (no args = `*`) when possible.

2. **`ShopService.fetchActive()` filters `is_active = true`.** Soft-deleted listings set `is_active = false`. They exist in the DB but are invisible to the app.

3. **Group chat messages use a real Supabase conversation UUID** — obtained via the `find_or_create_knot_chat` RPC. Never generate a local UUID for a conversation that needs to persist.

4. **Dark mode:** never use `.black` or `.white` directly for text or backgrounds. Always use `.primary`, `.secondary`, `Color(.systemBackground)`, `Color(.systemGray6)`, etc.

5. **RLS is always on.** Every table has Row Level Security. If a fetch returns nothing unexpectedly, check RLS policies before debugging the Swift code.

6. **`connectionProfiles[uuid]`** gives a name. **`connectionAvatarURLs[uuid]`** gives the profile image URL. Both are populated by any `ProfileService.fetchMultiple()` call.

---

## Build / Dev Notes

- Secrets live in `Config.xcconfig` (gitignored). Use `Config.xcconfig.example` as the template.
- Recurring **SourceKit errors** ("Loading the standard library failed") are a cache issue — do **Cmd+Shift+K** then **Cmd+B** in Xcode to fix. They are not real build errors.
- Supabase project ID: `flwwgpgqoqntpdxygknj` (region: ap-northeast-1, Tokyo)
- Bundle ID / app name: **Knot**
- Current build: **1.0.2 (102)**

---

## Deeper Reference

- UI rules → `docs/DESIGN.md`
- Database schema → `docs/DATABASE.md`
- Full architecture → `docs/ARCHITECTURE.md`
- Feature status → `docs/FEATURES.md`
