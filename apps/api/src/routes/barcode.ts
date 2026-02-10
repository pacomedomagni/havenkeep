import { Router } from 'express';
import { authenticate, AuthRequest, requirePremium } from '../middleware/auth';

const router = Router();
router.use(authenticate);
router.use(requirePremium);

router.post('/lookup', async (req: AuthRequest, res, next) => {
  try {
    const { barcode } = req.body;
    
    // Try Open Food Facts
    const response = await fetch(
      `https://world.openfoodfacts.org/api/v2/product/${barcode}.json`
    );
    
    if (response.ok) {
      const data = await response.json();
      if (data.status === 1 && data.product) {
        return res.json({
          barcode,
          brand: data.product.brands || null,
          productName: data.product.product_name || null,
          category: 'other',
          imageUrl: data.product.image_url || null,
        });
      }
    }
    
    res.json({ barcode, brand: null, productName: null });
  } catch (error) {
    next(error);
  }
});

export default router;
