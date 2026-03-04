import { Router } from 'express';
import { getClient, query, pool } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { validate } from '../middleware/validate';
import { createItemSchema, updateItemSchema, paginationSchema, uuidParamSchema } from '../validators';
import { AuditService } from '../services/audit.service';
import { config } from '../config';
import { writeRateLimiter } from '../middleware/rateLimiter';

const router = Router();

/**
 * Safely add months to a date, handling day overflow.
 * e.g., Jan 31 + 1 month = Feb 28 (not Mar 3)
 */
function addMonthsSafe(date: Date, months: number): Date {
  const result = new Date(date);
  const targetMonth = result.getMonth() + months;
  result.setMonth(targetMonth);
  // If the day overflowed (e.g. 31 -> next month), go back to last day of target month
  const expectedMonth = ((date.getMonth() + months) % 12 + 12) % 12;
  if (result.getMonth() !== expectedMonth) {
    result.setDate(0); // Last day of previous month
  }
  return result;
}

// All routes require authentication
router.use(authenticate);

// Whitelist of allowed update fields to prevent SQL injection
// NOTE: added_via is intentionally excluded — it is a write-once audit field
const ALLOWED_UPDATE_FIELDS = new Set([
  'name', 'brand', 'model_number', 'serial_number', 'category', 'room',
  'purchase_date', 'store', 'price', 'warranty_months', 'warranty_type',
  'warranty_provider', 'notes', 'is_archived', 'product_image_url', 'barcode',
]);

// Export all items as CSV (streaming — avoids buffering all rows in memory)
router.get('/export.csv', async (req: AuthRequest, res, next) => {
  try {
    const headers = [
      'Name', 'Brand', 'Category', 'Room', 'Model Number', 'Serial Number',
      'Purchase Date', 'Store', 'Price', 'Warranty Type', 'Warranty Months',
      'Warranty End Date', 'Notes', 'Archived', 'Added Via', 'Created At',
    ];

    // Simple CSV serialization with RFC 4180 quoting
    function escapeCsv(val: any): string {
      if (val == null) return '';
      const str = String(val);
      if (str.includes(',') || str.includes('"') || str.includes('\n')) {
        return `"${str.replace(/"/g, '""')}"`;
      }
      return str;
    }

    function formatRow(item: any): string {
      return [
        escapeCsv(item.name),
        escapeCsv(item.brand),
        escapeCsv(item.category),
        escapeCsv(item.room),
        escapeCsv(item.model_number),
        escapeCsv(item.serial_number),
        escapeCsv(item.purchase_date ? new Date(item.purchase_date).toISOString().split('T')[0] : ''),
        escapeCsv(item.store),
        escapeCsv(item.price != null ? Number(item.price).toFixed(2) : ''),
        escapeCsv(item.warranty_type),
        escapeCsv(item.warranty_months),
        escapeCsv(item.warranty_end_date ? new Date(item.warranty_end_date).toISOString().split('T')[0] : ''),
        escapeCsv(item.notes),
        escapeCsv(item.is_archived ? 'Yes' : 'No'),
        escapeCsv(item.added_via),
        escapeCsv(item.created_at ? new Date(item.created_at).toISOString().split('T')[0] : ''),
      ].join(',');
    }

    const date = new Date().toISOString().split('T')[0];
    const filename = `havenkeep_items_${date}.csv`;

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Transfer-Encoding', 'chunked');

    // Audit log the export
    await AuditService.logFromRequest(req, 'item.export', {
      resourceType: 'item',
      description: 'User exported items as CSV',
    });

    // Write BOM + header row
    res.write('\uFEFF' + headers.join(',') + '\r\n');

    // Stream rows in chunks using LIMIT/OFFSET to avoid loading all into memory
    const CHUNK_SIZE = 500;
    let offset = 0;
    let hasMore = true;

    while (hasMore) {
      const result = await query(
        `SELECT name, brand, category, room, model_number, serial_number,
                purchase_date, store, price, warranty_type, warranty_months,
                warranty_end_date, notes, is_archived, added_via, created_at
         FROM items
         WHERE user_id = $1
         ORDER BY is_archived ASC, warranty_end_date ASC NULLS LAST
         LIMIT $2 OFFSET $3`,
        [req.user!.id, CHUNK_SIZE, offset]
      );

      for (const row of result.rows) {
        res.write(formatRow(row) + '\r\n');
      }

      if (result.rows.length < CHUNK_SIZE) {
        hasMore = false;
      } else {
        offset += CHUNK_SIZE;
      }
    }

    res.end();
  } catch (error) {
    // If headers already sent, destroy the response; otherwise pass to error handler
    if (res.headersSent) {
      res.destroy();
    } else {
      next(error);
    }
  }
});

// Get active item count (for free plan limit check)
router.get('/count', async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`,
      [req.user!.id]
    );

    res.json({
      count: parseInt(result.rows[0].count, 10),
    });
  } catch (error) {
    next(error);
  }
});

// Get all items for user (with pagination)
router.get('/', validate(paginationSchema, 'query'), async (req: AuthRequest, res, next) => {
  try {
    const { homeId, archived, addedVia, page, limit } = req.query as any;

    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const pageNum = Math.max(1, parseInt(page as string, 10) || 1);
    const limitNum = Math.min(100, Math.max(1, parseInt(limit as string, 10) || 20));
    const offset = (pageNum - 1) * limitNum;

    let sql = `
      SELECT * FROM items
      WHERE user_id = $1
    `;
    const params: any[] = [req.user!.id];

    if (homeId) {
      sql += ` AND home_id = $${params.length + 1}`;
      params.push(homeId);
    }

    if (archived !== undefined) {
      const isArchived = archived === 'true' || archived === true;
      sql += ` AND is_archived = $${params.length + 1}`;
      params.push(isArchived);
    }

    if (addedVia) {
      sql += ` AND added_via = $${params.length + 1}`;
      params.push(addedVia);
    }

    sql += ` ORDER BY warranty_end_date ASC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limitNum, offset);

    // Get total count
    let countSql = `SELECT COUNT(*) FROM items WHERE user_id = $1`;
    const countParams: any[] = [req.user!.id];
    if (homeId) {
      countSql += ` AND home_id = $${countParams.length + 1}`;
      countParams.push(homeId);
    }
    if (archived !== undefined) {
      const isArchived = archived === 'true' || archived === true;
      countSql += ` AND is_archived = $${countParams.length + 1}`;
      countParams.push(isArchived);
    }
    if (addedVia) {
      countSql += ` AND added_via = $${countParams.length + 1}`;
      countParams.push(addedVia);
    }

    const [result, countResult] = await Promise.all([
      query(sql, params),
      query(countSql, countParams),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    // BE-10: Division by zero is safe here because limitNum >= 1 (clamped above)
    res.json({
      items: result.rows,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total,
        totalPages: Math.ceil(total / limitNum),
      },
    });
  } catch (error) {
    next(error);
  }
});

// Default expected lifespan (in years) by category, used when the item has no explicit value
const CATEGORY_DEFAULT_LIFESPAN: Record<string, number> = {
  appliance: 12,
  electronics: 5,
  furniture: 15,
  hvac: 15,
  plumbing: 20,
  roofing: 25,
  flooring: 15,
  outdoor: 10,
  other: 10,
};

// Get single item
router.get('/:id', validate(uuidParamSchema, 'params'), async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `SELECT * FROM items WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    const item = result.rows[0];

    // Compute lifespan percentage
    const expectedLifespan: number | null =
      item.expected_lifespan_years ??
      CATEGORY_DEFAULT_LIFESPAN[item.category] ??
      null;

    let lifespanPercentage: number | null = null;

    if (expectedLifespan && item.purchase_date) {
      const purchaseDate = new Date(item.purchase_date);
      const now = new Date();
      const yearsSincePurchase =
        (now.getTime() - purchaseDate.getTime()) / (1000 * 60 * 60 * 24 * 365.25);
      lifespanPercentage = Math.min(100, Math.round((yearsSincePurchase / expectedLifespan) * 100));
    }

    res.json({
      item: {
        ...item,
        expected_lifespan_years: expectedLifespan,
        lifespan_percentage: lifespanPercentage,
      },
    });
  } catch (error) {
    next(error);
  }
});

// Create item
router.post('/', writeRateLimiter, validate(createItemSchema), async (req: AuthRequest, res, next) => {
  const client = await getClient();
  try {
    const {
      homeId,
      name,
      brand,
      modelNumber,
      serialNumber,
      category,
      room,
      purchaseDate,
      store,
      price,
      warrantyMonths,
      warrantyType,
      warrantyProvider,
      notes,
      productImageUrl,
      barcode,
      addedVia,
    } = req.body;

    await client.query('BEGIN');

    // Check free plan limit (5 items) with a user-level lock to prevent races
    if (req.user!.plan === 'free') {
      await client.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user!.id]);

      const countResult = await client.query(
        `SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`,
        [req.user!.id]
      );

      if (parseInt(countResult.rows[0].count, 10) >= config.freeTier.itemLimit) {
        throw new AppError('Free plan limit reached. Upgrade to Premium for unlimited items.', 403);
      }
    }

    // Verify home belongs to user
    const homeResult = await client.query(
      `SELECT id FROM homes WHERE id = $1 AND user_id = $2`,
      [homeId, req.user!.id]
    );

    if (homeResult.rows.length === 0) {
      throw new AppError('Home not found', 404);
    }

    // Calculate warranty end date
    const purchaseDateObj = new Date(purchaseDate);
    if (isNaN(purchaseDateObj.getTime())) {
      throw new AppError('Invalid purchase date', 400);
    }
    const warrantyEndDate = addMonthsSafe(purchaseDateObj, warrantyMonths);

    const result = await client.query(
      `INSERT INTO items (
        user_id, home_id, name, brand, model_number, serial_number,
        category, room, purchase_date, store, price,
        warranty_months, warranty_end_date, warranty_type, warranty_provider, notes,
        product_image_url, barcode, added_via
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
      RETURNING *`,
      [
        req.user!.id, homeId, name, brand, modelNumber, serialNumber,
        category, room, purchaseDate, store, price,
        warrantyMonths, warrantyEndDate, warrantyType,
        warrantyProvider, notes, productImageUrl, barcode, addedVia || 'manual'
      ]
    );

    await client.query('COMMIT');

    const item = result.rows[0];

    // Fire-and-forget: stamp first_item_added_at on any active gift for this user
    pool.query(
      `UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE activated_user_id = $1 AND is_activated = TRUE`,
      [req.user!.id]
    ).catch(() => { /* non-critical */ });

    // Audit log: item created
    await AuditService.logFromRequest(req, 'item.create', {
      resourceType: 'item',
      resourceId: item.id,
      description: `Created item: ${item.name}`,
      metadata: {
        category: item.category,
        warranty_months: item.warranty_months,
      },
    });

    res.status(201).json({ item });
  } catch (error) {
    await client.query('ROLLBACK');
    next(error);
  } finally {
    client.release();
  }
});

// Update item - FIXED SQL INJECTION
router.put('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), validate(updateItemSchema), async (req: AuthRequest, res, next) => {
  try {
    const { id } = req.params;
    const updates = req.body;

    // Whitelist-based field validation to prevent SQL injection
    const fields: string[] = [];
    const values: any[] = [];
    let paramCount = 1;

    // Map camelCase to snake_case and validate
    const fieldMapping: Record<string, string> = {
      name: 'name',
      brand: 'brand',
      modelNumber: 'model_number',
      serialNumber: 'serial_number',
      category: 'category',
      room: 'room',
      purchaseDate: 'purchase_date',
      store: 'store',
      price: 'price',
      warrantyMonths: 'warranty_months',
      warrantyType: 'warranty_type',
      warrantyProvider: 'warranty_provider',
      notes: 'notes',
      isArchived: 'is_archived',
      productImageUrl: 'product_image_url',
      barcode: 'barcode',
      // addedVia intentionally excluded — write-once audit field
    };

    for (const [camelKey, value] of Object.entries(updates)) {
      const dbField = fieldMapping[camelKey];
      if (dbField && ALLOWED_UPDATE_FIELDS.has(dbField)) {
        fields.push(`${dbField} = $${paramCount}`);
        values.push(value);
        paramCount++;
      }
    }

    if (fields.length === 0) {
      throw new AppError('No valid fields to update', 400);
    }

    // Recalculate warranty_end_date when warrantyMonths or purchaseDate changes
    if (updates.warrantyMonths !== undefined || updates.purchaseDate !== undefined) {
      // BE-28: If purchaseDate is explicitly set to null/empty, also clear warranty_end_date
      if (updates.purchaseDate === null || updates.purchaseDate === '' || (updates.purchaseDate === undefined && updates.warrantyMonths !== undefined)) {
        // Only clear if purchaseDate is explicitly null/empty
        if (updates.purchaseDate === null || updates.purchaseDate === '') {
          fields.push(`warranty_end_date = $${paramCount}`);
          values.push(null);
          paramCount++;
        } else {
          // warrantyMonths changed but purchaseDate was not provided — fetch existing
          const existing = await query(
            `SELECT purchase_date, warranty_months FROM items WHERE id = $1 AND user_id = $2`,
            [id, req.user!.id]
          );
          if (existing.rows.length > 0 && existing.rows[0].purchase_date) {
            const purchaseDateForCalc = new Date(existing.rows[0].purchase_date);
            const warrantyMonthsForCalc = updates.warrantyMonths;
            const warrantyEndDate = addMonthsSafe(purchaseDateForCalc, warrantyMonthsForCalc);
            fields.push(`warranty_end_date = $${paramCount}`);
            values.push(warrantyEndDate);
            paramCount++;
          }
        }
      } else {
        // purchaseDate is provided and truthy — recalculate
        let purchaseDateForCalc: Date | null = null;
        let warrantyMonthsForCalc: number | null = null;

        if (updates.purchaseDate) {
          purchaseDateForCalc = new Date(updates.purchaseDate);
        }
        if (updates.warrantyMonths !== undefined) {
          warrantyMonthsForCalc = updates.warrantyMonths;
        }

        // If we only have one value, fetch the other from the existing item
        if (!purchaseDateForCalc || warrantyMonthsForCalc === null) {
          const existing = await query(
            `SELECT purchase_date, warranty_months FROM items WHERE id = $1 AND user_id = $2`,
            [id, req.user!.id]
          );
          if (existing.rows.length > 0) {
            if (!purchaseDateForCalc) {
              purchaseDateForCalc = new Date(existing.rows[0].purchase_date);
            }
            if (warrantyMonthsForCalc === null) {
              warrantyMonthsForCalc = existing.rows[0].warranty_months;
            }
          }
        }

        if (purchaseDateForCalc && warrantyMonthsForCalc !== null) {
          const warrantyEndDate = addMonthsSafe(purchaseDateForCalc, warrantyMonthsForCalc);
          fields.push(`warranty_end_date = $${paramCount}`);
          values.push(warrantyEndDate);
          paramCount++;
        }
      }
    }

    // Always update the timestamp
    fields.push('updated_at = NOW()');

    // BE-16: archived_at is kept in sync with is_archived here.
    // The DB should also have a CHECK constraint enforcing:
    //   (is_archived = FALSE AND archived_at IS NULL) OR (is_archived = TRUE AND archived_at IS NOT NULL)
    // which is being added in the migration.
    if (updates.isArchived !== undefined) {
      if (updates.isArchived) {
        fields.push('archived_at = NOW()');
      } else {
        fields.push('archived_at = NULL');
      }
    }

    values.push(id, req.user!.id);

    const result = await query(
      `UPDATE items SET ${fields.join(', ')}
       WHERE id = $${paramCount} AND user_id = $${paramCount + 1}
       RETURNING *`,
      values
    );

    if (result.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    const item = result.rows[0];

    // Audit log: item updated
    await AuditService.logFromRequest(req, 'item.update', {
      resourceType: 'item',
      resourceId: item.id,
      description: `Updated item: ${item.name}`,
      metadata: {
        updated_fields: Object.keys(updates),
      },
    });

    res.json({ item });
  } catch (error) {
    next(error);
  }
});

// Delete item
router.delete('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), async (req: AuthRequest, res, next) => {
  try {
    // Get item details before deleting for audit log
    const itemResult = await query(
      `SELECT id, name, category FROM items WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (itemResult.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    const item = itemResult.rows[0];

    const result = await query(
      `DELETE FROM items WHERE id = $1 AND user_id = $2 RETURNING id`,
      [req.params.id, req.user!.id]
    );

    // Audit log: item deleted
    await AuditService.logFromRequest(req, 'item.delete', {
      resourceType: 'item',
      resourceId: item.id,
      description: `Deleted item: ${item.name}`,
      metadata: {
        category: item.category,
      },
    });

    res.json({ message: 'Item deleted successfully' });
  } catch (error) {
    next(error);
  }
});

export default router;
