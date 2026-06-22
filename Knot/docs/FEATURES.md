# Knot — Feature Reference

Status legend: ✅ Done · 🔧 Partial / has known issues · ❌ Not built

---

## Auth

| Feature | Status | Notes |
|---------|--------|-------|
| Email + password sign-up | ✅ | Includes email verification gate |
| Email + password sign-in | ✅ | |
| Google OAuth | ✅ | Via `ASWebAuthenticationSession`, redirect `knot://auth/callback` |
| Password reset | ✅ | Deep link `knot://auth/callback` with recovery token |
| Password strength validation | ✅ | `PasswordPolicy.swift` |
| Account banned state | ✅ | `BannedAccountView` shown on login |
| Sign-out | ✅ | Clears all local state via `clearAllData()` |

---

## Onboarding

| Feature | Status | Notes |
|---------|--------|-------|
| Name collection | ✅ | |
| Birthday collection | ✅ | |
| Address collection | ✅ | Saved to Supabase via `ProfileService.updateAddress()` |
| Interests / categories | ✅ | |
| Welcome screen (first launch) | ✅ | `WelcomeToKnotSheet`, shown once via `@AppStorage("hasSeenWelcome")` |

---

## Profile

| Feature | Status | Notes |
|---------|--------|-------|
| View own profile | ✅ | `ProfileView.swift` |
| Edit profile (name, bio, photo, address, privacy) | ✅ | `EditProfileView.swift` |
| Profile image upload | ✅ | `ProfileService.uploadAvatar()` → Storage |
| Privacy controls (is_private, show_knots, show_listings, show_connections) | ✅ | |
| View another user's profile | ✅ | `UserProfileView` — fetches real data on appear |
| Other user's profile image | ✅ | `AsyncImage` via `connectionAvatarURLs` |
| Other user's bio | ✅ | Loaded from `ProfileService.fetch()` in `UserProfileView` |

---

## Connections

| Feature | Status | Notes |
|---------|--------|-------|
| Send connection request | ✅ | |
| Accept / decline request | ✅ | |
| Remove connection | ✅ | |
| Connection list | ✅ | |
| Pending requests view | ✅ | |
| UUID-based connection lookup | ✅ | `connectionProfiles[UUID]` → name |
| Avatar URL cache | ✅ | `connectionAvatarURLs[UUID]` → URL string |

---

## Knots (Groups)

| Feature | Status | Notes |
|---------|--------|-------|
| Browse public knots | ✅ | Filter by category, age group, size |
| Create a knot | ✅ | `CreateGroupView.swift` |
| Join a knot (open) | ✅ | |
| Join request (approval required) | ✅ | |
| Join form with custom questions | ✅ | Admin sets questions; applicants answer |
| Leave a knot | ✅ | |
| Admin: approve / reject join requests | ✅ | Creator **and** co-admins (parity) — gated by `is_knot_admin` RLS |
| Admin: kick members | ✅ | Creator and co-admins can kick directly |
| Admin: send announcements | ✅ | Creator and co-admins (`Send Alert to Members`) |
| Admin: promote to co-admin | ✅ | **Creator only** — co-admins send a request to the creator (ownership action) |
| Delete knot | ✅ | **Creator only** (ownership action) |
| Co-admin = group chat admin | ✅ | Knot admins can edit the knot's group chat (name/description/photo) — `conversations_update` RLS allows `is_knot_admin(source_knot_id)` |
| Admin: send announcement | ✅ | |
| Admin: manage knot settings | ✅ | `ManageGroupView.swift` |
| Knot group chat (all members) | ✅ | Via `find_or_create_knot_chat` RPC |
| Non-admin: open knot group chat | ✅ | Same button as admin, routes to group |
| Rate a knot (1–5 stars) | ✅ | Members/admins only. 3-dot menu → "Rate this Knot" → `RateKnotSheet`. Upserts into `knot_ratings` |
| Average rating display | ✅ | Green 5-star template under knot name + `(count)`, snapped to nearest 0.5 (`KnotStarRow`) |

---

## Messages

| Feature | Status | Notes |
|---------|--------|-------|
| 1-to-1 DM | ✅ | |
| Group chat | ✅ | |
| Send text message | ✅ | |
| Send image | ✅ | Custom flow (`ChatPhotoFlow.swift`): photo icon → "Add photos" bottom sheet → custom multi-select gallery (`ChatGalleryPicker`) or AVFoundation camera (`ChatCameraView`, photo + video modes) → staged tray above composer → send. Each staged photo posts as its own image message |
| Star a message | ✅ | |
| Favourite a conversation | ✅ | Swipe row from the left → Favourite/Unfavourite (swipe right deletes). `setConversationFavourite` |
| Unread count badge | ✅ | |
| Realtime message delivery | ✅ | Supabase Realtime channel |
| Message filter (all / favourites / connections) | ✅ | |
| Search conversations | ✅ | |
| Profile image in conversation list | ✅ | `AsyncImage` via `connectionAvatarURLs` |
| Profile image in chat header | ✅ | Same |
| Leave group chat | ✅ | |
| Edit group chat (name, description, photo) | ✅ | Admin/creator only — edit circle on the group avatar → `EditGroupChatView`. Photo persists via `group_image_url` |
| Reply to message | ❌ | Removed — UI was too noisy |
| Message search within a chat | ❌ | Not built |
| Read receipts per message | 🔧 | DB has `status` column, UI shows basic status only |

---

## Hub (Marketplace)

| Feature | Status | Notes |
|---------|--------|-------|
| Browse all listings | ✅ | Grid layout, refreshes on tab open |
| Filter by type (items / services / ads) | ✅ | |
| Search listings | ✅ | |
| Create listing (item / service / advertisement) | ✅ | Image upload — library or in-app camera ("Take Photo" / "Choose from Library") |
| Edit own listing | ✅ | `EditListingView` |
| Delete listing (soft-delete) | ✅ | Sets `is_active = false` |
| My Listings filter | ✅ | |
| Listing detail view | ✅ | |
| Buy a listing | ✅ | `PurchaseFlow.swift` — Stripe PaymentSheet |
| Payout setup (seller) | ✅ | `WalletPaymentsView.swift` — Stripe Connect |
| Order tracking | ✅ | `TransactionFlow.swift` — status timeline |
| Meetup coordination | ✅ | Propose location + date |
| Reviews after completion | ✅ | Buyer and seller can leave reviews |
| Payout banner (if no bank linked) | ✅ | Dismissible nudge in Hub header |

---

## Alerts (Announcements)

| Feature | Status | Notes |
|---------|--------|-------|
| View announcements from joined knots | ✅ | |
| Realtime new announcement delivery | ✅ | |
| Dismiss individual announcement | ✅ | Persisted in `UserDefaults` |
| Dismiss all announcements | ✅ | |
| Dismissed alerts don't reappear | ✅ | Filtered on load via dismissed ID set |
| Pin announcement | ✅ | |
| Persistent "Getting Started" guide | ✅ | Always shown at top of Alerts tab |

---

## Search

| Feature | Status | Notes |
|---------|--------|-------|
| Search users by name | ✅ | `ProfileService.search()` |
| Search knots | ✅ | |
| Keyboard dismissal | ✅ | `.scrollDismissesKeyboard(.interactively)` |

---

## Settings

| Feature | Status | Notes |
|---------|--------|-------|
| Privacy settings | ✅ | `PrivacySecurityView.swift` |
| Notification settings | ✅ | `NotificationsSettingsView.swift` |
| Help & Support | ✅ | `HelpSupportView.swift` |
| Change password | ✅ | |
| Delete account | ❌ | Not built |

---

## Dark Mode

All views use semantic colour tokens (`Color.primary`, `Color(.systemBackground)`, etc.). Dark mode is fully supported. If any text appears black in dark mode, find the hardcoded `.black` or `.white` and replace with `.primary` / `Color(.systemBackground)`.

---

## Known Issues / TODOs

- `otherUserPrivacy` dictionary in `UserProfile` still contains hardcoded mock entries (`"Ahmad Khalid"`, `"Lin Hui"`, `"David Chen"`). Now that `UserProfileView` fetches real privacy settings, this dictionary is unused but should be cleaned up.
- `makeSampleConversations()` is still in `MessagesView.swift`. It's not called anywhere in production but should be removed.
- Connection count stat in `UserProfileView` shows `—` because the DB doesn't expose a connection count for other users. Could be solved with an RPC or a denormalised column.
- Order `knotFeeCents` and `payoutCents` are generated columns in Postgres — read-only. Never try to set them in an INSERT or UPDATE.
