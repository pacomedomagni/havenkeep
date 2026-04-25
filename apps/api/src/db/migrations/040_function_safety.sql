-- ============================================
-- Migration 040: plpgsql function hardening (Ch00-DB006..010)
-- Date: 2026-04-25
-- Description:
--   * Every plpgsql function now SET search_path = pg_catalog, public so a
--     malicious schema entry can't shadow a built-in or app object the
--     function calls (DB006).
--   * calculate_health_score uses INTEGER for counts and the divide step so
--     a float divide doesn't drift counts (DB007). Also guards the no-op
--     UPDATE: when the user_analytics row doesn't exist, INSERT it instead
--     of silently dropping the score (DB008). Caps health_score_history at
--     90 days of entries so the JSONB doesn't grow unbounded (DB009).
--   * get_dashboard_stats COALESCE-guards estimated_repair_cost so a NULL
--     row doesn't poison the SUM and crash the dashboard (DB010).
-- ============================================

CREATE OR REPLACE FUNCTION calculate_health_score(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_score INTEGER := 0;
  v_total_items INTEGER;
  v_active_warranties INTEGER;
  v_documented_items INTEGER;
  v_maintenance_count INTEGER;
  v_expired_count INTEGER;
BEGIN
  SELECT COUNT(*)::INTEGER INTO v_total_items
    FROM items
   WHERE user_id = p_user_id AND is_archived = FALSE;

  IF v_total_items = 0 THEN
    -- Zero items still means a deterministic score; persist it so the
    -- dashboard cache (migration 036) can rely on a row existing.
    INSERT INTO user_analytics (user_id, current_health_score, cached_health_score, cached_health_score_at)
      VALUES (p_user_id, 0, 0, NOW())
      ON CONFLICT (user_id)
      DO UPDATE SET current_health_score = 0,
                    cached_health_score = 0,
                    cached_health_score_at = NOW(),
                    updated_at = NOW();
    RETURN 0;
  END IF;

  -- Items tracked (max 30 points)
  v_score := v_score + LEAST(v_total_items * 2, 30);

  -- Active warranties (max 25 points)
  SELECT COUNT(*)::INTEGER INTO v_active_warranties
    FROM items
   WHERE user_id = p_user_id
     AND is_archived = FALSE
     AND warranty_end_date >= CURRENT_DATE;

  v_score := v_score + LEAST(v_active_warranties * 3, 25);

  -- Documents uploaded (max 20 points). All-integer math.
  SELECT COUNT(DISTINCT i.id)::INTEGER INTO v_documented_items
    FROM items i
    JOIN documents d ON d.item_id = i.id
   WHERE i.user_id = p_user_id AND i.is_archived = FALSE;

  v_score := v_score + LEAST((v_documented_items * 20) / GREATEST(v_total_items, 1), 20);

  -- Maintenance completed in last 6 months (max 15 points)
  SELECT COUNT(*)::INTEGER INTO v_maintenance_count
    FROM maintenance_history
   WHERE user_id = p_user_id
     AND completed_date >= CURRENT_DATE - INTERVAL '6 months';

  v_score := v_score + LEAST(v_maintenance_count, 15);

  -- Penalty for expired warranties (max -10 points)
  SELECT COUNT(*)::INTEGER INTO v_expired_count
    FROM items
   WHERE user_id = p_user_id
     AND is_archived = FALSE
     AND warranty_end_date < CURRENT_DATE;

  v_score := v_score - LEAST(v_expired_count * 2, 10);
  v_score := GREATEST(0, LEAST(v_score, 100));

  -- Persist + cap history at the most recent 90 entries (~3 months daily).
  -- INSERT path covers the case where the analytics row hasn't been created
  -- yet; otherwise UPDATE rewrites the row.
  INSERT INTO user_analytics (user_id, current_health_score, health_score_history,
                              cached_health_score, cached_health_score_at)
    VALUES (
      p_user_id, v_score,
      jsonb_build_array(jsonb_build_object('date', CURRENT_DATE, 'score', v_score)),
      v_score, NOW()
    )
    ON CONFLICT (user_id)
    DO UPDATE SET
      current_health_score = v_score,
      health_score_history = (
        SELECT jsonb_agg(elem)
          FROM (
            SELECT elem
              FROM (
                SELECT jsonb_array_elements(
                  user_analytics.health_score_history
                  || jsonb_build_array(jsonb_build_object('date', CURRENT_DATE, 'score', v_score))
                ) AS elem
              ) e
             ORDER BY (elem->>'date')::date DESC
             LIMIT 90
          ) capped
      ),
      cached_health_score = v_score,
      cached_health_score_at = NOW(),
      updated_at = NOW();

  RETURN v_score;
END;
$$;

COMMENT ON FUNCTION calculate_health_score IS
  'Calculates warranty health score (0-100) with integer arithmetic, search_path-pinned, history capped at 90 entries.';

CREATE OR REPLACE FUNCTION get_dashboard_stats(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_stats JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total_value',         COALESCE(SUM(price), 0),
    'total_items',         COUNT(*),
    'active_warranties',   COUNT(*) FILTER (WHERE warranty_end_date >= CURRENT_DATE),
    'expiring_soon',       COUNT(*) FILTER (WHERE warranty_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'),
    'expired',             COUNT(*) FILTER (WHERE warranty_end_date < CURRENT_DATE),
    'total_repair_value',  COALESCE(SUM(COALESCE(estimated_repair_cost, 0)), 0),
    'health_score',        (SELECT COALESCE(cached_health_score, current_health_score, 0)
                              FROM user_analytics WHERE user_id = p_user_id)
  ) INTO v_stats
    FROM items
   WHERE user_id = p_user_id AND is_archived = FALSE;

  RETURN v_stats;
END;
$$;

COMMENT ON FUNCTION get_dashboard_stats IS
  'Returns dashboard statistics with COALESCE-guarded sums so a single NULL row cannot blow up the JSONB.';

-- cleanup_old_audit_logs function exists in 031 (audit_logs immutable) — it's
-- already SECURITY DEFINER + search_path, so nothing to redo here.

-- update_updated_at_column trigger function: pin search_path
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  RAISE NOTICE 'Migration 040 complete: plpgsql functions hardened (search_path, INTEGER counts, COALESCE)';
END $$;
