-- ============================================
-- Migration 025: Add missing audit_action enum values
-- Date: 2026-03-04
-- Description: The TypeScript AuditAction type in audit.service.ts includes
--   'auth.logout_all', 'user.email_change_requested', and 'item.export',
--   but these values were never added to the PostgreSQL audit_action ENUM
--   (created in migration 004). Inserting audit rows with these actions
--   causes a runtime error.
-- ============================================

ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'auth.logout_all';
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'user.email_change_requested';
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'item.export';

DO $$
BEGIN
  RAISE NOTICE 'Migration 025: Added audit_action enum values: auth.logout_all, user.email_change_requested, item.export';
END $$;
