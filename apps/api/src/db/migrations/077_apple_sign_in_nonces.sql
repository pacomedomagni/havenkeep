-- Migration 077: Apple Sign-In nonce store (Ch01-F? / S1-H)
--
-- Fix for replay attacks against /auth/apple. The mobile client now
-- generates a random per-attempt nonce, hashes it with SHA-256, passes
-- the *hashed* value to Apple's SDK, then sends the *unhashed* nonce in
-- the request body. The server hashes again and verifies the result
-- matches the `nonce` claim in the verified ID token.
--
-- To stop the same id-token+nonce pair from being replayed, we record
-- the SHA-256 hash of every consumed nonce here with a short TTL (5
-- minutes). The Apple ID token's exp is ~10 minutes; 5 covers any
-- realistic delivery slop. A daily prune job removes expired rows.
--
-- This table is a fallback for deployments without Redis. When Redis is
-- configured, the route prefers the SET … NX EX path; when it's not, it
-- inserts here and lets the unique constraint reject replays.

CREATE TABLE IF NOT EXISTS apple_sign_in_nonces (
  nonce_hash  CHAR(64)  PRIMARY KEY,
  expires_at  TIMESTAMPTZ NOT NULL
);

-- Cheap range scan for the cleanup job.
CREATE INDEX IF NOT EXISTS idx_apple_sign_in_nonces_expires
  ON apple_sign_in_nonces(expires_at);
