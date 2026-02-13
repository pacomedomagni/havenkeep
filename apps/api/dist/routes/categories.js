"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const async_handler_1 = require("../utils/async-handler");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   GET /api/v1/categories/defaults
 * @desc    Get all category defaults (warranty months, default room, etc.)
 * @access  Private
 */
router.get('/defaults', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await (0, db_1.query)(`SELECT * FROM category_defaults ORDER BY category ASC`);
    res.json({
        success: true,
        data: result.rows,
    });
}));
/**
 * @route   GET /api/v1/categories/:category/brands
 * @desc    Get brand suggestions for a specific category
 * @access  Private
 */
router.get('/:category/brands', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { category } = req.params;
    const result = await (0, db_1.query)(`SELECT * FROM brand_suggestions WHERE category = $1 ORDER BY sort_order ASC`, [category]);
    res.json({
        success: true,
        data: result.rows,
    });
}));
exports.default = router;
//# sourceMappingURL=categories.js.map