import { Router } from 'express';
import { authenticate, requirePremium } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { asyncHandler } from '../utils/async-handler';
import { logger } from '../utils/logger';
import { config } from '../config';

const router = Router();
router.use(authenticate);

/**
 * @route   POST /api/v1/receipts/scan
 * @desc    Scan a receipt image and extract structured data
 * @access  Private
 */
router.post(
  '/scan',
  requirePremium,
  asyncHandler(async (req, res) => {
    const { image } = req.body;

    if (!image || typeof image !== 'string') {
      throw new AppError('Base64 image is required', 400);
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
      extracted = JSON.parse(content);
    } catch {
      logger.warn({ content }, 'Failed to parse receipt scan response');
      throw new AppError('Could not parse receipt data', 502);
    }

    res.json({
      success: true,
      data: extracted,
    });
  })
);

export default router;
