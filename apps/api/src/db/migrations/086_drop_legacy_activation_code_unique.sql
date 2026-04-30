-- Migration 086: drop the redundant uq_partner_gifts_activation_code
-- (plaintext) UNIQUE constraint.
--
-- Audit H-D4: mig 011 added a UNIQUE on the plaintext `activation_code`
-- column (DB-24). Mig 032 then added the canonical hashed-code unique
-- index `idx_partner_gifts_activation_code_hash`. Both indexes cover
-- the same value-space (hash is a deterministic function of plaintext,
-- so a collision on one is a collision on the other) — the plaintext
-- UNIQUE is duplicate work + duplicate index storage on every INSERT.
--
-- The audit's deeper recommendation — null out `activation_code`
-- post-email-send so plaintext doesn't sit at rest — is a larger
-- feature change (partners look up old codes by reading the gift list,
-- and a "Resend" UI exists). That's deliberately deferred to a later
-- phase; this migration just removes the redundant constraint.

ALTER TABLE partner_gifts
  DROP CONSTRAINT IF EXISTS uq_partner_gifts_activation_code;

DO $$
BEGIN
  RAISE NOTICE 'Migration 086 complete: dropped redundant plaintext activation_code UNIQUE (H-D4)';
END $$;
