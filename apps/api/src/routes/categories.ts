import { Router } from 'express';
import { query } from '../db';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../utils/async-handler';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * @route   GET /api/v1/categories/defaults
 * @desc    Get all category defaults (warranty months, default room, etc.)
 * @access  Private
 */
router.get(
  '/defaults',
  asyncHandler(async (req, res) => {
    const result = await query(
      `SELECT * FROM category_defaults ORDER BY category ASC`
    );

    res.json({
      success: true,
      data: result.rows,
    });
  })
);

/**
 * @route   GET /api/v1/categories/:category/brands
 * @desc    Get brand suggestions for a specific category
 * @access  Private
 */
router.get(
  '/:category/brands',
  asyncHandler(async (req, res) => {
    const { category } = req.params;

    const result = await query(
      `SELECT * FROM brand_suggestions WHERE category = $1 ORDER BY sort_order ASC`,
      [category]
    );

    res.json({
      success: true,
      data: result.rows,
    });
  })
);

export default router;
