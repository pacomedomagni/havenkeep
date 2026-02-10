import { Router } from 'express';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';

const router = Router();
router.use(authenticate);

router.get('/', async (req: AuthRequest, res, next) => {
  try {
    const { itemId } = req.query;
    const result = await query(
      `SELECT * FROM documents WHERE user_id = $1 AND item_id = $2 ORDER BY created_at DESC`,
      [req.user!.id, itemId]
    );
    res.json({ documents: result.rows });
  } catch (error) {
    next(error);
  }
});

export default router;
