-- Hot-path index: grid/discover exclude blocked users bidirectionally on every
-- request. The forward check (blocks WHERE user_id = $me) is served by the PK
-- (user_id, target_id), but the reverse check (blocks WHERE target_id = $me)
-- has no usable index — target_id is not a PK prefix — so it seq-scans blocks
-- on every grid load. This index covers the reverse-block lookup.
CREATE INDEX IF NOT EXISTS idx_blocks_target ON blocks(target_id);
