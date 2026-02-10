import { Router } from 'express';
import { query } from '../db';
import { authenticate, AuthRequest, requireAdmin } from '../middleware/auth';

const router = Router();
router.use(authenticate);
router.use(requireAdmin);

router.get('/stats', async (req: AuthRequest, res, next) => {
  try {
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium') as premium_users,
        (SELECT COUNT(*) FROM items) as total_items,
        (SELECT COALESCE(SUM(price), 0) FROM items) as total_value
    `);
    res.json({ stats: stats.rows[0] });
  } catch (error) {
    next(error);
  }
});

router.get('/users', async (req: AuthRequest, res, next) => {
  try {
    const result = await query(`SELECT * FROM user_stats ORDER BY created_at DESC LIMIT 100`);
    res.json({ users: result.rows });
  } catch (error) {
    next(error);
  }
});

export default router;
