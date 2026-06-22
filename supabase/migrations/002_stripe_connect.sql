-- Add Stripe Connect account ID to profiles.
-- Sellers go through Stripe Express onboarding; this stores their acct_xxx ID
-- so release-escrow can transfer payouts to their bank account.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS stripe_connect_id TEXT;
