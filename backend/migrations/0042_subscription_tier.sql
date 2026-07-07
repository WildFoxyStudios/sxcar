-- Add subscription_tier column to users table for premium feature gating.
-- Values: 'free', 'xtra', 'unlimited'
-- The column is set/updated by RevenueCat webhook handler.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS subscription_tier TEXT NOT NULL DEFAULT 'free';

-- Index for queries that filter by tier (admin views, analytics).
CREATE INDEX IF NOT EXISTS idx_users_subscription_tier ON users(subscription_tier);
