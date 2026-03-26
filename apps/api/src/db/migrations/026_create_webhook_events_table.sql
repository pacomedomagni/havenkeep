-- ============================================
-- Migration 026: Create webhook_events table for idempotency
-- Date: 2026-03-25
-- Description: Stores processed webhook event IDs to prevent
--   duplicate processing of Stripe and RevenueCat webhook deliveries.
--   Events are retained for 7 days then eligible for cleanup.
-- ============================================

CREATE TABLE IF NOT EXISTS webhook_events (
  id SERIAL PRIMARY KEY,
  event_id VARCHAR(255) NOT NULL,
  source VARCHAR(50) NOT NULL,  -- 'stripe' or 'revenuecat'
  event_type VARCHAR(100) NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraint ensures idempotency: same event_id + source can only be inserted once
CREATE UNIQUE INDEX idx_webhook_events_unique ON webhook_events (source, event_id);

-- Index for cleanup queries (delete events older than 7 days)
CREATE INDEX idx_webhook_events_processed_at ON webhook_events (processed_at);
