# Knot — Database Reference

Supabase project: `flwwgpgqoqntpdxygknj` (ap-northeast-1, Tokyo)

---

## Tables

### `profiles`

One row per user. Created by `ProfileService.create()` right after auth sign-up.

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | matches `auth.uid()` |
| `name` | text NOT NULL | display name |
| `bio` | text NOT NULL DEFAULT '' | |
| `profile_image` | text | Storage public URL |
| `street / city / postal_code / country` | text | nullable address fields |
| `is_private` | bool NOT NULL DEFAULT false | |
| `show_knots` | bool NOT NULL DEFAULT true | |
| `show_listings` | bool NOT NULL DEFAULT true | |
| `show_connections` | bool NOT NULL DEFAULT true | |
| `stripe_customer_id` | text | set by Edge Function on first purchase |
| `stripe_connect_id` | text | set after Stripe Express onboarding |
| `onboarding_complete` | bool NOT NULL DEFAULT false | ⚠️ see critical note below |
| `created_at / updated_at` | timestamptz | |

**⚠️ Critical:** `onboarding_complete` is **non-optional** in `DBProfile`. Any explicit `SELECT` column list that omits it will cause a silent JSON decode failure — the entire fetch returns nothing. Always include it, or use bare `select()` to get `*`.

**RLS:** Users can read/write only their own row. `search()` uses an explicit safe column list that excludes address fields and Stripe IDs.

---

### `connections`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `requester_id` | uuid FK → profiles | |
| `recipient_id` | uuid FK → profiles | |
| `status` | text | `'pending'` \| `'accepted'` \| `'declined'` |
| `created_at / updated_at` | timestamptz | |

**RLS:** Only the requester or recipient can see/modify a row.

---

### `knots`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `creator_id` | uuid FK → profiles | |
| `name / description / category / location` | text NOT NULL | |
| `image_url` | text | Storage public URL |
| `is_public` | bool | |
| `is_event` | bool | |
| `requires_approval` | bool | join requests needed |
| `is_connections_only` | bool | |
| `hide_location_from_non_members` | bool | |
| `max_members` | int | nullable = unlimited |
| `age_group` | text | `'all'` \| `'youth'` \| `'adults'` \| `'seniors'` |
| `min_age / max_age` | int | |
| `is_paid` | bool | |
| `payment_type` | text | `'one_time'` \| `'monthly'` |
| `price_cents` | int | |
| `member_count` | int | maintained by trigger |
| `rating_sum` | int NOT NULL DEFAULT 0 | sum of all star ratings — maintained by `knot_ratings_sync` trigger |
| `rating_count` | int NOT NULL DEFAULT 0 | number of ratings — average = `rating_sum / rating_count` |
| `created_at / updated_at` | timestamptz | |

---

### `knot_members`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `knot_id` | uuid FK → knots | |
| `user_id` | uuid FK → profiles | |
| `role` | text | `'member'` \| `'co_admin'` \| `'creator'` |
| `joined_at` | timestamptz | |

---

### `knot_ratings`

One star rating per user per knot.

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `knot_id` | uuid FK → knots | `on delete cascade` |
| `user_id` | uuid FK → profiles | defaults to `auth.uid()`; `on delete cascade` |
| `rating` | int NOT NULL | `CHECK (rating between 1 and 5)` |
| `created_at / updated_at` | timestamptz | |

**Unique:** `(knot_id, user_id)` — one rating per user. Client upserts on this constraint (`KnotRatingService.submit`) so re-rating updates rather than duplicates.

**Trigger `knot_ratings_sync` (SECURITY DEFINER):** on insert/update/delete, keeps `knots.rating_sum` and `knots.rating_count` current. App computes the average client-side and snaps it to the nearest 0.5 for the 5-star display (`CommunityGroup.roundedRating`).

**RLS:**
- SELECT — only your own rating (`auth.uid() = user_id`). Aggregates are read from the public `knots` row, not this table.
- INSERT / UPDATE — only as yourself **and** only if you're a member of the knot (`knot_members` check). Non-members cannot rate.
- DELETE — only your own rating.

---

### `knot_join_requests`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `knot_id` | uuid FK → knots | |
| `applicant_id` | uuid FK → profiles | |
| `answers` | jsonb | question_id → answer map |
| `status` | text | `'pending'` \| `'approved'` \| `'rejected'` |
| `submitted_at / reviewed_at / reviewed_by` | timestamptz / uuid | |

---

### `conversations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `is_group` | bool | |
| `group_name` | text | nullable (DMs have no name) |
| `group_image_url` | text | nullable — group chat photo (Storage `message-images` bucket, path `<conv_id>/group.jpg`) |
| `group_description` | text NOT NULL DEFAULT '' | group chat description (editable by admin/creator) |
| `creator_id` | uuid FK → profiles | |
| `source_knot_id` | uuid FK → knots | nullable — set for knot group chats |
| `created_at / updated_at` | timestamptz | |

---

### `conversation_participants`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `conversation_id` | uuid FK → conversations | |
| `user_id` | uuid FK → profiles | |
| `is_admin` | bool | |
| `is_creator` | bool | |
| `is_favourite` | bool | |
| `has_left` | bool | |
| `last_read_at` | timestamptz | nullable |
| `joined_at` | timestamptz | |

---

### `messages`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `conversation_id` | uuid FK → conversations | |
| `sender_id` | uuid FK → profiles | nullable for system messages |
| `text` | text NOT NULL DEFAULT '' | |
| `image_url` | text | nullable |
| `reply_to_id` | uuid FK → messages | nullable |
| `is_system` | bool | |
| `is_starred` | bool | |
| `status` | text | `'sent'` \| `'delivered'` \| `'read'` |
| `created_at` | timestamptz | |

---

### `shop_listings`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `seller_id` | uuid FK → profiles | |
| `listing_type` | enum `listing_type` | `'item'` \| `'service'` \| `'advertisement'` |
| `category` | enum `shop_category` | `'electronics'` \| `'furniture'` \| `'clothing'` \| `'sports'` \| `'books'` \| `'home_garden'` \| `'toys_games'` \| `'food'` \| `'other'` |
| `condition` | enum `item_condition` | `'not_specified'` \| `'brand_new'` \| `'like_new'` \| `'lightly_used'` \| `'well_used'` \| `'heavily_used'` |
| `name / description / link` | text NOT NULL DEFAULT '' | |
| `price_cents` | int NOT NULL DEFAULT 0 | |
| `image_urls` | text[] NOT NULL DEFAULT '{}' | Storage public URLs |
| `is_active` | bool NOT NULL DEFAULT true | **soft-delete flag** |
| `created_at / updated_at` | timestamptz | |

**RLS SELECT policy:** `(is_active = true) OR (seller_id = auth.uid())`
Sellers can see their own inactive listings; everyone else sees only active ones.

**Soft delete:** `ShopService.delete()` sets `is_active = false`. Rows are never hard-deleted.

---

### `orders`

| Column | Type | Notes |
|--------|------|-------|
| `id` | text PK | format: `#KN-XXXXX` |
| `listing_id` | uuid FK → shop_listings | |
| `buyer_id / seller_id` | uuid FK → profiles | |
| `subtotal_cents` | int | |
| `knot_fee_rate` | float8 | platform fee % |
| `knot_fee_cents / payout_cents` | int | **generated columns** — read only |
| `fulfilment` | text | `'meetup'` \| `'delivery'` |
| `delivery_address` | text | |
| `status` | text | `'pending'` → `'seller_accepted'` → `'meetup_agreed'` → `'awaiting_confirmation'` → `'complete'` \| `'disputed'` \| `'cancelled'` |
| `escrow_status` | text | `'held'` \| `'released'` \| `'refunded'` |
| `meetup_location / meetup_date / meetup_proposed_by` | mixed | nullable |
| `stripe_payment_intent_id / stripe_transfer_id` | text | nullable |
| timestamps for each status transition | timestamptz | nullable |

---

### `announcements`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `knot_id` | uuid FK → knots | nullable (global = null) |
| `sender_id` | uuid FK → profiles | |
| `title / body` | text NOT NULL | |
| `is_pinned` | bool | |
| `created_at` | timestamptz | |

---

### `announcement_reads`

Tracks per-user read/pin state. One row per user × announcement.

---

### `reviews`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `order_id` | text FK → orders | |
| `reviewer_id / reviewee_id` | uuid FK → profiles | |
| `rating` | int | 1–5 |
| `comment` | text | |
| `created_at` | timestamptz | |

---

## Supabase Storage Buckets

| Bucket | Contents |
|--------|---------|
| `profile-images` | User profile photos |
| `listing-images` | Marketplace listing photos |
| `knot-images` | Knot cover photos and group chat images |

Bucket name constant in `SupabaseManager.swift`:
```swift
enum Bucket {
    static let profileImages  = "profile-images"
    static let listingImages  = "listing-images"
    static let knotImages     = "knot-images"
}
```

---

## RPC Functions

### `find_or_create_knot_chat(p_knot_id uuid, p_knot_name text) → uuid`

Used by `MessagingService.findOrCreateKnotChat()`. Called when any knot member taps "Open Group Chat".

- Validates the caller is a member of `p_knot_id`
- Finds an existing conversation with `source_knot_id = p_knot_id`, OR creates one
- Ensures the caller is a participant
- Returns the conversation UUID

**Security:** `SECURITY DEFINER` — runs as the function owner, not the caller. This allows creating conversation rows even though RLS would normally block it.

---

## Row Level Security Notes

- Every table has RLS enabled.
- Silent failures are common: if RLS blocks a query, Supabase returns an empty array (not an error).
- If a fetch returns nothing unexpectedly, check RLS policies in the Supabase dashboard first.
- The `profiles` search function uses an explicit safe column list — never exposes `stripe_customer_id`, `street`, `city`, `postal_code`, or `country` to search callers.

---

## Common Query Patterns

### Fetch own profile
```swift
ProfileService.fetch(userID: uid)   // select()  = all columns
```

### Fetch multiple profiles by UUID
```swift
ProfileService.fetchMultiple(userIDs: [uuid1, uuid2])
// Always stores profileImage URL into connectionAvatarURLs
```

### Search profiles by name
```swift
ProfileService.search(query: "Alice")
// Explicit column list — no address/Stripe fields
// Must include onboarding_complete
```

### Create a listing
```swift
ShopService.create(type:category:condition:name:description:link:price:images:)
// Inserts with is_active = true
// Returns a DBShopListing constructed locally (doesn't re-fetch)
```

### Soft-delete a listing
```swift
ShopService.delete(listingID:)
// Sets is_active = false — does NOT hard-delete
```
