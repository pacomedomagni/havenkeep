import { Router } from 'express';
import { authenticate, AuthRequest, requirePremium } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { barcodeLookupSchema } from '../validators/barcode';
import { AppError } from '../middleware/errorHandler';
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
      if (data.status === 1 && data.product) {
        logger.info({ barcode, found: true }, 'Barcode found');
        return res.json({
          barcode,
          brand: data.product.brands || null,
          productName: data.product.product_name || null,
          category: 'other',
          imageUrl: data.product.image_url || null,
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
