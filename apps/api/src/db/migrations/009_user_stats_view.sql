-- Create analytics view for admin user listing

CREATE OR REPLACE VIEW user_stats AS
SELECT
  u.id,
  u.email,
  u.full_name,
  u.plan,
  u.created_at,
  COUNT(DISTINCT i.id) AS total_items,
  COALESCE(SUM(i.price), 0) AS total_value,
  MAX(i.created_at) AS last_item_created,
  MAX(i.updated_at) AS last_activity
FROM users u
LEFT JOIN items i ON i.user_id = u.id AND i.is_archived = FALSE
GROUP BY u.id, u.email, u.full_name, u.plan, u.created_at;
