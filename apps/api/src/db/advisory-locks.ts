/**
 * Central registry of pg_advisory_lock keys.
 *
 * Why a central registry: H7 caught the digest tick (every 60s) sharing
 * the same lock id (`93422878`) as the partner-commission auto-approve
 * (daily). If both crons happen to race, one silently no-ops. The fix
 * is "unique keys per concern" — collecting them here also makes it
 * trivial for a reviewer to spot the next collision before it ships.
 *
 * Style: each key is a distinct 32-bit integer. Range chosen to be
 * far from other apps that share the same Postgres host (loni,
 * restorae, etc.) so cross-app collision is unlikely.
 *
 * When adding a new lock: append at the bottom with the next free id
 * AND a brief comment of who holds it (handler + frequency).
 */

export const ADVISORY_LOCKS = {
  // Daily-cron concerns.
  NOTIFICATION_EXPIRATION: 93422874,        // expiration-notifications, daily 09:00 UTC
  MAINTENANCE_DUE: 93422875,                // maintenance-due, daily
  WARRANTY_OFFERS: 93422876,                // warranty-offers, daily
  PARTNER_GIFT_EXPIRY: 93422877,            // expireUnactivatedPartnerGifts, daily
  PARTNER_COMMISSION_AUTO_APPROVE: 93422878, // autoApproveAgedPendingCommissions, daily

  // High-frequency tick.
  // H7: was 93422878 (same as PARTNER_COMMISSION_AUTO_APPROVE). Re-keyed
  // to a distinct id so the 60-second digest tick can't silently
  // starve the daily auto-approve.
  NOTIFICATION_DIGEST_FLUSH: 93422879,      // notification-digest-flush, every 60s

  // Migration / data integrity locks (referenced elsewhere — kept here
  // for completeness of the registry).
  // run-migration.ts MIGRATION_LOCK_KEY = 0x4d_47_52_4e ('MGRN')
  // mig 080 audit_logs_assign_hash() pg_advisory_xact_lock(687638440097)
  // account-purge.service.ts ADVISORY_LOCK_KEY = 0xa00d_4a13
} as const;
