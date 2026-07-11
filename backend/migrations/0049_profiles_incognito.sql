-- Incognito / invisible mode (Grindr "incognito" parity).
--
-- When `incognito` is true, the user is excluded from *other* users'
-- /grid/nearby and /discover results (they can still browse others).
-- Premium-gated on the client (incognitoMode feature); the column itself is
-- additive and defaults to visible so existing users are unaffected.
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS incognito boolean NOT NULL DEFAULT false;

-- Partial index: the grid excludes incognito users, so only the (small) set of
-- incognito=true rows ever needs to be matched against.
CREATE INDEX IF NOT EXISTS idx_profiles_incognito
    ON profiles (user_id) WHERE incognito = true;
