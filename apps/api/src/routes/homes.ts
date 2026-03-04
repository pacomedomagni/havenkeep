import { Router } from 'express';
import { query, getClient } from '../db';
import { authenticate } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { validate } from '../middleware/validate';
import { createHomeSchema, updateHomeSchema, uuidParamSchema } from '../validators';
import { AuditService } from '../services/audit.service';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { asyncHandler } from '../utils/async-handler';

const router = Router();
router.use(authenticate);

// Get all homes for user
router.get('/', asyncHandler(async (req, res) => {
  const result = await query(
    `SELECT * FROM homes WHERE user_id = $1 ORDER BY created_at DESC`,
    [req.user!.id]
  );
  res.json({ homes: result.rows });
}));

// Get single home by ID
router.get('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req, res) => {
  const result = await query(
    `SELECT * FROM homes WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user!.id]
  );

  if (result.rows.length === 0) {
    throw new AppError('Home not found', 404);
  }

  res.json({ home: result.rows[0] });
}));

// Create new home
router.post('/', writeRateLimiter, validate(createHomeSchema), asyncHandler(async (req, res) => {
  const { name, address, city, state, zip, homeType, moveInDate } = req.body;
  const result = await query(
    `INSERT INTO homes (user_id, name, address, city, state, zip, home_type, move_in_date)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
    [req.user!.id, name, address, city, state, zip, homeType, moveInDate]
  );
  const home = result.rows[0];

  await AuditService.logFromRequest(req, 'home.create', {
    resourceType: 'home',
    resourceId: home.id,
    description: `Created home: ${home.name}`,
  });
  res.status(201).json({ home });
}));

// Update home
router.put('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), validate(updateHomeSchema), asyncHandler(async (req, res) => {
  const { name, address, city, state, zip, homeType, moveInDate } = req.body;
  const updates: string[] = [];
  const values: any[] = [];
  let paramIndex = 1;

  if (name !== undefined) {
    updates.push(`name = $${paramIndex++}`);
    values.push(name);
  }
  if (address !== undefined) {
    updates.push(`address = $${paramIndex++}`);
    values.push(address);
  }
  if (city !== undefined) {
    updates.push(`city = $${paramIndex++}`);
    values.push(city);
  }
  if (state !== undefined) {
    updates.push(`state = $${paramIndex++}`);
    values.push(state);
  }
  if (zip !== undefined) {
    updates.push(`zip = $${paramIndex++}`);
    values.push(zip);
  }
  if (homeType !== undefined) {
    updates.push(`home_type = $${paramIndex++}`);
    values.push(homeType);
  }
  if (moveInDate !== undefined) {
    updates.push(`move_in_date = $${paramIndex++}`);
    values.push(moveInDate);
  }

  if (updates.length === 0) {
    throw new AppError('No fields to update', 400);
  }

  values.push(req.params.id, req.user!.id);

  const result = await query(
    `UPDATE homes SET
      ${updates.join(', ')},
      updated_at = NOW()
     WHERE id = $${paramIndex++} AND user_id = $${paramIndex++}
     RETURNING *`,
    values
  );

  if (result.rows.length === 0) {
    throw new AppError('Home not found', 404);
  }

  const home = result.rows[0];
  await AuditService.logFromRequest(req, 'home.update', {
    resourceType: 'home',
    resourceId: home.id,
    description: `Updated home: ${home.name}`,
    metadata: {
      updated_fields: Object.keys(req.body || {}),
    },
  });

  res.json({ home });
}));

// Delete home
router.delete('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), asyncHandler(async (req, res) => {
  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Lock all of the user's homes to prevent TOCTOU race conditions
    const lockedHomes = await client.query(
      `SELECT id, name FROM homes WHERE user_id = $1 FOR UPDATE`,
      [req.user!.id]
    );

    // Prevent deleting the last home
    if (lockedHomes.rows.length <= 1) {
      throw new AppError('Cannot delete your only home. You must have at least one home.', 400);
    }

    // Verify the specific home exists and belongs to the user
    const home = lockedHomes.rows.find((h: any) => h.id === req.params.id);
    if (!home) {
      throw new AppError('Home not found', 404);
    }

    // Reassign any items in this home to the user's first remaining home (#18)
    const firstRemainingHome = lockedHomes.rows.find((h: any) => h.id !== req.params.id);
    if (firstRemainingHome) {
      await client.query(
        `UPDATE items SET home_id = $1 WHERE home_id = $2 AND user_id = $3`,
        [firstRemainingHome.id, req.params.id, req.user!.id]
      );
    }

    // Delete the home
    await client.query(
      `DELETE FROM homes WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    await client.query('COMMIT');

    await AuditService.logFromRequest(req, 'home.delete', {
      resourceType: 'home',
      resourceId: home.id,
      description: `Deleted home: ${home.name}`,
      metadata: {
        items_reassigned_to: firstRemainingHome?.id ?? null,
      },
    });

    res.json({ message: 'Home deleted successfully' });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

export default router;
