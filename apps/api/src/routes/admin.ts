import { Router } from 'express';
import { query } from '../db';
import { authenticate, requireAdmin } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { paginationSchema } from '../validators';

const router = Router();
router.use(authenticate);
router.use(requireAdmin);

// Admin stats overview
router.get('/stats', async (req, res, next) => {
  try {
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium') as premium_users,
        (SELECT COUNT(*) FROM items) as total_items,
        (SELECT COALESCE(SUM(price), 0) FROM items) as total_value,
        (SELECT COUNT(*) FROM partners WHERE is_active = TRUE) as active_partners,
        (SELECT COUNT(*) FROM partner_gifts) as total_gifts,
        (SELECT COUNT(*) FROM warranty_claims) as total_claims
    `);
    res.json({ stats: stats.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Admin user listing with pagination
router.get('/users', validate(paginationSchema, 'query'), async (req, res, next) => {
  try {
    const { page, limit } = req.query as any;
    const offset = (page - 1) * limit;

    const [result, countResult] = await Promise.all([
      query(
        `SELECT * FROM user_stats ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
        [limit, offset]
      ),
      query(`SELECT COUNT(*) FROM users`),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    res.json({
      users: result.rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    next(error);
  }
});

export default router;
