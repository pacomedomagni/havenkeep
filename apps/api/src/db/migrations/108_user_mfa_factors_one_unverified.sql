-- Migration 108: H21 — at most one unverified MFA factor per user.
--
-- enrollTotp() in mfa.service.ts intentionally overwrites the prior
-- unverified row (DELETE before INSERT inside one tx) so a user
-- re-enrolling mid-flow doesn't accumulate. But two simultaneous
-- enroll calls can both pass the DELETE then both INSERT, leaving
-- two unverified rows. The next verify pulls one secret, the QR the
-- user just scanned belongs to the other → user can never complete
-- enrollment.
--
-- Partial unique index closes the race at the DB level. Verified
-- rows (verified_at IS NOT NULL) are exempt — multiple verified
-- factors per user is a future feature (TOTP + recovery codes today;
-- WebAuthn next).

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_mfa_factors_one_unverified
  ON user_mfa_factors (user_id)
  WHERE verified_at IS NULL;
