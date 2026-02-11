import { Router } from 'express';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { validate } from '../middleware/validate';
import { createItemSchema, updateItemSchema, paginationSchema, uuidParamSchema } from '../validators';

const router = Router();

// All routes require authentication
router.use(authenticate);

// Whitelist of allowed update fields to prevent SQL injection
const ALLOWED_UPDATE_FIELDS = new Set([
  'name', 'brand', 'model_number', 'serial_number', 'category', 'room',
  'purchase_date', 'store', 'price', 'warranty_months', 'warranty_type',
  'warranty_provider', 'notes', 'is_archived', 'product_image_url', 'barcode'
]);

// Get all items for user (with pagination)
router.get('/', validate(paginationSchema, 'query'), async (req: AuthRequest, res, next) => {
  try {
    const { homeId, archived, page, limit } = req.query as any;
    const offset = (page - 1) * limit;

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
      sql += ` AND is_archived = $${params.length + 1}`;
      params.push(archived === 'true');
    }

    sql += ` ORDER BY warranty_end_date ASC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    // Get total count
    let countSql = `SELECT COUNT(*) FROM items WHERE user_id = $1`;
    const countParams: any[] = [req.user!.id];
    if (homeId) {
      countSql += ` AND home_id = $2`;
      countParams.push(homeId);
    }
    if (archived !== undefined) {
      countSql += ` AND is_archived = $${countParams.length + 1}`;
      countParams.push(archived === 'true');
    }

    const [result, countResult] = await Promise.all([
      query(sql, params),
      query(countSql, countParams),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    res.json({
      items: result.rows,
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

// Get single item
router.get('/:id', validate(uuidParamSchema, 'params'), async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `SELECT * FROM items WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError(404, 'Item not found');
    }

    res.json({ item: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Create item
router.post('/', validate(createItemSchema), async (req: AuthRequest, res, next) => {
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
    } = req.body;

    // Check free plan limit (10 items)
    if (req.user!.plan === 'free') {
      const countResult = await query(
        `SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`,
        [req.user!.id]
      );

      if (parseInt(countResult.rows[0].count, 10) >= 10) {
        throw new AppError(403, 'Free plan limit reached. Upgrade to Premium for unlimited items.');
      }
    }

    // Verify home belongs to user
    const homeResult = await query(
      `SELECT id FROM homes WHERE id = $1 AND user_id = $2`,
      [homeId, req.user!.id]
    );

    if (homeResult.rows.length === 0) {
      throw new AppError(404, 'Home not found');
    }

    // Calculate warranty end date
    const purchaseDateObj = new Date(purchaseDate);
    if (isNaN(purchaseDateObj.getTime())) {
      throw new AppError(400, 'Invalid purchase date');
    }
    const warrantyEndDate = new Date(purchaseDateObj);
    const expectedMonth = (warrantyEndDate.getMonth() + warrantyMonths) % 12;
    warrantyEndDate.setMonth(warrantyEndDate.getMonth() + warrantyMonths);
    // Handle day overflow (e.g., Jan 31 + 1 month = Mar 3 instead of Feb 28)
    if (warrantyEndDate.getMonth() !== expectedMonth) {
      warrantyEndDate.setDate(0); // Set to last day of previous month
    }

    const result = await query(
      `INSERT INTO items (
        user_id, home_id, name, brand, model_number, serial_number,
        category, room, purchase_date, store, price,
        warranty_months, warranty_end_date, warranty_type, warranty_provider, notes,
        product_image_url, barcode
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
      RETURNING *`,
      [
        req.user!.id, homeId, name, brand, modelNumber, serialNumber,
        category, room, purchaseDate, store, price,
        warrantyMonths, warrantyEndDate, warrantyType,
        warrantyProvider, notes, productImageUrl, barcode
      ]
    );

    res.status(201).json({ item: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Update item - FIXED SQL INJECTION
router.put('/:id', validate(uuidParamSchema, 'params'), validate(updateItemSchema), async (req: AuthRequest, res, next) => {
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
      throw new AppError(400, 'No valid fields to update');
    }

    // Recalculate warranty_end_date when warrantyMonths or purchaseDate changes
    if (updates.warrantyMonths !== undefined || updates.purchaseDate !== undefined) {
      // If purchaseDate is provided, use it; otherwise fetch existing from DB
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
        const warrantyEndDate = new Date(purchaseDateForCalc);
        const expectedMonth = (warrantyEndDate.getMonth() + warrantyMonthsForCalc) % 12;
        warrantyEndDate.setMonth(warrantyEndDate.getMonth() + warrantyMonthsForCalc);
        // Handle day overflow (e.g., Jan 31 + 1 month = Mar 3 instead of Feb 28)
        if (warrantyEndDate.getMonth() !== expectedMonth) {
          warrantyEndDate.setDate(0); // Set to last day of previous month
        }
        fields.push(`warranty_end_date = $${paramCount}`);
        values.push(warrantyEndDate);
        paramCount++;
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
      throw new AppError(404, 'Item not found');
    }

    res.json({ item: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Delete item
router.delete('/:id', validate(uuidParamSchema, 'params'), async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `DELETE FROM items WHERE id = $1 AND user_id = $2 RETURNING id`,
      [req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError(404, 'Item not found');
    }

    res.json({ message: 'Item deleted successfully' });
  } catch (error) {
    next(error);
  }
});

export default router;
