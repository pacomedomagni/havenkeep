-- Migration 104: extend audit_action enum.
--
-- H1: system.audit_chain_break — emitted when the daily verifier
--   surfaces any broken row. Stays in the chain so the tampering
--   attempt itself leaves a forensic breadcrumb.
-- H76: admin.commission_approve / .commission_pay / .commission_cancel
--   — money-moving admin actions that previously had no audit trail.
-- H77 (anticipated): admin.newsletter_token_cleanup — not yet wired
--   from code but added here so the next migration boundary isn't
--   blocked on a single enum value.

ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'system.audit_chain_break';
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'admin.commission_approve';
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'admin.commission_pay';
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'admin.commission_cancel';
