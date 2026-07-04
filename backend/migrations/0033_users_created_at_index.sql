-- Grindr parity T5.2: index on users.created_at to support the NUEVO badge query
-- (users whose account is <7 days old) when combined with the nearby filters in
-- /grid/nearby. Without this index, the LEFT JOIN to a users.created_at < now() - interval
-- '7 days' predicate would force a sequential scan.
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
