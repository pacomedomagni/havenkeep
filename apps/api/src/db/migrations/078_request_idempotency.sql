-- Migration 078: generic Idempotency-Key replay cache (S2-D)
--
-- Receipt scans (mig 051) already had a feature-specific replay table
-- (`receipt_scan_idempotency`). The mobile offline queue now sends an
-- Idempotency-Key on *every* mutating call so a re-sent queued action
-- can't duplicate writes — warranty claims, warranty purchases, and any
-- other mutating route. This table is the generic store; routes plug in
-- via the `idempotency` middleware.
--
-- Scope key is `(user_id, route_key, idempotency_key)`: the caller-supplied
-- UUID alone isn't enough to disambiguate (a client might reuse the same
-- key across endpoints by mistake), and `route_key` keeps each endpoint's
-- replay cache independent.

CREATE TABLE IF NOT EXISTS request_idempotency (
  user_id          UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  route_key        VARCHAR(64)  NOT NULL,
  idempotency_key  VARCHAR(255) NOT NULL,
  -- sha256(canonical_request_json). Mismatch on the same key = 409.
  request_hash     CHAR(64)     NOT NULL,
  response_status  INTEGER      NOT NULL,
  response_json    JSONB        NOT NULL,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ  NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  PRIMARY KEY (user_id, route_key, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_request_idempotency_expires
  ON request_idempotency (expires_at);

COMMENT ON TABLE request_idempotency IS
  'Generic Idempotency-Key replay cache. Same key + same body returns the prior response; same key + different body = 409 (RFC 9110 §17).';
