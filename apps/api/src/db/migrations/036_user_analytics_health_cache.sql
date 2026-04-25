-- ============================================
-- Migration 036: Cache health score on user_analytics (Ch04-F048)
-- Date: 2026-04-25
-- Description: GET /stats/dashboard recomputes calculate_health_score on every
--   hit. With ~30 reads per active session that's millions of redundant scans
--   on items + documents + maintenance_history. Cache the score per-user with
--   a writable invalidation timestamp; dashboard returns cached if fresh and
--   recomputes lazily otherwise.
-- ============================================

ALTER TABLE user_analytics
  ADD COLUMN IF NOT EXISTS cached_health_score   INTEGER,
  ADD COLUMN IF NOT EXISTS cached_health_score_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_user_analytics_cached_health_at
  ON user_analytics(cached_health_score_at);

DO $$
BEGIN
  RAISE NOTICE 'Migration 036 complete: cached_health_score columns added';
END $$;
