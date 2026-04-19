"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const errors_1 = require("../utils/errors");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const audit_service_1 = require("../services/audit.service");
const rateLimiter_1 = require("../middleware/rateLimiter");
const async_handler_1 = require("../utils/async-handler");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Get all homes for user
router.get('/', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await (0, db_1.query)(`SELECT * FROM homes WHERE user_id = $1 ORDER BY created_at DESC`, [req.user.id]);
    (0, response_1.sendSuccess)(res, result.rows);
}));
// Get single home by ID
router.get('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await (0, db_1.query)(`SELECT * FROM homes WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Home not found', 404);
    }
    (0, response_1.sendSuccess)(res, result.rows[0]);
}));
// Create new home
router.post('/', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.createHomeSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { name, address, city, state, zip, homeType, moveInDate } = req.body;
    const result = await (0, db_1.query)(`INSERT INTO homes (user_id, name, address, city, state, zip, home_type, move_in_date)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`, [req.user.id, name, address, city, state, zip, homeType, moveInDate]);
    const home = result.rows[0];
    await audit_service_1.AuditService.logFromRequest(req, 'home.create', {
        resourceType: 'home',
        resourceId: home.id,
        description: `Created home: ${home.name}`,
    });
    (0, response_1.sendSuccess)(res, home, { status: 201 });
}));
// Update home
router.put('/:id', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, validate_1.validate)(validators_1.updateHomeSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { name, address, city, state, zip, homeType, moveInDate } = req.body;
    const updates = [];
    const values = [];
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
        throw new errors_1.AppError('No fields to update', 400);
    }
    values.push(req.params.id, req.user.id);
    const result = await (0, db_1.query)(`UPDATE homes SET
      ${updates.join(', ')},
      updated_at = NOW()
     WHERE id = $${paramIndex++} AND user_id = $${paramIndex++}
     RETURNING *`, values);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Home not found', 404);
    }
    const home = result.rows[0];
    await audit_service_1.AuditService.logFromRequest(req, 'home.update', {
        resourceType: 'home',
        resourceId: home.id,
        description: `Updated home: ${home.name}`,
        metadata: {
            updated_fields: Object.keys(req.body || {}),
        },
    });
    (0, response_1.sendSuccess)(res, home);
}));
// Delete home
router.delete('/:id', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const client = await (0, db_1.getClient)();
    try {
        await client.query('BEGIN');
        // Lock all of the user's homes to prevent TOCTOU race conditions
        const lockedHomes = await client.query(`SELECT id, name FROM homes WHERE user_id = $1 FOR UPDATE`, [req.user.id]);
        // Prevent deleting the last home
        if (lockedHomes.rows.length <= 1) {
            throw new errors_1.AppError('Cannot delete your only home. You must have at least one home.', 400);
        }
        // Verify the specific home exists and belongs to the user
        const home = lockedHomes.rows.find((h) => h.id === req.params.id);
        if (!home) {
            throw new errors_1.AppError('Home not found', 404);
        }
        // Reassign any items in this home to the user's first remaining home (#18)
        const firstRemainingHome = lockedHomes.rows.find((h) => h.id !== req.params.id);
        if (firstRemainingHome) {
            await client.query(`UPDATE items SET home_id = $1 WHERE home_id = $2 AND user_id = $3`, [firstRemainingHome.id, req.params.id, req.user.id]);
        }
        // Delete the home
        await client.query(`DELETE FROM homes WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        await client.query('COMMIT');
        await audit_service_1.AuditService.logFromRequest(req, 'home.delete', {
            resourceType: 'home',
            resourceId: home.id,
            description: `Deleted home: ${home.name}`,
            metadata: {
                items_reassigned_to: firstRemainingHome?.id ?? null,
            },
        });
        (0, response_1.sendMessage)(res, 'Home deleted successfully');
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
//# sourceMappingURL=homes.js.map