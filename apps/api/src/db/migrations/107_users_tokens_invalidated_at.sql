-- Migration 107: users.tokens_invalidated_at — kill access tokens (H18+H19).
--
-- Refresh-token deletion is fine for kicking the user out NEXT refresh,
-- but access tokens stay valid for up to JWT_EXPIRES_IN (1h) once
-- issued because they're stateless. Password change, email change, and
-- admin suspend currently delete refresh tokens but leave the existing
-- access tokens alive. An attacker who already has the access token
-- gets up to an hour of grace.
--
-- Fix: stamp `tokens_invalidated_at` on those state changes. The
-- authenticate middleware compares the access token's `iat` (issued-at,
-- in seconds) to this column and rejects anything older. Refresh path
-- mints a fresh token with a new `iat` so the user immediately gets a
-- working session back.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS tokens_invalidated_at TIMESTAMPTZ;
