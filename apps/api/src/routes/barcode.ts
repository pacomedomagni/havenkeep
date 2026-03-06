import { Router } from 'express';
import { authenticate, AuthRequest, requirePremium } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { barcodeLookupSchema } from '../validators/barcode';
import { logger } from '../utils/logger';
import { getRedisClient } from '../utils/redis';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess } from '../utils/response';

const router = Router();
router.use(authenticate);
router.use(requirePremium);

const BARCODE_CACHE_TTL = 86400; // 24 hours in seconds

router.post('/lookup', validate(barcodeLookupSchema), asyncHandler(async (req: AuthRequest, res) => {
  const { barcode } = req.body;

  logger.info({ barcode, userId: req.user!.id }, 'Barcode lookup requested');

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
  // NOTE: Using the UPC Item DB trial API which has strict rate limits (100 req/day).
  // For production traffic, upgrade to a paid plan.
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

  // BE-25: Distinguish between API error (upstream failure) and not-found
  if (!response.ok) {
    const statusCode = response.status;
    logger.error({ barcode, statusCode }, 'Barcode API returned error');

    if (statusCode === 404) {
      // API explicitly says not found — return 200 with null product data
      const notFoundResult = { barcode, brand: null, product_name: null, description: null, image_url: null };
      try {
        const redis = await getRedisClient();
        await redis.set(cacheKey, JSON.stringify(notFoundResult), { EX: BARCODE_CACHE_TTL });
      } catch (err) {
        logger.warn({ err, barcode }, 'Redis cache write failed for barcode');
      }
      return sendSuccess(res, notFoundResult);
    }

    // Upstream server error or rate limit — return 502 Bad Gateway
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
      await redis.set(cacheKey, JSON.stringify(result), { EX: BARCODE_CACHE_TTL });
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
    await redis.set(cacheKey, JSON.stringify(emptyResult), { EX: BARCODE_CACHE_TTL });
  } catch (err) {
    logger.warn({ err, barcode }, 'Redis cache write failed for barcode');
  }
  sendSuccess(res, emptyResult);
}));

export default router;
