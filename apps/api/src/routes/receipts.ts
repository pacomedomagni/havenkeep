import { Router } from 'express';
import { authenticate, requirePremium } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { asyncHandler } from '../utils/async-handler';
import { logger } from '../utils/logger';
import { config } from '../config';
import { receiptScanRateLimiter } from '../middleware/rateLimiter';
import { sendSuccess } from '../utils/response';

const router = Router();
router.use(authenticate);

/**
 * @route   POST /api/v1/receipts/scan
 * @desc    Scan a receipt image and extract structured data
 * @access  Private
 */
router.post(
  '/scan',
  receiptScanRateLimiter,
  requirePremium,
  asyncHandler(async (req, res) => {
    const { image } = req.body;

    if (!image || typeof image !== 'string') {
      throw new AppError('Base64 image is required', 400);
    }

    // Validate base64 format (reject non-base64 input)
    if (!/^[A-Za-z0-9+/]+=*$/.test(image.slice(0, 100))) {
      throw new AppError('Invalid base64 image data', 400);
    }

    // Reject oversized images before sending to OpenAI (5MB limit)
    const sizeBytes = Buffer.byteLength(image, 'base64');
    if (sizeBytes > 5 * 1024 * 1024) {
      throw new AppError('Image too large. Maximum size is 5MB.', 413);
    }

    if (!config.openai?.apiKey) {
      throw new AppError(
        'Receipt scanning requires OpenAI API key configuration. Set OPENAI_API_KEY in environment.',
        501,
      );
    }

    // Call OpenAI Vision API to extract receipt data
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openai.apiKey}`,
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are a receipt scanner. Extract the following from the receipt image and return ONLY valid JSON:
{
  "merchant": "store name",
  "date": "YYYY-MM-DD",
  "total": 0.00,
  "items": [{"name": "item name", "price": 0.00, "quantity": 1}],
  "categoryGuess": "appliance category guess (refrigerator, washer, dryer, tv, etc.) or null"
}
If you cannot extract a field, use null.`,
          },
          {
            role: 'user',
            content: [
              {
                type: 'image_url',
                image_url: {
                  url: `data:image/jpeg;base64,${image}`,
                },
              },
            ],
          },
        ],
        max_tokens: 1000,
      }),
    });

    if (!response.ok) {
      logger.error({ status: response.status }, 'OpenAI receipt scan failed');
      throw new AppError('Receipt scanning service unavailable', 502);
    }

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content;

    if (!content) {
      throw new AppError('Empty response from receipt scanner', 502);
    }

    let extracted;
    try {
      // Strip markdown code fences if present (e.g. ```json ... ```)
      const cleaned = content.replace(/^```(?:json)?\s*\n?/i, '').replace(/\n?```\s*$/i, '').trim();
      extracted = JSON.parse(cleaned);
    } catch {
      logger.warn({ content }, 'Failed to parse receipt scan response');
      throw new AppError('Could not parse receipt data', 502);
    }

    // Sanitize: only allow expected fields through
    const sanitized = {
      merchant: typeof extracted.merchant === 'string' ? extracted.merchant.slice(0, 255) : null,
      date: typeof extracted.date === 'string' ? extracted.date.slice(0, 10) : null,
      total: typeof extracted.total === 'number' ? extracted.total : null,
      items: Array.isArray(extracted.items)
        ? extracted.items.slice(0, 50).map((item: any) => ({
            name: typeof item.name === 'string' ? item.name.slice(0, 255) : '',
            price: typeof item.price === 'number' ? item.price : 0,
            quantity: typeof item.quantity === 'number' ? item.quantity : 1,
          }))
        : [],
      categoryGuess: typeof extracted.categoryGuess === 'string' ? extracted.categoryGuess.slice(0, 50) : null,
    };

    sendSuccess(res, sanitized);
  })
);

export default router;
