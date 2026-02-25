import { Router } from 'express';
import { authenticate, AuthRequest, requirePremium } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { barcodeLookupSchema } from '../validators/barcode';
import { logger } from '../utils/logger';

const router = Router();
router.use(authenticate);
router.use(requirePremium);

// In-memory barcode result cache — 24-hour TTL per barcode.
// Reduces hits against the trial UPC API (100 req/day limit).
// Cache survives process lifetime only; acceptable for single-instance deployments.
const barcodeCache = new Map<string, { result: object; cachedAt: number }>();
const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

function getCached(barcode: string): object | null {
  const entry = barcodeCache.get(barcode);
  if (!entry) return null;
  if (Date.now() - entry.cachedAt > CACHE_TTL_MS) {
    barcodeCache.delete(barcode);
    return null;
  }
  return entry.result;
}

function setCache(barcode: string, result: object): void {
  barcodeCache.set(barcode, { result, cachedAt: Date.now() });
}

router.post('/lookup', validate(barcodeLookupSchema), async (req: AuthRequest, res, next) => {
  try {
    const { barcode } = req.body;

    logger.info({ barcode, userId: req.user!.id }, 'Barcode lookup requested');

    // Serve from cache if available (avoids hitting rate-limited trial API)
    const cached = getCached(barcode);
    if (cached) {
      logger.info({ barcode }, 'Barcode served from cache');
      return res.json(cached);
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
        const notFoundResult = { barcode, brand: null, productName: null, description: null, imageUrl: null };
        setCache(barcode, notFoundResult);
        return res.json(notFoundResult);
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
        productName: typeof product.title === 'string' ? product.title : null,
        category: typeof product.category === 'string' ? product.category : 'other',
        imageUrl: Array.isArray(product.images) && product.images.length > 0 ? product.images[0] : null,
        description: typeof product.description === 'string' && product.description.length > 0 ? product.description : null,
      };
      setCache(barcode, result);
      return res.json(result);
    }

    // API returned 200 but no items — product genuinely not found
    logger.info({ barcode, found: false }, 'Barcode not found');
    const emptyResult = { barcode, brand: null, productName: null, description: null, imageUrl: null };
    setCache(barcode, emptyResult);
    res.json(emptyResult);
  } catch (error) {
    logger.error({ error, barcode: req.body?.barcode }, 'Barcode lookup failed');
    next(error);
  }
});

export default router;
