import { Router } from 'express';
import { authenticate, AuthRequest, requirePremium } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { barcodeLookupSchema } from '../validators/barcode';
import { logger } from '../utils/logger';
import { getRedisClient } from '../utils/redis';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess } from '../utils/response';
import { pool } from '../db';
import { AppError } from '../utils/errors';

const router = Router();
router.use(authenticate);
router.use(requirePremium);

// F105: a successful lookup is cached for 24h (results don't change often).
// A 404 is now only cached for 1h so a newly-listed product surfaces within
// the day instead of staying invisible until the cache TTL expires.
const BARCODE_CACHE_TTL_HIT = 86400;       // 24h
const BARCODE_CACHE_TTL_MISS = 60 * 60;    // 1h

// F103: per-user daily quota. The shared upcitemdb trial cap is 100/day, so
// without a per-user limit a single chatty account can starve the rest.
// Free plan users (technically blocked by requirePremium today, but kept
// here for consistency) get 10/day; premium users get 50/day.
const QUOTA_PREMIUM = 50;
const QUOTA_FREE = 10;

async function consumeBarcodeQuota(userId: string, plan: 'free' | 'premium' | string): Promise<void> {
  const limit = plan === 'premium' ? QUOTA_PREMIUM : QUOTA_FREE;
  // Atomic upsert + check. The ON CONFLICT branch returns the post-increment
  // value, so we can throw 429 immediately if the user is over.
  const result = await pool.query<{ lookups: number }>(
    `INSERT INTO barcode_lookup_quota (user_id, quota_date, lookups)
     VALUES ($1, (NOW() AT TIME ZONE 'UTC')::date, 1)
     ON CONFLICT (user_id, quota_date)
     DO UPDATE SET lookups = barcode_lookup_quota.lookups + 1
     RETURNING lookups`,
    [userId],
  );
  if (result.rows[0].lookups > limit) {
    throw new AppError(`Daily barcode lookup quota of ${limit} exceeded`, 429);
  }
}

router.post('/lookup', validate(barcodeLookupSchema), asyncHandler(async (req: AuthRequest, res) => {
  const { barcode } = req.body;
  const user = req.user!;

  // F103: bump per-user quota first; over-quota requests don't consume any
  // upstream budget. The plan string lives on req.user (premium gating
  // already filtered free out, but treat conservatively).
  await consumeBarcodeQuota(user.id, (user as any).plan ?? 'premium');

  logger.info({ barcode, userId: user.id }, 'Barcode lookup requested');

  // Serve from Redis cache if available (avoids hitting rate-limited trial API)
  const cacheKey = `barcode:${barcode}`;
  try {
    const redis = await getRedisClient();
    const cached = await redis.get(cacheKey);
    if (cached) {
      logger.info({ barcode }, 'Barcode served from Redis cache');
      return sendSuccess(res, JSON.parse(cached));
    }
  } catch (err) {
    logger.warn({ err, barcode }, 'Redis cache read failed for barcode, proceeding with API call');
  }

  // Try UPC Database API (general product database, not food-only)
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  let response: Response;
  try {
    response = await fetch(
      `https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`,
      { signal: controller.signal }
    );
  } catch (err: any) {
    clearTimeout(timeout);
    if (err.name === 'AbortError') {
      return res.status(504).json({ error: 'Barcode lookup timed out' });
    }
    throw err;
  }
  clearTimeout(timeout);

  if (!response.ok) {
    const statusCode = response.status;
    logger.error({ barcode, statusCode }, 'Barcode API returned error');

    if (statusCode === 404) {
      const notFoundResult = { barcode, brand: null, product_name: null, description: null, image_url: null };
      try {
        const redis = await getRedisClient();
        // F105: short TTL on 404 so a newly-listed product surfaces sooner.
        await redis.set(cacheKey, JSON.stringify(notFoundResult), { EX: BARCODE_CACHE_TTL_MISS });
      } catch (err) {
        logger.warn({ err, barcode }, 'Redis cache write failed for barcode (404)');
      }
      return sendSuccess(res, notFoundResult);
    }

    return res.status(502).json({
      error: 'Barcode lookup service unavailable',
      message: `External API returned status ${statusCode}`,
    });
  }

  const data: any = await response.json();
  if (data.items && data.items.length > 0) {
    const product = data.items[0];
    logger.info({ barcode, found: true }, 'Barcode found');
    const result = {
      barcode,
      brand: typeof product.brand === 'string' ? product.brand : null,
      product_name: typeof product.title === 'string' ? product.title : null,
      category: typeof product.category === 'string' ? product.category : 'other',
      image_url: Array.isArray(product.images) && product.images.length > 0 ? product.images[0] : null,
      description: typeof product.description === 'string' && product.description.length > 0 ? product.description : null,
    };
    try {
      const redis = await getRedisClient();
      await redis.set(cacheKey, JSON.stringify(result), { EX: BARCODE_CACHE_TTL_HIT });
    } catch (err) {
      logger.warn({ err, barcode }, 'Redis cache write failed for barcode');
    }
    return sendSuccess(res, result);
  }

  // API returned 200 but no items — product genuinely not found
  logger.info({ barcode, found: false }, 'Barcode not found');
  const emptyResult = { barcode, brand: null, product_name: null, description: null, image_url: null };
  try {
    const redis = await getRedisClient();
    // F105: same short TTL as 404; "200 with no items" is functionally a miss.
    await redis.set(cacheKey, JSON.stringify(emptyResult), { EX: BARCODE_CACHE_TTL_MISS });
  } catch (err) {
    logger.warn({ err, barcode }, 'Redis cache write failed for barcode (empty)');
  }
  sendSuccess(res, emptyResult);
}));

export default router;
