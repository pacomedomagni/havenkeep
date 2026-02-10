import { Router } from 'express';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';

const router = Router();

// All routes require authentication
router.use(authenticate);

// Get all items for user
router.get('/', async (req: AuthRequest, res, next) => {
  try {
    const { homeId, archived } = req.query;
    
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
    
    sql += ` ORDER BY warranty_end_date ASC`;
    
    const result = await query(sql, params);
    
    res.json({ items: result.rows });
  } catch (error) {
    next(error);
  }
});

// Get single item
router.get('/:id', async (req: AuthRequest, res, next) => {
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
router.post('/', async (req: AuthRequest, res, next) => {
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
    } = req.body;
    
    // Validation
    if (!homeId || !name || !purchaseDate) {
      throw new AppError(400, 'Missing required fields');
    }
    
    // Check free plan limit (10 items)
    if (req.user!.plan === 'free') {
      const countResult = await query(
        `SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`,
        [req.user!.id]
      );
      
      if (parseInt(countResult.rows[0].count) >= 10) {
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
    const warrantyEndDate = new Date(purchaseDateObj);
    warrantyEndDate.setMonth(warrantyEndDate.getMonth() + (warrantyMonths || 12));
    
    const result = await query(
      `INSERT INTO items (
        user_id, home_id, name, brand, model_number, serial_number,
        category, room, purchase_date, store, price,
        warranty_months, warranty_end_date, warranty_type, warranty_provider, notes
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
      RETURNING *`,
      [
        req.user!.id, homeId, name, brand, modelNumber, serialNumber,
        category || 'other', room, purchaseDate, store, price,
        warrantyMonths || 12, warrantyEndDate, warrantyType || 'manufacturer',
        warrantyProvider, notes
      ]
    );
    
    res.status(201).json({ item: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Update item
router.put('/:id', async (req: AuthRequest, res, next) => {
  try {
    const { id } = req.params;
    const updates = req.body;
    
    // Build update query dynamically
    const fields = [];
    const values = [];
    let paramCount = 1;
    
    for (const [key, value] of Object.entries(updates)) {
      if (key !== 'id' && key !== 'user_id' && key !== 'created_at') {
        fields.push(`${key} = $${paramCount}`);
        values.push(value);
        paramCount++;
      }
    }
    
    if (fields.length === 0) {
      throw new AppError(400, 'No fields to update');
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
router.delete('/:id', async (req: AuthRequest, res, next) => {
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
