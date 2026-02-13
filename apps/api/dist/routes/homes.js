"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const errorHandler_1 = require("../middleware/errorHandler");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const audit_service_1 = require("../services/audit.service");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Get all homes for user
router.get('/', async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`SELECT * FROM homes WHERE user_id = $1 ORDER BY created_at DESC`, [req.user.id]);
        res.json({ homes: result.rows });
    }
    catch (error) {
        next(error);
    }
});
// Get single home by ID
router.get('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`SELECT * FROM homes WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('Home not found', 404);
        }
        res.json({ home: result.rows[0] });
    }
    catch (error) {
        next(error);
    }
});
// Create new home
router.post('/', (0, validate_1.validate)(validators_1.createHomeSchema), async (req, res, next) => {
    try {
        const { name, address, city, state, zip, homeType, moveInDate } = req.body;
        const result = await (0, db_1.query)(`INSERT INTO homes (user_id, name, address, city, state, zip, home_type, move_in_date)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`, [req.user.id, name, address, city, state, zip, homeType, moveInDate]);
        const home = result.rows[0];
        await audit_service_1.AuditService.logFromRequest(req, 'home.create', {
            resourceType: 'home',
            resourceId: home.id,
            description: `Created home: ${home.name}`,
        });
        res.status(201).json({ home });
    }
    catch (error) {
        next(error);
    }
});
// Update home
router.put('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, validate_1.validate)(validators_1.updateHomeSchema), async (req, res, next) => {
    try {
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
            throw new errorHandler_1.AppError('No fields to update', 400);
        }
        values.push(req.params.id, req.user.id);
        const result = await (0, db_1.query)(`UPDATE homes SET
        ${updates.join(', ')},
        updated_at = NOW()
       WHERE id = $${paramIndex++} AND user_id = $${paramIndex++}
       RETURNING *`, values);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('Home not found', 404);
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
        res.json({ home });
    }
    catch (error) {
        next(error);
    }
});
// Delete home
router.delete('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), async (req, res, next) => {
    try {
        // Prevent deleting the last home
        const countResult = await (0, db_1.query)(`SELECT COUNT(*) FROM homes WHERE user_id = $1`, [req.user.id]);
        if (parseInt(countResult.rows[0].count) <= 1) {
            throw new errorHandler_1.AppError('Cannot delete your only home. You must have at least one home.', 400);
        }
        const homeResult = await (0, db_1.query)(`SELECT id, name FROM homes WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        if (homeResult.rows.length === 0) {
            throw new errorHandler_1.AppError('Home not found', 404);
        }
        const home = homeResult.rows[0];
        await (0, db_1.query)(`DELETE FROM homes WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        await audit_service_1.AuditService.logFromRequest(req, 'home.delete', {
            resourceType: 'home',
            resourceId: home.id,
            description: `Deleted home: ${home.name}`,
        });
        res.json({ message: 'Home deleted successfully' });
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=homes.js.map