-- =============================================================
-- Knot — Initial Schema
-- Run this once in the Supabase SQL Editor (or via CLI)
-- =============================================================

-- ─── Extensions ──────────────────────────────────────────────
create extension if not exists "pgcrypto";


-- ─── Enum Types ───────────────────────────────────────────────
create type knot_payment_type      as enum ('free', 'per_session', 'one_time');
create type age_group_type         as enum ('any', 'teen', 'young', 'adult', 'senior', 'custom');
create type join_request_status    as enum ('pending', 'approved', 'rejected');
create type admin_action_type      as enum ('make_admin', 'dismiss_admin', 'kick');
create type admin_action_status    as enum ('pending', 'approved', 'rejected');
create type knot_member_role       as enum ('member', 'co_admin', 'creator');
create type message_read_status    as enum ('sent', 'delivered', 'read');
create type listing_type           as enum ('item', 'service', 'advertisement');
create type shop_category          as enum (
    'electronics', 'furniture', 'clothing', 'sports',
    'books', 'home_garden', 'toys_games', 'food', 'other'
);
create type item_condition         as enum (
    'not_specified', 'brand_new', 'like_new',
    'lightly_used', 'well_used', 'heavily_used'
);
create type order_status           as enum (
    'pending', 'seller_accepted', 'meetup_agreed',
    'awaiting_confirmation', 'complete', 'disputed', 'cancelled'
);
create type escrow_status          as enum ('held', 'released');
create type fulfilment_method      as enum ('meetup', 'delivery');
create type question_type          as enum ('open_ended', 'mcq');
create type problem_type           as enum ('not_as_described', 'no_show', 'damaged', 'other');


-- ─── Table: profiles ─────────────────────────────────────────
-- One row per auth.users user, created immediately after sign-up.
create table profiles (
    id                   uuid        primary key references auth.users(id) on delete cascade,
    name                 text        not null default '',
    bio                  text        not null default '',
    profile_image        text,                -- Supabase Storage public URL
    street               text        not null default '',
    city                 text        not null default '',
    postal_code          text        not null default '',
    country              text        not null default '',
    is_private           boolean     not null default false,
    show_knots           boolean     not null default true,
    show_listings        boolean     not null default true,
    show_connections     boolean     not null default true,
    stripe_customer_id   text,                -- set server-side on first payment
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now()
);

create index profiles_name_search_idx on profiles using gin (to_tsvector('simple', name));


-- ─── Table: connections ───────────────────────────────────────
create table connections (
    id              uuid        primary key default gen_random_uuid(),
    requester_id    uuid        not null references profiles(id) on delete cascade,
    recipient_id    uuid        not null references profiles(id) on delete cascade,
    status          text        not null check (status in ('pending', 'accepted', 'declined')),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    unique (requester_id, recipient_id)
);

create index connections_recipient_idx on connections(recipient_id);
create index connections_requester_idx on connections(requester_id);


-- ─── Table: knots ─────────────────────────────────────────────
create table knots (
    id                              uuid                primary key default gen_random_uuid(),
    creator_id                      uuid                not null references profiles(id) on delete restrict,
    name                            text                not null,
    description                     text                not null default '',
    image_url                       text,
    category                        text                not null,
    location                        text                not null default '',
    is_public                       boolean             not null default true,
    is_event                        boolean             not null default false,
    requires_approval               boolean             not null default false,
    is_connections_only             boolean             not null default false,
    hide_location_from_non_members  boolean             not null default false,
    max_members                     integer,
    age_group                       age_group_type      not null default 'any',
    min_age                         integer             not null default 13,
    max_age                         integer             not null default 99,
    is_paid                         boolean             not null default false,
    payment_type                    knot_payment_type   not null default 'free',
    price_cents                     integer             not null default 0,
    member_count                    integer             not null default 1,   -- maintained by trigger
    created_at                      timestamptz         not null default now(),
    updated_at                      timestamptz         not null default now()
);

create index knots_creator_idx  on knots(creator_id);
create index knots_category_idx on knots(category);
create index knots_public_idx   on knots(is_public) where is_public = true;
create index knots_search_idx   on knots using gin (to_tsvector('simple', name || ' ' || description));


-- ─── Table: knot_members ─────────────────────────────────────
create table knot_members (
    id          uuid                primary key default gen_random_uuid(),
    knot_id     uuid                not null references knots(id) on delete cascade,
    user_id     uuid                not null references profiles(id) on delete cascade,
    role        knot_member_role    not null default 'member',
    joined_at   timestamptz         not null default now(),
    unique (knot_id, user_id)
);

create index knot_members_knot_idx on knot_members(knot_id);
create index knot_members_user_idx on knot_members(user_id);

-- Trigger: keep knots.member_count accurate
create or replace function update_knot_member_count()
returns trigger language plpgsql as $$
begin
    if TG_OP = 'INSERT' then
        update knots
        set member_count = member_count + 1,
            updated_at   = now()
        where id = NEW.knot_id;
    elsif TG_OP = 'DELETE' then
        update knots
        set member_count = greatest(0, member_count - 1),
            updated_at   = now()
        where id = OLD.knot_id;
    end if;
    return null;
end;
$$;

create trigger trg_knot_member_count
after insert or delete on knot_members
for each row execute function update_knot_member_count();


-- ─── Table: knot_join_form_questions ─────────────────────────
create table knot_join_form_questions (
    id              uuid            primary key default gen_random_uuid(),
    knot_id         uuid            not null references knots(id) on delete cascade,
    sort_order      integer         not null default 0,
    question_type   question_type   not null default 'open_ended',
    prompt          text            not null,
    options         text[]          not null default '{}',   -- populated for MCQ
    required        boolean         not null default true
);

create index knot_questions_knot_idx on knot_join_form_questions(knot_id);


-- ─── Table: knot_join_requests ───────────────────────────────
create table knot_join_requests (
    id              uuid                primary key default gen_random_uuid(),
    knot_id         uuid                not null references knots(id) on delete cascade,
    applicant_id    uuid                not null references profiles(id) on delete cascade,
    -- {question_id: answer_text}
    answers         jsonb               not null default '{}',
    status          join_request_status not null default 'pending',
    submitted_at    timestamptz         not null default now(),
    reviewed_at     timestamptz,
    reviewed_by     uuid                references profiles(id),
    unique (knot_id, applicant_id)
);

create index join_requests_knot_idx    on knot_join_requests(knot_id);
create index join_requests_status_idx  on knot_join_requests(status);


-- ─── Table: knot_admin_action_requests ───────────────────────
create table knot_admin_action_requests (
    id                      uuid                primary key default gen_random_uuid(),
    knot_id                 uuid                not null references knots(id) on delete cascade,
    requesting_admin_id     uuid                not null references profiles(id) on delete cascade,
    target_member_id        uuid                not null references profiles(id) on delete cascade,
    action_type             admin_action_type   not null,
    status                  admin_action_status not null default 'pending',
    created_at              timestamptz         not null default now(),
    resolved_at             timestamptz,
    resolved_by             uuid                references profiles(id)
);

create index admin_actions_knot_idx on knot_admin_action_requests(knot_id);


-- ─── Table: conversations ─────────────────────────────────────
create table conversations (
    id              uuid        primary key default gen_random_uuid(),
    is_group        boolean     not null default false,
    group_name      text,                   -- null for 1:1
    group_image_url text,                   -- null for 1:1
    creator_id      uuid        not null references profiles(id) on delete restrict,
    source_knot_id  uuid        references knots(id) on delete set null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index conversations_knot_idx on conversations(source_knot_id);


-- ─── Table: conversation_participants ────────────────────────
create table conversation_participants (
    id                  uuid        primary key default gen_random_uuid(),
    conversation_id     uuid        not null references conversations(id) on delete cascade,
    user_id             uuid        not null references profiles(id) on delete cascade,
    is_admin            boolean     not null default false,
    is_creator          boolean     not null default false,
    is_favourite        boolean     not null default false,
    has_left            boolean     not null default false,
    last_read_at        timestamptz,
    joined_at           timestamptz not null default now(),
    unique (conversation_id, user_id)
);

create index conv_participants_user_idx on conversation_participants(user_id);
create index conv_participants_conv_idx on conversation_participants(conversation_id);


-- ─── Table: messages ─────────────────────────────────────────
create table messages (
    id              uuid                primary key default gen_random_uuid(),
    conversation_id uuid                not null references conversations(id) on delete cascade,
    sender_id       uuid                references profiles(id) on delete set null,  -- null = system msg
    text            text                not null default '',
    image_url       text,
    reply_to_id     uuid                references messages(id) on delete set null,
    is_system       boolean             not null default false,
    is_starred      boolean             not null default false,
    status          message_read_status not null default 'sent',
    created_at      timestamptz         not null default now()
);

create index messages_conv_created_idx on messages(conversation_id, created_at desc);
create index messages_sender_idx       on messages(sender_id);

-- Trigger: bump conversations.updated_at on each new message
create or replace function bump_conversation_updated()
returns trigger language plpgsql as $$
begin
    update conversations set updated_at = now() where id = NEW.conversation_id;
    return null;
end;
$$;

create trigger trg_bump_conv_updated
after insert on messages
for each row execute function bump_conversation_updated();


-- ─── Table: shop_listings ────────────────────────────────────
create table shop_listings (
    id              uuid            primary key default gen_random_uuid(),
    seller_id       uuid            not null references profiles(id) on delete cascade,
    listing_type    listing_type    not null default 'item',
    category        shop_category   not null default 'other',
    condition       item_condition  not null default 'not_specified',
    name            text            not null,
    description     text            not null default '',
    link            text            not null default '',
    price_cents     integer         not null default 0,
    image_urls      text[]          not null default '{}',
    is_active       boolean         not null default true,
    created_at      timestamptz     not null default now(),
    updated_at      timestamptz     not null default now()
);

create index listings_seller_idx   on shop_listings(seller_id);
create index listings_type_idx     on shop_listings(listing_type);
create index listings_active_idx   on shop_listings(is_active) where is_active = true;
create index listings_search_idx   on shop_listings
    using gin (to_tsvector('simple', name || ' ' || description));


-- ─── Table: orders ───────────────────────────────────────────
-- Text PK preserves the "#KN-XXXXX" format already used in Swift.
-- Inserts are blocked for authenticated users — Edge Function only.
create table orders (
    id                          text            primary key,
    listing_id                  uuid            not null references shop_listings(id) on delete restrict,
    buyer_id                    uuid            not null references profiles(id) on delete restrict,
    seller_id                   uuid            not null references profiles(id) on delete restrict,
    subtotal_cents              integer         not null,
    knot_fee_rate               numeric(5,4)    not null default 0.10,
    knot_fee_cents              integer         not null generated always as
                                    (floor(subtotal_cents * knot_fee_rate)::integer) stored,
    payout_cents                integer         not null generated always as
                                    (subtotal_cents - floor(subtotal_cents * knot_fee_rate)::integer) stored,
    fulfilment                  fulfilment_method not null,
    delivery_address            text            not null default '',
    status                      order_status    not null default 'pending',
    escrow_status               escrow_status   not null default 'held',
    -- Meetup proposal
    meetup_location             text,
    meetup_date                 timestamptz,
    meetup_proposed_by          text            check (meetup_proposed_by in ('buyer', 'seller')),
    -- Per-status timestamps (flat columns — easier to query than jsonb)
    pending_at                  timestamptz,
    seller_accepted_at          timestamptz,
    meetup_agreed_at            timestamptz,
    awaiting_confirmation_at    timestamptz,
    complete_at                 timestamptz,
    disputed_at                 timestamptz,
    cancelled_at                timestamptz,
    -- Stripe
    stripe_payment_intent_id    text,
    stripe_transfer_id          text,
    created_at                  timestamptz     not null default now(),
    updated_at                  timestamptz     not null default now()
);

create index orders_buyer_idx   on orders(buyer_id);
create index orders_seller_idx  on orders(seller_id);
create index orders_status_idx  on orders(status);


-- ─── Table: order_disputes ───────────────────────────────────
create table order_disputes (
    id              uuid            primary key default gen_random_uuid(),
    order_id        text            not null references orders(id) on delete cascade,
    reporter_id     uuid            not null references profiles(id) on delete restrict,
    problem_type    problem_type    not null,
    description     text            not null,
    resolved        boolean         not null default false,
    created_at      timestamptz     not null default now()
);


-- ─── Table: reviews ──────────────────────────────────────────
create table reviews (
    id              uuid        primary key default gen_random_uuid(),
    order_id        text        not null references orders(id) on delete cascade,
    reviewer_id     uuid        not null references profiles(id) on delete restrict,
    reviewee_id     uuid        not null references profiles(id) on delete restrict,
    rating          smallint    not null check (rating between 1 and 5),
    comment         text        not null default '',
    created_at      timestamptz not null default now(),
    unique (order_id, reviewer_id)
);

create index reviews_reviewee_idx on reviews(reviewee_id);


-- ─── Table: stripe_payment_methods ───────────────────────────
-- Stores Stripe tokens only — never raw card data.
-- Inserts are blocked for authenticated users — Edge Function only.
create table stripe_payment_methods (
    id                          uuid        primary key default gen_random_uuid(),
    user_id                     uuid        not null references profiles(id) on delete cascade,
    stripe_payment_method_id    text        not null unique,   -- "pm_xxx"
    brand                       text        not null,
    last4                       text        not null,
    exp_month                   integer     not null,
    exp_year                    integer     not null,
    is_default                  boolean     not null default false,
    created_at                  timestamptz not null default now()
);

create index stripe_pm_user_idx on stripe_payment_methods(user_id);


-- ─── Table: announcements ────────────────────────────────────
-- knot_id = null means platform-wide announcement.
create table announcements (
    id          uuid        primary key default gen_random_uuid(),
    knot_id     uuid        references knots(id) on delete cascade,
    sender_id   uuid        not null references profiles(id) on delete cascade,
    title       text        not null,
    body        text        not null,
    is_pinned   boolean     not null default false,
    created_at  timestamptz not null default now()
);

create index announcements_knot_idx on announcements(knot_id);


-- ─── Table: announcement_reads ───────────────────────────────
-- Per-user read state. One row inserted lazily when user first opens an announcement.
create table announcement_reads (
    announcement_id uuid        not null references announcements(id) on delete cascade,
    user_id         uuid        not null references profiles(id) on delete cascade,
    is_read         boolean     not null default false,
    is_pinned       boolean     not null default false,   -- user's personal pin override
    read_at         timestamptz,
    primary key (announcement_id, user_id)
);


-- =============================================================
-- Row Level Security
-- =============================================================

alter table profiles                    enable row level security;
alter table connections                 enable row level security;
alter table knots                       enable row level security;
alter table knot_members                enable row level security;
alter table knot_join_form_questions    enable row level security;
alter table knot_join_requests          enable row level security;
alter table knot_admin_action_requests  enable row level security;
alter table conversations               enable row level security;
alter table conversation_participants   enable row level security;
alter table messages                    enable row level security;
alter table shop_listings               enable row level security;
alter table orders                      enable row level security;
alter table order_disputes              enable row level security;
alter table reviews                     enable row level security;
alter table stripe_payment_methods      enable row level security;
alter table announcements               enable row level security;
alter table announcement_reads          enable row level security;


-- ── profiles ──
create policy "profiles_select" on profiles for select using (
    id = auth.uid()
    or not is_private
    or exists (
        select 1 from connections
        where status = 'accepted'
          and ((requester_id = auth.uid() and recipient_id = profiles.id)
            or (recipient_id = auth.uid() and requester_id = profiles.id))
    )
);
create policy "profiles_insert" on profiles for insert with check (id = auth.uid());
create policy "profiles_update" on profiles for update using (id = auth.uid());


-- ── connections ──
create policy "connections_select" on connections for select using (
    requester_id = auth.uid() or recipient_id = auth.uid()
);
create policy "connections_insert" on connections for insert with check (
    requester_id = auth.uid()
);
create policy "connections_update" on connections for update using (
    recipient_id = auth.uid()
);
create policy "connections_delete" on connections for delete using (
    requester_id = auth.uid() or recipient_id = auth.uid()
);


-- ── knots ──
create policy "knots_select" on knots for select using (
    is_public
    or exists (
        select 1 from knot_members
        where knot_id = knots.id and user_id = auth.uid()
    )
);
create policy "knots_insert" on knots for insert with check (creator_id = auth.uid());
create policy "knots_update" on knots for update using (
    exists (
        select 1 from knot_members
        where knot_id = knots.id
          and user_id = auth.uid()
          and role in ('creator', 'co_admin')
    )
);
create policy "knots_delete" on knots for delete using (creator_id = auth.uid());


-- ── knot_members ──
create policy "knot_members_select" on knot_members for select using (
    user_id = auth.uid()
    or exists (
        select 1 from knot_members km2
        where km2.knot_id = knot_members.knot_id and km2.user_id = auth.uid()
    )
);
-- Creator-only client insert at knot creation. Approved joins go via Edge Function (service_role).
create policy "knot_members_insert" on knot_members for insert with check (
    user_id = auth.uid() and role = 'creator'
);
create policy "knot_members_update" on knot_members for update using (
    exists (
        select 1 from knot_members km2
        where km2.knot_id = knot_members.knot_id
          and km2.user_id = auth.uid()
          and km2.role = 'creator'
    )
);
create policy "knot_members_delete" on knot_members for delete using (
    user_id = auth.uid()
    or exists (
        select 1 from knot_members km2
        where km2.knot_id = knot_members.knot_id
          and km2.user_id = auth.uid()
          and km2.role in ('creator', 'co_admin')
    )
);


-- ── knot_join_form_questions ──
create policy "questions_select" on knot_join_form_questions for select using (
    exists (select 1 from knots where id = knot_id and is_public)
    or exists (select 1 from knot_members where knot_id = knot_join_form_questions.knot_id and user_id = auth.uid())
);
create policy "questions_write" on knot_join_form_questions for all using (
    exists (
        select 1 from knot_members
        where knot_id = knot_join_form_questions.knot_id
          and user_id = auth.uid()
          and role in ('creator', 'co_admin')
    )
);


-- ── knot_join_requests ──
create policy "join_requests_select" on knot_join_requests for select using (
    applicant_id = auth.uid()
    or exists (
        select 1 from knot_members
        where knot_id = knot_join_requests.knot_id
          and user_id = auth.uid()
          and role in ('creator', 'co_admin')
    )
);
create policy "join_requests_insert" on knot_join_requests for insert with check (
    applicant_id = auth.uid()
);
create policy "join_requests_update" on knot_join_requests for update using (
    exists (
        select 1 from knot_members
        where knot_id = knot_join_requests.knot_id
          and user_id = auth.uid()
          and role in ('creator', 'co_admin')
    )
);


-- ── knot_admin_action_requests ──
create policy "admin_actions_select" on knot_admin_action_requests for select using (
    requesting_admin_id = auth.uid()
    or exists (
        select 1 from knot_members
        where knot_id = knot_admin_action_requests.knot_id
          and user_id = auth.uid()
          and role = 'creator'
    )
);
create policy "admin_actions_insert" on knot_admin_action_requests for insert with check (
    requesting_admin_id = auth.uid()
    and exists (
        select 1 from knot_members
        where knot_id = knot_admin_action_requests.knot_id
          and user_id = auth.uid()
          and role = 'co_admin'
    )
);
create policy "admin_actions_update" on knot_admin_action_requests for update using (
    exists (
        select 1 from knot_members
        where knot_id = knot_admin_action_requests.knot_id
          and user_id = auth.uid()
          and role = 'creator'
    )
);


-- ── conversations ──
create policy "conversations_select" on conversations for select using (
    exists (
        select 1 from conversation_participants
        where conversation_id = conversations.id and user_id = auth.uid()
    )
);
create policy "conversations_insert" on conversations for insert with check (
    creator_id = auth.uid()
);
create policy "conversations_update" on conversations for update using (
    exists (
        select 1 from conversation_participants
        where conversation_id = conversations.id
          and user_id = auth.uid()
          and (is_admin = true or is_creator = true)
    )
);


-- ── conversation_participants ──
create policy "conv_participants_select" on conversation_participants for select using (
    user_id = auth.uid()
    or exists (
        select 1 from conversation_participants cp2
        where cp2.conversation_id = conversation_participants.conversation_id
          and cp2.user_id = auth.uid()
    )
);
create policy "conv_participants_insert" on conversation_participants for insert with check (
    exists (
        select 1 from conversations
        where id = conversation_id and creator_id = auth.uid()
    )
    or exists (
        select 1 from conversation_participants cp2
        where cp2.conversation_id = conversation_participants.conversation_id
          and cp2.user_id = auth.uid()
          and cp2.is_admin = true
    )
);
create policy "conv_participants_update" on conversation_participants for update using (
    user_id = auth.uid()
    or exists (
        select 1 from conversation_participants cp2
        where cp2.conversation_id = conversation_participants.conversation_id
          and cp2.user_id = auth.uid()
          and (cp2.is_admin = true or cp2.is_creator = true)
    )
);


-- ── messages ──
create policy "messages_select" on messages for select using (
    exists (
        select 1 from conversation_participants
        where conversation_id = messages.conversation_id and user_id = auth.uid()
    )
);
create policy "messages_insert" on messages for insert with check (
    sender_id = auth.uid()
    and exists (
        select 1 from conversation_participants
        where conversation_id = messages.conversation_id
          and user_id = auth.uid()
          and has_left = false
    )
);
create policy "messages_update" on messages for update using (sender_id = auth.uid());


-- ── shop_listings ──
create policy "listings_select" on shop_listings for select using (
    is_active = true or seller_id = auth.uid()
);
create policy "listings_insert" on shop_listings for insert with check (seller_id = auth.uid());
create policy "listings_update" on shop_listings for update using (seller_id = auth.uid());
create policy "listings_delete" on shop_listings for delete using (seller_id = auth.uid());


-- ── orders ──
create policy "orders_select" on orders for select using (
    buyer_id = auth.uid() or seller_id = auth.uid()
);
-- No client inserts — handled by create-order Edge Function (service_role)
create policy "orders_insert" on orders for insert with check (false);
create policy "orders_update" on orders for update using (
    buyer_id = auth.uid() or seller_id = auth.uid()
);


-- ── order_disputes ──
create policy "disputes_select" on order_disputes for select using (
    reporter_id = auth.uid()
    or exists (select 1 from orders where id = order_id and seller_id = auth.uid())
);
create policy "disputes_insert" on order_disputes for insert with check (
    reporter_id = auth.uid()
    and exists (select 1 from orders where id = order_id and buyer_id = auth.uid())
);


-- ── reviews ──
create policy "reviews_select" on reviews for select using (true);
create policy "reviews_insert" on reviews for insert with check (
    reviewer_id = auth.uid()
    and exists (
        select 1 from orders
        where id = order_id
          and status = 'complete'
          and (buyer_id = auth.uid() or seller_id = auth.uid())
    )
);


-- ── stripe_payment_methods ──
create policy "stripe_pm_select" on stripe_payment_methods for select using (user_id = auth.uid());
-- No client inserts — handled by attach-stripe-payment-method Edge Function (service_role)
create policy "stripe_pm_insert" on stripe_payment_methods for insert with check (false);
create policy "stripe_pm_delete" on stripe_payment_methods for delete using (user_id = auth.uid());


-- ── announcements ──
create policy "announcements_select" on announcements for select using (
    knot_id is null
    or exists (
        select 1 from knot_members
        where knot_id = announcements.knot_id and user_id = auth.uid()
    )
);
create policy "announcements_insert" on announcements for insert with check (
    sender_id = auth.uid()
    and (
        knot_id is null
        or exists (
            select 1 from knot_members
            where knot_id = announcements.knot_id
              and user_id = auth.uid()
              and role in ('creator', 'co_admin')
        )
    )
);
create policy "announcements_update" on announcements for update using (sender_id = auth.uid());


-- ── announcement_reads ──
create policy "ann_reads_select" on announcement_reads for select using (user_id = auth.uid());
create policy "ann_reads_insert" on announcement_reads for insert with check (user_id = auth.uid());
create policy "ann_reads_update" on announcement_reads for update using (user_id = auth.uid());


-- =============================================================
-- Storage Buckets
-- Run in Supabase Dashboard → Storage, or via CLI:
--   supabase storage create profile-images --public
--   supabase storage create knot-images --public
--   supabase storage create listing-images --public
--   supabase storage create message-images   (private)
-- =============================================================
