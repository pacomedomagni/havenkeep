"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const errors_1 = require("../utils/errors");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const audit_service_1 = require("../services/audit.service");
const config_1 = require("../config");
const rateLimiter_1 = require("../middleware/rateLimiter");
const async_handler_1 = require("../utils/async-handler");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
/**
 * Safely add months to a date, handling day overflow.
 * e.g., Jan 31 + 1 month = Feb 28 (not Mar 3)
 */
function addMonthsSafe(date, months) {
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
router.use(auth_1.authenticate);
// Whitelist of allowed update fields to prevent SQL injection
// NOTE: added_via is intentionally excluded — it is a write-once audit field
const ALLOWED_UPDATE_FIELDS = new Set([
    'name', 'brand', 'model_number', 'serial_number', 'category', 'room',
    'purchase_date', 'store', 'price', 'warranty_months', 'warranty_type',
    'warranty_provider', 'notes', 'is_archived', 'product_image_url', 'barcode',
    'home_id', 'installation_date', 'last_maintenance_date', 'next_maintenance_due',
]);
// Export all items as CSV (streaming — avoids buffering all rows in memory)
// NOTE: This handler keeps a manual try/catch because it needs to call res.destroy()
// when headers are already sent, which asyncHandler cannot handle.
router.get('/export.csv', async (req, res, next) => {
    try {
        const headers = [
            'Name', 'Brand', 'Category', 'Room', 'Model Number', 'Serial Number',
            'Purchase Date', 'Store', 'Price', 'Warranty Type', 'Warranty Months',
            'Warranty End Date', 'Notes', 'Archived', 'Added Via', 'Created At',
        ];
        // Simple CSV serialization with RFC 4180 quoting
        function escapeCsv(val) {
            if (val == null)
                return '';
            const str = String(val);
            if (str.includes(',') || str.includes('"') || str.includes('\n')) {
                return `"${str.replace(/"/g, '""')}"`;
            }
            return str;
        }
        function formatRow(item) {
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
        await audit_service_1.AuditService.logFromRequest(req, 'item.export', {
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
            const result = await (0, db_1.query)(`SELECT name, brand, category, room, model_number, serial_number,
                purchase_date, store, price, warranty_type, warranty_months,
                warranty_end_date, notes, is_archived, added_via, created_at
         FROM items
         WHERE user_id = $1
         ORDER BY is_archived ASC, warranty_end_date ASC NULLS LAST
         LIMIT $2 OFFSET $3`, [req.user.id, CHUNK_SIZE, offset]);
            for (const row of result.rows) {
                res.write(formatRow(row) + '\r\n');
            }
            if (result.rows.length < CHUNK_SIZE) {
                hasMore = false;
            }
            else {
                offset += CHUNK_SIZE;
            }
        }
        res.end();
    }
    catch (error) {
        // If headers already sent, destroy the response; otherwise pass to error handler
        if (res.headersSent) {
            res.destroy();
        }
        else {
            next(error);
        }
    }
});
// Get active item count (for free plan limit check)
router.get('/count', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await (0, db_1.query)(`SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`, [req.user.id]);
    (0, response_1.sendSuccess)(res, { count: parseInt(result.rows[0].count, 10) });
}));
// Get all items for user (with pagination)
router.get('/', (0, validate_1.validate)(validators_1.paginationSchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { homeId, archived, addedVia, page, limit } = req.query;
    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const pageNum = Math.max(1, parseInt(page, 10) || 1);
    const limitNum = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
    const offset = (pageNum - 1) * limitNum;
    let sql = `
    SELECT * FROM items
    WHERE user_id = $1
  `;
    const params = [req.user.id];
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
    const countParams = [req.user.id];
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
        (0, db_1.query)(sql, params),
        (0, db_1.query)(countSql, countParams),
    ]);
    const total = parseInt(countResult.rows[0].count, 10);
    // BE-10: Division by zero is safe here because limitNum >= 1 (clamped above)
    (0, response_1.sendSuccess)(res, result.rows, {
        pagination: {
            page: pageNum,
            limit: limitNum,
            total,
            total_pages: Math.ceil(total / limitNum),
        },
    });
}));
// Default expected lifespan (in years) by category, used when the item has no explicit value
const CATEGORY_DEFAULT_LIFESPAN = {
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
router.get('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await (0, db_1.query)(`SELECT * FROM items WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Item not found', 404);
    }
    const item = result.rows[0];
    // Compute lifespan percentage
    const expectedLifespan = item.expected_lifespan_years ??
        CATEGORY_DEFAULT_LIFESPAN[item.category] ??
        null;
    let lifespanPercentage = null;
    if (expectedLifespan && item.purchase_date) {
        const purchaseDate = new Date(item.purchase_date);
        const now = new Date();
        const yearsSincePurchase = (now.getTime() - purchaseDate.getTime()) / (1000 * 60 * 60 * 24 * 365.25);
        lifespanPercentage = Math.min(100, Math.round((yearsSincePurchase / expectedLifespan) * 100));
    }
    (0, response_1.sendSuccess)(res, {
        ...item,
        expected_lifespan_years: expectedLifespan,
        lifespan_percentage: lifespanPercentage,
    });
}));
// Create item
router.post('/', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.createItemSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const client = await (0, db_1.getClient)();
    try {
        const { homeId, name, brand, modelNumber, serialNumber, category, room, purchaseDate, store, price, warrantyMonths, warrantyType, warrantyProvider, notes, productImageUrl, barcode, addedVia, installationDate, lastMaintenanceDate, nextMaintenanceDue, } = req.body;
        await client.query('BEGIN');
        // Check free plan limit (5 items) with a user-level lock to prevent races
        if (req.user.plan === 'free') {
            await client.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user.id]);
            const countResult = await client.query(`SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`, [req.user.id]);
            if (parseInt(countResult.rows[0].count, 10) >= config_1.config.freeTier.itemLimit) {
                throw new errors_1.AppError('Free plan limit reached. Upgrade to Premium for unlimited items.', 403);
            }
        }
        // Verify home belongs to user
        const homeResult = await client.query(`SELECT id FROM homes WHERE id = $1 AND user_id = $2`, [homeId, req.user.id]);
        if (homeResult.rows.length === 0) {
            throw new errors_1.AppError('Home not found', 404);
        }
        // Calculate warranty end date
        const purchaseDateObj = new Date(purchaseDate);
        if (isNaN(purchaseDateObj.getTime())) {
            throw new errors_1.AppError('Invalid purchase date', 400);
        }
        const warrantyEndDate = addMonthsSafe(purchaseDateObj, warrantyMonths);
        const result = await client.query(`INSERT INTO items (
        user_id, home_id, name, brand, model_number, serial_number,
        category, room, purchase_date, store, price,
        warranty_months, warranty_end_date, warranty_type, warranty_provider, notes,
        product_image_url, barcode, added_via,
        installation_date, last_maintenance_date, next_maintenance_due
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22)
      RETURNING *`, [
            req.user.id, homeId, name, brand, modelNumber, serialNumber,
            category, room, purchaseDate, store, price,
            warrantyMonths, warrantyEndDate, warrantyType,
            warrantyProvider, notes, productImageUrl, barcode, addedVia || 'manual',
            installationDate || null, lastMaintenanceDate || null, nextMaintenanceDue || null
        ]);
        await client.query('COMMIT');
        const item = result.rows[0];
        // Fire-and-forget: stamp first_item_added_at on any active gift for this user
        db_1.pool.query(`UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE activated_user_id = $1 AND is_activated = TRUE`, [req.user.id]).catch(() => { });
        // Audit log: item created
        await audit_service_1.AuditService.logFromRequest(req, 'item.create', {
            resourceType: 'item',
            resourceId: item.id,
            description: `Created item: ${item.name}`,
            metadata: {
                category: item.category,
                warranty_months: item.warranty_months,
            },
        });
        (0, response_1.sendSuccess)(res, item, { status: 201 });
    }
    catch (error) {
        await client.query('ROLLBACK');
        throw error;
    }
    finally {
        client.release();
    }
}));
// Update item - FIXED SQL INJECTION
router.put('/:id', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, validate_1.validate)(validators_1.updateItemSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { id } = req.params;
    const updates = req.body;
    // Whitelist-based field validation to prevent SQL injection
    const fields = [];
    const values = [];
    let paramCount = 1;
    // Map camelCase to snake_case and validate
    const fieldMapping = {
        homeId: 'home_id',
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
        installationDate: 'installation_date',
        lastMaintenanceDate: 'last_maintenance_date',
        nextMaintenanceDue: 'next_maintenance_due',
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
        throw new errors_1.AppError('No valid fields to update', 400);
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
            }
            else {
                // warrantyMonths changed but purchaseDate was not provided — fetch existing
                const existing = await (0, db_1.query)(`SELECT purchase_date, warranty_months FROM items WHERE id = $1 AND user_id = $2`, [id, req.user.id]);
                if (existing.rows.length > 0 && existing.rows[0].purchase_date) {
                    const purchaseDateForCalc = new Date(existing.rows[0].purchase_date);
                    const warrantyMonthsForCalc = updates.warrantyMonths;
                    const warrantyEndDate = addMonthsSafe(purchaseDateForCalc, warrantyMonthsForCalc);
                    fields.push(`warranty_end_date = $${paramCount}`);
                    values.push(warrantyEndDate);
                    paramCount++;
                }
            }
        }
        else {
            // purchaseDate is provided and truthy — recalculate
            let purchaseDateForCalc = null;
            let warrantyMonthsForCalc = null;
            if (updates.purchaseDate) {
                purchaseDateForCalc = new Date(updates.purchaseDate);
            }
            if (updates.warrantyMonths !== undefined) {
                warrantyMonthsForCalc = updates.warrantyMonths;
            }
            // If we only have one value, fetch the other from the existing item
            if (!purchaseDateForCalc || warrantyMonthsForCalc === null) {
                const existing = await (0, db_1.query)(`SELECT purchase_date, warranty_months FROM items WHERE id = $1 AND user_id = $2`, [id, req.user.id]);
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
        }
        else {
            fields.push('archived_at = NULL');
        }
    }
    values.push(id, req.user.id);
    const result = await (0, db_1.query)(`UPDATE items SET ${fields.join(', ')}
     WHERE id = $${paramCount} AND user_id = $${paramCount + 1}
     RETURNING *`, values);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Item not found', 404);
    }
    const item = result.rows[0];
    // Audit log: item updated
    await audit_service_1.AuditService.logFromRequest(req, 'item.update', {
        resourceType: 'item',
        resourceId: item.id,
        description: `Updated item: ${item.name}`,
        metadata: {
            updated_fields: Object.keys(updates),
        },
    });
    (0, response_1.sendSuccess)(res, item);
}));
// Delete item
router.delete('/:id', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const client = await (0, db_1.getClient)();
    try {
        await client.query('BEGIN');
        // Get item details before deleting for audit log
        const itemResult = await client.query(`SELECT id, name, category FROM items WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        if (itemResult.rows.length === 0) {
            throw new errors_1.AppError('Item not found', 404);
        }
        const item = itemResult.rows[0];
        // Delete related records first (child tables)
        await client.query(`DELETE FROM documents WHERE item_id = $1 AND user_id = $2`, [item.id, req.user.id]);
        await client.query(`DELETE FROM maintenance_history WHERE item_id = $1 AND user_id = $2`, [item.id, req.user.id]);
        await client.query(`DELETE FROM warranty_claims WHERE item_id = $1 AND user_id = $2`, [item.id, req.user.id]);
        await client.query(`DELETE FROM warranty_purchases WHERE item_id = $1 AND user_id = $2`, [item.id, req.user.id]);
        await client.query(`DELETE FROM notification_history WHERE item_id = $1 AND user_id = $2`, [item.id, req.user.id]);
        // Delete the item itself
        await client.query(`DELETE FROM items WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        await client.query('COMMIT');
        // Audit log: item deleted (fire-and-forget, outside transaction)
        audit_service_1.AuditService.logFromRequest(req, 'item.delete', {
            resourceType: 'item',
            resourceId: item.id,
            description: `Deleted item: ${item.name}`,
            metadata: { category: item.category },
        }).catch((err) => {
            // Log but don't throw — audit failure should not affect the user response
            console.error('Failed to log item.delete audit event:', err);
        });
        (0, response_1.sendMessage)(res, 'Item deleted successfully');
    }
    catch (error) {
        await client.query('ROLLBACK');
        throw error;
    }
    finally {
        client.release();
    }
}));
exports.default = router;
//# sourceMappingURL=items.js.map