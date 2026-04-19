"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const barcode_1 = require("../validators/barcode");
const logger_1 = require("../utils/logger");
const redis_1 = require("../utils/redis");
const async_handler_1 = require("../utils/async-handler");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
router.use(auth_1.requirePremium);
const BARCODE_CACHE_TTL = 86400; // 24 hours in seconds
router.post('/lookup', (0, validate_1.validate)(barcode_1.barcodeLookupSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { barcode } = req.body;
    logger_1.logger.info({ barcode, userId: req.user.id }, 'Barcode lookup requested');
    // Serve from Redis cache if available (avoids hitting rate-limited trial API)
    const cacheKey = `barcode:${barcode}`;
    try {
        const redis = await (0, redis_1.getRedisClient)();
        const cached = await redis.get(cacheKey);
        if (cached) {
            logger_1.logger.info({ barcode }, 'Barcode served from Redis cache');
            return (0, response_1.sendSuccess)(res, JSON.parse(cached));
        }
    }
    catch (err) {
        logger_1.logger.warn({ err, barcode }, 'Redis cache read failed for barcode, proceeding with API call');
    }
    // Try UPC Database API (general product database, not food-only)
    // NOTE: Using the UPC Item DB trial API which has strict rate limits (100 req/day).
    // For production traffic, upgrade to a paid plan.
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    let response;
    try {
        response = await fetch(`https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`, { signal: controller.signal });
    }
    catch (err) {
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
        logger_1.logger.error({ barcode, statusCode }, 'Barcode API returned error');
        if (statusCode === 404) {
            // API explicitly says not found — return 200 with null product data
            const notFoundResult = { barcode, brand: null, product_name: null, description: null, image_url: null };
            try {
                const redis = await (0, redis_1.getRedisClient)();
                await redis.set(cacheKey, JSON.stringify(notFoundResult), { EX: BARCODE_CACHE_TTL });
            }
            catch (err) {
                logger_1.logger.warn({ err, barcode }, 'Redis cache write failed for barcode');
            }
            return (0, response_1.sendSuccess)(res, notFoundResult);
        }
        // Upstream server error or rate limit — return 502 Bad Gateway
        return res.status(502).json({
            error: 'Barcode lookup service unavailable',
            message: `External API returned status ${statusCode}`,
        });
    }
    const data = await response.json();
    if (data.items && data.items.length > 0) {
        const product = data.items[0];
        logger_1.logger.info({ barcode, found: true }, 'Barcode found');
        const result = {
            barcode,
            brand: typeof product.brand === 'string' ? product.brand : null,
            product_name: typeof product.title === 'string' ? product.title : null,
            category: typeof product.category === 'string' ? product.category : 'other',
            image_url: Array.isArray(product.images) && product.images.length > 0 ? product.images[0] : null,
            description: typeof product.description === 'string' && product.description.length > 0 ? product.description : null,
        };
        try {
            const redis = await (0, redis_1.getRedisClient)();
            await redis.set(cacheKey, JSON.stringify(result), { EX: BARCODE_CACHE_TTL });
        }
        catch (err) {
            logger_1.logger.warn({ err, barcode }, 'Redis cache write failed for barcode');
        }
        return (0, response_1.sendSuccess)(res, result);
    }
    // API returned 200 but no items — product genuinely not found
    logger_1.logger.info({ barcode, found: false }, 'Barcode not found');
    const emptyResult = { barcode, brand: null, product_name: null, description: null, image_url: null };
    try {
        const redis = await (0, redis_1.getRedisClient)();
        await redis.set(cacheKey, JSON.stringify(emptyResult), { EX: BARCODE_CACHE_TTL });
    }
    catch (err) {
        logger_1.logger.warn({ err, barcode }, 'Redis cache write failed for barcode');
    }
    (0, response_1.sendSuccess)(res, emptyResult);
}));
exports.default = router;
//# sourceMappingURL=barcode.js.map