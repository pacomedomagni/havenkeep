"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const barcode_1 = require("../validators/barcode");
const logger_1 = require("../utils/logger");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
router.use(auth_1.requirePremium);
router.post('/lookup', (0, validate_1.validate)(barcode_1.barcodeLookupSchema), async (req, res, next) => {
    try {
        const { barcode } = req.body;
        logger_1.logger.info({ barcode, userId: req.user.id }, 'Barcode lookup requested');
        // Try Open Food Facts
        const response = await fetch(`https://world.openfoodfacts.org/api/v2/product/${barcode}.json`);
        if (response.ok) {
            const data = await response.json();
            if (data.status === 1 && data.product && typeof data.product === 'object') {
                logger_1.logger.info({ barcode, found: true }, 'Barcode found');
                return res.json({
                    barcode,
                    brand: typeof data.product.brands === 'string' ? data.product.brands : null,
                    productName: typeof data.product.product_name === 'string' ? data.product.product_name : null,
                    category: 'other',
                    imageUrl: typeof data.product.image_url === 'string' ? data.product.image_url : null,
                });
            }
        }
        logger_1.logger.info({ barcode, found: false }, 'Barcode not found');
        res.json({ barcode, brand: null, productName: null });
    }
    catch (error) {
        logger_1.logger.error({ error, barcode: req.body?.barcode }, 'Barcode lookup failed');
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=barcode.js.map