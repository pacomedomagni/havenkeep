import { Router } from 'express';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';

const router = Router();
router.use(authenticate);

router.get('/', async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `SELECT * FROM homes WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.user!.id]
    );
    res.json({ homes: result.rows });
  } catch (error) {
    next(error);
  }
});

router.post('/', async (req: AuthRequest, res, next) => {
  try {
    const { name, address, city, state, zip, homeType, moveInDate } = req.body;
    const result = await query(
      `INSERT INTO homes (user_id, name, address, city, state, zip, home_type, move_in_date)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [req.user!.id, name, address, city, state, zip, homeType, moveInDate]
    );
    res.status(201).json({ home: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

export default router;
