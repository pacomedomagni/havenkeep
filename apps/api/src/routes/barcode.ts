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

    // Try UPC Database API (general product database, not food-only)
    const response = await fetch(
      `https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`
    );

    if (response.ok) {
      const data: any = await response.json();
      if (data.items && data.items.length > 0) {
        const product = data.items[0];
        logger.info({ barcode, found: true }, 'Barcode found');
        return res.json({
          barcode,
          brand: typeof product.brand === 'string' ? product.brand : null,
          productName: typeof product.title === 'string' ? product.title : null,
          category: typeof product.category === 'string' ? product.category : 'other',
          imageUrl: Array.isArray(product.images) && product.images.length > 0 ? product.images[0] : null,
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
