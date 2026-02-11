import { Router } from 'express';
import { query } from '../db';
import { authenticate } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { validate } from '../middleware/validate';
import { createHomeSchema, updateHomeSchema, uuidParamSchema } from '../validators';

const router = Router();
router.use(authenticate);

// Get all homes for user
router.get('/', async (req, res, next) => {
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

// Get single home by ID
router.get('/:id', validate(uuidParamSchema, 'params'), async (req, res, next) => {
  try {
    const result = await query(
      `SELECT * FROM homes WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError(404, 'Home not found');
    }

    res.json({ home: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Create new home
router.post('/', validate(createHomeSchema), async (req, res, next) => {
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

// Update home
router.put('/:id', validate(uuidParamSchema, 'params'), validate(updateHomeSchema), async (req, res, next) => {
  try {
    const { name, address, city, state, zip, homeType, moveInDate } = req.body;

    const result = await query(
      `UPDATE homes SET
        name = COALESCE($1, name),
        address = COALESCE($2, address),
        city = COALESCE($3, city),
        state = COALESCE($4, state),
        zip = COALESCE($5, zip),
        home_type = COALESCE($6, home_type),
        move_in_date = COALESCE($7, move_in_date)
       WHERE id = $8 AND user_id = $9
       RETURNING *`,
      [name, address, city, state, zip, homeType, moveInDate, req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError(404, 'Home not found');
    }

    res.json({ home: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Delete home
router.delete('/:id', validate(uuidParamSchema, 'params'), async (req, res, next) => {
  try {
    // Prevent deleting the last home
    const countResult = await query(
      `SELECT COUNT(*) FROM homes WHERE user_id = $1`,
      [req.user!.id]
    );

    if (parseInt(countResult.rows[0].count) <= 1) {
      throw new AppError(400, 'Cannot delete your only home. You must have at least one home.');
    }

    const result = await query(
      `DELETE FROM homes WHERE id = $1 AND user_id = $2 RETURNING id`,
      [req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError(404, 'Home not found');
    }

    res.json({ message: 'Home deleted successfully' });
  } catch (error) {
    next(error);
  }
});

export default router;
