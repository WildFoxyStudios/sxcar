-- Idempotency for provider webhooks (RevenueCat/stores).
-- RevenueCat redelivers the same event on retries; dedup by its event id so
-- grant/revoke side effects run exactly once.
CREATE TABLE IF NOT EXISTS processed_webhook_events (
  event_id   text NOT NULL,
  provider   text NOT NULL DEFAULT 'revenuecat',
  received_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, event_id)
);
