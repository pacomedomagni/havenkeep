import { Router } from 'express';
import { query, getClient } from '../db';
import { authenticate } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { validate } from '../middleware/validate';
import { createHomeSchema, updateHomeSchema, uuidParamSchema } from '../validators';
import { AuditService } from '../services/audit.service';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';

const router = Router();
router.use(authenticate);

// Audit Ch02-F054: explicit column allowlist on every read so internal columns
// (audit timestamps, soft-delete flags) can't leak by adding them at the
// schema level later.
const HOME_COLUMNS = `
  id, user_id, name, address, city, state, zip, home_type, move_in_date,
  created_at, updated_at
`;

// Audit Ch02-F055: canonicalize empty-string user input to NULL so the DB
// stays consistent with itself. Mobile + dashboard often send `''` when a
// caller clears a field; storing both '' and NULL means equality checks need
// COALESCE everywhere.
function nullIfEmpty(v: any): any {
  if (typeof v === 'string' && v.trim() === '') return null;
  return v;
}

// Get all homes for user
router.get('/', asyncHandler(async (req, res) => {
  const result = await query(
    `SELECT ${HOME_COLUMNS} FROM homes WHERE user_id = $1 ORDER BY created_at DESC`,
    [req.user!.id]
  );
  sendSuccess(res, result.rows);
}));

// Get single home by ID
router.get('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req, res) => {
  const result = await query(
    `SELECT ${HOME_COLUMNS} FROM homes WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user!.id]
  );

  if (result.rows.length === 0) {
    throw new AppError('Home not found', 404);
  }

  sendSuccess(res, result.rows[0]);
}));

// Create new home
router.post('/', writeRateLimiter, validate(createHomeSchema), asyncHandler(async (req, res) => {
  const { name, address, city, state, zip, homeType, moveInDate } = req.body;
  const result = await query(
    `INSERT INTO homes (user_id, name, address, city, state, zip, home_type, move_in_date)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING ${HOME_COLUMNS}`,
    [
      req.user!.id,
      name,
      nullIfEmpty(address),
      nullIfEmpty(city),
      nullIfEmpty(state),
      nullIfEmpty(zip),
      homeType,
      moveInDate,
    ],
  );
  const home = result.rows[0];

  await AuditService.logFromRequest(req, 'home.create', {
    resourceType: 'home',
    resourceId: home.id,
    description: `Created home: ${home.name}`,
  });
  sendSuccess(res, home, { status: 201 });
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
    values.push(nullIfEmpty(address));
  }
  if (city !== undefined) {
    updates.push(`city = $${paramIndex++}`);
    values.push(nullIfEmpty(city));
  }
  if (state !== undefined) {
    updates.push(`state = $${paramIndex++}`);
    values.push(nullIfEmpty(state));
  }
  if (zip !== undefined) {
    updates.push(`zip = $${paramIndex++}`);
    values.push(nullIfEmpty(zip));
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
     RETURNING ${HOME_COLUMNS}`,
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

  sendSuccess(res, home);
}));

// Delete home
router.delete('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), asyncHandler(async (req, res) => {
  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Audit Ch02-F014: only lock the target home — locking every user home
    // serialized concurrent home edits unnecessarily. The "last home"
    // invariant is enforced by a separate count below, which is enough
    // because the home delete itself is a single statement.
    const targetRes = await client.query(
      `SELECT id, name FROM homes WHERE id = $1 AND user_id = $2 FOR UPDATE`,
      [req.params.id, req.user!.id],
    );
    if (targetRes.rows.length === 0) {
      throw new AppError('Home not found', 404);
    }
    const home = targetRes.rows[0];

    // Audit Ch02-F015: pick the fallback home deterministically (oldest
    // remaining) so the operation is replay-safe in audit logs and in tests.
    const fallbackRes = await client.query(
      `SELECT id, name FROM homes
       WHERE user_id = $1 AND id <> $2
       ORDER BY created_at ASC, id ASC
       LIMIT 1`,
      [req.user!.id, req.params.id],
    );
    const fallback = fallbackRes.rows[0] ?? null;

    // Audit Ch02-F016: refuse a last-home delete with a generic message that
    // does not leak the precise count. The old "Cannot delete your only
    // home" wording made the count observable to non-owners via timing /
    // 4xx vs 5xx differentiation.
    if (!fallback) {
      throw new AppError('Cannot delete this home; create another home first.', 409);
    }

    // Reassign items in the deleted home to the deterministic fallback.
    await client.query(
      `UPDATE items SET home_id = $1 WHERE home_id = $2 AND user_id = $3`,
      [fallback.id, req.params.id, req.user!.id],
    );

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
        items_reassigned_to: fallback.id,
      },
    });

    sendMessage(res, 'Home deleted successfully');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

export default router;
