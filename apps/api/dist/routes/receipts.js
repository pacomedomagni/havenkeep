"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const errorHandler_1 = require("../middleware/errorHandler");
const async_handler_1 = require("../utils/async-handler");
const logger_1 = require("../utils/logger");
const config_1 = require("../config");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
/**
 * @route   POST /api/v1/receipts/scan
 * @desc    Scan a receipt image and extract structured data
 * @access  Private
 */
router.post('/scan', auth_1.requirePremium, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { image } = req.body;
    if (!image || typeof image !== 'string') {
        throw new errorHandler_1.AppError('Base64 image is required', 400);
    }
    if (!config_1.config.openai?.apiKey) {
        throw new errorHandler_1.AppError('Receipt scanning requires OpenAI API key configuration. Set OPENAI_API_KEY in environment.', 501);
    }
    // Call OpenAI Vision API to extract receipt data
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${config_1.config.openai.apiKey}`,
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
        logger_1.logger.error({ status: response.status }, 'OpenAI receipt scan failed');
        throw new errorHandler_1.AppError('Receipt scanning service unavailable', 502);
    }
    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
        throw new errorHandler_1.AppError('Empty response from receipt scanner', 502);
    }
    let extracted;
    try {
        extracted = JSON.parse(content);
    }
    catch {
        logger_1.logger.warn({ content }, 'Failed to parse receipt scan response');
        throw new errorHandler_1.AppError('Could not parse receipt data', 502);
    }
    res.json({
        success: true,
        data: extracted,
    });
}));
exports.default = router;
//# sourceMappingURL=receipts.js.map