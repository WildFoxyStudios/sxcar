-- ═══ AD-Billing: subscriptions entitlements for the new purchase flow ═══
-- (mega-spec Grindr 100% parity)
--
-- A `subscriptions` table already exists from migration 0007 (tier-based,
-- store/revenuecat_id, current_period_end). This migration ADDS the columns
-- the new /billing/* simulated-purchase API needs (plan_code, price_id,
-- period, period_days, source, started_at, expires_at) without dropping the
-- old columns, so the migration is safe to re-run and the legacy code keeps
-- working.
--
-- Indexes are recreated for the new shape and are idempotent (IF NOT EXISTS).

ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS plan_code text REFERENCES plans(code),
  ADD COLUMN IF NOT EXISTS price_id uuid REFERENCES plan_prices(id),
  ADD COLUMN IF NOT EXISTS period text CHECK (period IN ('monthly', 'yearly')),
  ADD COLUMN IF NOT EXISTS period_days int CHECK (period_days > 0),
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'simulated',
  ADD COLUMN IF NOT EXISTS started_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- A row is "active" if status='active' AND expires_at is in the future.
-- (Existing legacy rows have status='active' but NULL expires_at; treat them
-- as not-entitled to avoid granting free infinite subscriptions.)
ALTER TABLE subscriptions
  DROP CONSTRAINT IF EXISTS subscriptions_status_check;
ALTER TABLE subscriptions
  ADD CONSTRAINT subscriptions_status_check
  CHECK (status IN ('active', 'expired', 'grace', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_active
  ON subscriptions(user_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_expires
  ON subscriptions(user_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_subscriptions_plan
  ON subscriptions(plan_code);

-- ═══ Seed two real paid tiers the Flutter TiendaScreen expects ═══
-- The Flutter app shows 2 segments (Vibra+, Unlimited) + duration cards.
INSERT INTO plans (code, name, tier, active, description) VALUES
  ('vibra_plus', 'Vibra+', 1, true, 'Premium tier with unlimited chats and no ads'),
  ('unlimited',  'Unlimited', 2, true, 'Top tier with incognito mode and all features')
ON CONFLICT (code) DO NOTHING;

INSERT INTO plan_features (plan_code, feature, enabled) VALUES
  ('vibra_plus', 'unlimited_chats', true),
  ('vibra_plus', 'no_ads', true),
  ('vibra_plus', 'see_who_viewed', true),
  ('unlimited',  'unlimited_chats', true),
  ('unlimited',  'no_ads', true),
  ('unlimited',  'see_who_viewed', true),
  ('unlimited',  'incognito_mode', true),
  ('unlimited',  'boost_discount', true)
ON CONFLICT (plan_code, feature) DO NOTHING;

-- Global fallback pricing (XX country) in EUR. Other countries can be added later.
INSERT INTO plan_prices (plan_code, country_code, currency, price_monthly, price_yearly) VALUES
  ('vibra_plus', 'XX', 'EUR', 8.99, 49.99),
  ('unlimited',  'XX', 'EUR', 19.99, 99.99)
ON CONFLICT (plan_code, country_code) DO NOTHING;
