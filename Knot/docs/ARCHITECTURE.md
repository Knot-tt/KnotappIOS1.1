# Knot — Architecture

---

## App Entry Flow

```
KnotApp (@main)
  └── RootView
        ├── isCheckingSession → blank screen
        ├── isBanned          → BannedAccountView
        ├── isPasswordRecovery → PasswordResetView
        ├── isLoggedIn        → MainTabView
        └── else              → LoginView
```

`AuthManager` (an `@StateObject`) owns auth state. It's injected via `.environmentObject(authManager)` and available throughout the app.

---

## State Management

### UserProfile

The single source of truth for all app data. It is:
- An `@Observable` class (not a struct)
- Created once in `MainTabView` as `@State private var profile`
- Injected into the entire view tree via `.environment(profile)`
- Accessed in views with `@Environment(UserProfile.self) var profile`

**Rule:** There is exactly one `UserProfile` instance alive at any time. Never create another.

### AuthManager

An `ObservableObject` (`@StateObject`) owned by `KnotApp`. Manages:
- Session state (`isLoggedIn`, `isCheckingSession`)
- Auth operations (sign in, sign up, sign out, OAuth, password reset)
- A callback `onSignedIn` — called by `MainTabView.task` to trigger `profile.loadFromSupabase()`

### Data loading lifecycle

```
MainTabView.task
  → authManager.onSignedIn fires
  → profile.loadFromSupabase(userID:)
      → loadConnections()
      → loadKnots()
      → loadConversations()
      → loadAnnouncements()
      → loadListings()
      → loadOrders()
```

`MainTabView.onChange(of: scenePhase)` re-runs all loads when the app returns from background.

---

## File Responsibilities

### `UserProfile.swift`
All app state + business logic. Organised by phase:
- **Phase 1:** Own profile (name, bio, image, address, privacy settings)
- **Phase 2:** Connections (dbConnections, connectionProfiles, connectionAvatarURLs)
- **Phase 3:** Knots (createdGroups, publicKnots, joinedGroupIDs)
- **Phase 4:** Conversations + messages (conversations, realtime subscription)
- **Phase 5:** Announcements (announcements, realtime subscription)
- **Phase 6:** Shop (allListings, myListings computed)
- **Phase 7:** Orders (orders)

### `SupabaseManager.swift`
Service layer — no state, just async throwing functions. Service enums:

| Enum | Responsibility |
|------|---------------|
| `ProfileService` | CRUD for profiles, avatar upload, search |
| `ConnectionService` | Send / accept / decline / remove connections |
| `KnotService` | Create / update / delete knots, manage members |
| `MessagingService` | Conversations, participants, messages, realtime |
| `ShopService` | Listings CRUD, soft-delete |
| `OrderService` | Order status transitions |
| `AnnouncementService` | Fetch/create announcements, mark read |

### `SupabaseModels.swift`
`Codable` DB structs — one per table. These are pure data containers, no logic. Naming convention: `DB` prefix (e.g. `DBProfile`, `DBKnot`).

### `CommunityModels.swift`
UI-layer models for knots and orders (e.g. `CommunityGroup`, `KnotOrder`). These are separate from the DB structs — richer, with computed properties.

### `Configuration.swift`
Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `Config.xcconfig` at runtime. Creates the `supabase` client used everywhere.

---

## Navigation

- **Tab navigation:** `TabView` with `AppTab` enum. Views call `profile.selectedTab = .messages` to programmatically switch tabs.
- **Sheet navigation:** Most secondary screens (profile view, listing detail, chat, knot detail) are presented as `.sheet(item:)` or `.sheet(isPresented:)`.
- **NavigationStack:** Used inside the Home, Knots, and Messages tabs for push navigation. Sheets that need internal navigation also wrap in `NavigationStack`.

---

## Realtime

Two Supabase Realtime channels are active while logged in:

| Channel | Table | Events | Handler |
|---------|-------|--------|---------|
| `messaging` | `messages`, `conversation_participants` | INSERT, UPDATE | `startMessagingRealtime()` → appends new messages, updates unread counts |
| `announcements` | `announcements` | INSERT | `startAnnouncementRealtime()` → appends new announcements |

Channels are started in `loadFromSupabase()` and cancelled in `clearAllData()` (on sign-out).

---

## Auth Flow

### Email / Password
1. `AuthManager.signIn(email:password:)` → `supabase.auth.signIn`
2. Session is persisted by the Supabase SDK automatically
3. On next launch, `supabase.auth.session` restores the session without a network call

### Google OAuth
1. `AuthManager.signInWithGoogle()` → opens Safari via `ASWebAuthenticationSession`
2. Redirect URL: `knot://auth/callback`
3. `KnotApp.onOpenURL` catches the callback and calls `authManager.handleCallbackURL(url)`

### Sign-up flow
`SignUpView` → name → email + password → email verification → address → `onboardingComplete = true` → `MainTabView`

---

## Image Handling

### Profile images
- Upload: `ProfileService.uploadAvatar(data:)` → `profile-images/{uid}/avatar.jpg`
- Display own: `profile.profileImage` (UIImage, loaded on startup)
- Display others: `connectionAvatarURLs[uuid]` → `AsyncImage(url:)`

### Group images
- Stored in `knot-images/{conversationID}/group.jpg`
- Loaded as `UIImage` and stored on `Conversation.groupImage`

### Listing images
- Stored in `listing-images/{listingID}/{index}.jpg`
- Displayed via `AsyncImage(url:)` using URLs in `ShopListing.imageURLs`

---

## Known Patterns & Gotchas

### Silent decode failures
If a Supabase fetch returns an empty array unexpectedly:
1. Check RLS policies — the most common cause
2. Check for non-optional fields in the DB struct that have NULL in the DB
3. Check that any explicit `SELECT` column list includes ALL non-optional fields

The `onboarding_complete` column on `profiles` has been a recurring source of this — always include it.

### Soft delete
`ShopService.delete()` sets `is_active = false` rather than deleting the row. `fetchActive()` only returns `is_active = true` rows. Sellers can still see their own inactive listings (RLS allows it) but they won't appear in the main Hub feed.

### Group chat creation
Never create a `Conversation` with a locally-generated UUID for a group chat. Use `MessagingService.findOrCreateKnotChat(knotID:knotName:)` which calls the `find_or_create_knot_chat` RPC. This returns a real DB-persisted UUID.

### connectionProfiles vs connectionAvatarURLs
Both caches are populated by `ProfileService.fetchMultiple()`. Any code that calls `fetchMultiple` should populate both:
```swift
for p in profiles {
    connectionProfiles[p.id] = p.name
    if let url = p.profileImage { connectionAvatarURLs[p.id] = url }
}
```
Always clear both in `clearAllData()` on sign-out.
