-- Migration 103: H3 — let idempotency middleware claim a slot atomically.
--
-- The prior shape persisted (request_hash, response_status, response_json)
-- only AFTER the handler ran successfully. Two simultaneous same-key
-- requests both saw a SELECT miss, both ran the handler, both wrote
-- (the second's INSERT lost to ON CONFLICT DO NOTHING but the
-- handler had already executed) — and the second caller got a
-- response that diverged from the first's cached body.
--
-- New shape: middleware INSERTs a placeholder row with response_status
-- + response_json NULL the moment it sees a key it has no record of.
-- Whichever side wins the unique constraint is the executor; the other
-- polls for the response_json to be filled in. To make that possible
-- the two columns become NULLable, and a new `claimed_at` timestamp
-- records when the placeholder was created (so a polling loser can
-- time out if the executor crashed mid-flight).

ALTER TABLE request_idempotency
  ALTER COLUMN response_status DROP NOT NULL,
  ALTER COLUMN response_json   DROP NOT NULL;

ALTER TABLE request_idempotency
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ;

DO $$
BEGIN
  RAISE NOTICE 'Migration 103 complete: request_idempotency supports claim-then-fill flow';
END $$;
