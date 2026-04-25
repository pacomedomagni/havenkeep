import { Router } from 'express';
import { query } from '../db';
import { authenticate, requireAdmin } from '../middleware/auth';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess } from '../utils/response';
import { validate } from '../middleware/validate';
import { writeRateLimiter } from '../middleware/rateLimiter';
import Joi from 'joi';
import { AppError } from '../utils/errors';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * F096: hard-coded category allowlist used by both the route validators
 * and any future caller that needs to validate a `:category` param. Mirrors
 * the `ItemCategory` union in types/database.types.ts and the DB enum
 * `item_category`. Keep all three in sync.
 */
const VALID_CATEGORIES: ReadonlySet<string> = new Set<string>([
  'refrigerator', 'dishwasher', 'washer', 'dryer',
  'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
  'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
  'tv', 'computer', 'smart_home',
  'roofing', 'windows', 'doors', 'flooring',
  'plumbing', 'electrical',
  'furniture',
  'air_purifier', 'vacuum', 'ceiling_fan', 'smoke_detector',
  'security_system', 'garage_door_opener', 'power_tools', 'lawn_mower',
  'pool_equipment', 'grill', 'coffee_maker', 'home_theater',
  'printer', 'networking', 'camera', 'lighting',
  'dehumidifier', 'freezer', 'wine_cooler', 'trash_compactor',
  'other',
]);

/**
 * F097: simple in-memory cache for /categories/defaults. Categories rarely
 * change (admin POST/PUT below invalidates) and the table is read on every
 * "add item" flow, so 5 minutes pays for itself instantly.
 *
 * In a multi-instance deploy each instance carries its own cache; the
 * 5-minute TTL bounds the inconsistency window. If we ever need cross-pod
 * coherence move this to Redis.
 */
const CATEGORY_CACHE_TTL_MS = 5 * 60 * 1000;
let categoryDefaultsCache: { rows: any[]; expiresAt: number } | null = null;
function invalidateCategoryDefaultsCache(): void {
  categoryDefaultsCache = null;
}

/**
 * @route   GET /api/v1/categories/defaults
 * @desc    Get all category defaults (warranty months, default room, etc.)
 * @access  Private
 */
router.get(
  '/defaults',
  asyncHandler(async (req, res) => {
    if (categoryDefaultsCache && categoryDefaultsCache.expiresAt > Date.now()) {
      return sendSuccess(res, categoryDefaultsCache.rows);
    }
    const result = await query(
      `SELECT * FROM category_defaults ORDER BY category ASC`
    );
    categoryDefaultsCache = {
      rows: result.rows,
      expiresAt: Date.now() + CATEGORY_CACHE_TTL_MS,
    };
    return sendSuccess(res, result.rows);
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
    // F096: validate the route param against the enum allowlist so an
    // unknown value surfaces as a 400 (not a generic 500 if PG rejects
    // the cast against item_category).
    if (!VALID_CATEGORIES.has(category)) {
      throw new AppError('Unknown category', 400);
    }

    const result = await query(
      `SELECT * FROM brand_suggestions WHERE category = $1 ORDER BY sort_order ASC`,
      [category]
    );

    sendSuccess(res, result.rows);
  })
);

/**
 * F098: admin write endpoint for category_defaults. Replaces the row for
 * the supplied category outright (PUT semantics). Invalidates the in-memory
 * cache so the next read sees the change.
 */
const upsertCategoryDefaultsSchema = Joi.object({
  category: Joi.string().required(),
  warranty_months: Joi.number().integer().min(0).max(360).optional(),
  default_room: Joi.string().max(64).optional().allow(null),
  icon: Joi.string().max(16).optional(),
});

router.put(
  '/defaults',
  requireAdmin,
  writeRateLimiter,
  validate(upsertCategoryDefaultsSchema),
  asyncHandler(async (req, res) => {
    const { category, warranty_months, default_room, icon } = req.body;
    if (!VALID_CATEGORIES.has(category)) {
      throw new AppError('Unknown category', 400);
    }

    const result = await query(
      `INSERT INTO category_defaults (category, warranty_months, default_room, icon, updated_by, updated_at)
       VALUES ($1, COALESCE($2, 12), $3, COALESCE($4, '📦'), $5, NOW())
       ON CONFLICT (category)
       DO UPDATE SET warranty_months = COALESCE(EXCLUDED.warranty_months, category_defaults.warranty_months),
                     default_room    = COALESCE(EXCLUDED.default_room, category_defaults.default_room),
                     icon            = COALESCE(EXCLUDED.icon, category_defaults.icon),
                     updated_by      = EXCLUDED.updated_by,
                     updated_at      = NOW()
       RETURNING *`,
      [category, warranty_months ?? null, default_room ?? null, icon ?? null, req.user!.id],
    );

    invalidateCategoryDefaultsCache();
    sendSuccess(res, result.rows[0], { message: 'Category default upserted' });
  }),
);

export default router;
