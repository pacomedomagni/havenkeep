import { Router } from 'express';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';

const router = Router();
router.use(authenticate);

router.get('/me', async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `SELECT id, email, full_name, avatar_url, plan, plan_expires_at, created_at
       FROM users WHERE id = $1`,
      [req.user!.id]
    );
    res.json({ user: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

router.put('/me', async (req: AuthRequest, res, next) => {
  try {
    const { fullName, avatarUrl } = req.body;
    const result = await query(
      `UPDATE users SET full_name = COALESCE($1, full_name), avatar_url = COALESCE($2, avatar_url)
       WHERE id = $3 RETURNING id, email, full_name, avatar_url, plan`,
      [fullName, avatarUrl, req.user!.id]
    );
    res.json({ user: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

export default router;
