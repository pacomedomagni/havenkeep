import { Router } from 'express';
import { authenticate, AuthRequest, requirePremium } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { barcodeLookupSchema } from '../validators/barcode';
import { logger } from '../utils/logger';

const router = Router();
router.use(authenticate);
router.use(requirePremium);

router.post('/lookup', validate(barcodeLookupSchema), async (req: AuthRequest, res, next) => {
  try {
    const { barcode } = req.body;

    logger.info({ barcode, userId: req.user!.id }, 'Barcode lookup requested');

    // Try Open Food Facts
    const response = await fetch(
      `https://world.openfoodfacts.org/api/v2/product/${barcode}.json`
    );

    if (response.ok) {
      const data = await response.json();
      if (data.status === 1 && data.product && typeof data.product === 'object') {
        logger.info({ barcode, found: true }, 'Barcode found');
        return res.json({
          barcode,
          brand: typeof data.product.brands === 'string' ? data.product.brands : null,
          productName: typeof data.product.product_name === 'string' ? data.product.product_name : null,
          category: 'other',
          imageUrl: typeof data.product.image_url === 'string' ? data.product.image_url : null,
        });
      }
    }

    logger.info({ barcode, found: false }, 'Barcode not found');
    res.json({ barcode, brand: null, productName: null });
  } catch (error) {
    logger.error({ error, barcode: req.body?.barcode }, 'Barcode lookup failed');
    next(error);
  }
});

export default router;
