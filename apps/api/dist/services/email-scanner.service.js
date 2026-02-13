"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmailScannerService = void 0;
const googleapis_1 = require("googleapis");
const axios_1 = __importDefault(require("axios"));
const db_1 = require("../db");
const logger_1 = require("../utils/logger");
const errors_1 = require("../utils/errors");
const config_1 = require("../config");
class EmailScannerService {
    /**
     * Initiate email scan
     */
    static async initiateScan(userId, provider, accessToken, options = {}) {
        const client = await db_1.pool.connect();
        try {
            await client.query('BEGIN');
            // Create scan record
            const scanResult = await client.query(`INSERT INTO email_scans (user_id, provider, status, date_range_start, date_range_end)
         VALUES ($1, $2, 'pending', $3, $4)
         RETURNING *`, [
                userId,
                provider,
                options.dateRangeStart || null,
                options.dateRangeEnd || null,
            ]);
            const scan = scanResult.rows[0];
            await client.query('COMMIT');
            // Start scan asynchronously with failure recovery
            this.performScan(scan.id, userId, provider, accessToken, options).catch(async (error) => {
                logger_1.logger.error({ error, scanId: scan.id }, 'Background email scan failed');
                try {
                    await db_1.pool.query(`UPDATE email_scans SET status = 'failed', error_message = $2, completed_at = NOW() WHERE id = $1 AND status != 'completed'`, [scan.id, error.message || 'Unknown error']);
                }
                catch (updateError) {
                    logger_1.logger.error({ updateError, scanId: scan.id }, 'Failed to update scan status after error');
                }
            });
            return scan;
        }
        catch (error) {
            await client.query('ROLLBACK');
            logger_1.logger.error({ error, userId, provider }, 'Error initiating email scan');
            throw error;
        }
        finally {
            client.release();
        }
    }
    /**
     * Perform the actual email scanning (runs in background)
     */
    static async performScan(scanId, userId, provider, accessToken, options) {
        try {
            if (!config_1.config.openai?.apiKey) {
                await db_1.pool.query(`UPDATE email_scans
           SET status = 'failed',
               error_message = $2,
               completed_at = NOW()
           WHERE id = $1`, [scanId, 'OpenAI API key is not configured']);
                logger_1.logger.warn({ scanId }, 'Email scan aborted: missing OpenAI API key');
                return;
            }
            // Update status to scanning
            await db_1.pool.query(`UPDATE email_scans SET status = 'scanning' WHERE id = $1`, [scanId]);
            let receipts = [];
            if (provider === 'gmail') {
                receipts = await this.scanGmail(accessToken, options);
            }
            else if (provider === 'outlook') {
                receipts = await this.scanOutlook(accessToken, options);
            }
            logger_1.logger.info({ scanId, receiptsFound: receipts.length }, 'Email scan completed');
            // Filter for appliances and electronics
            const relevantReceipts = receipts.filter((r) => this.isRelevantPurchase(r.productName, r.category));
            // Import items
            let importedCount = 0;
            for (const receipt of relevantReceipts) {
                try {
                    await this.createItemFromReceipt(userId, receipt, scanId);
                    importedCount++;
                }
                catch (error) {
                    logger_1.logger.warn({ error, receipt }, 'Failed to import receipt');
                }
            }
            // Update scan record
            await db_1.pool.query(`UPDATE email_scans
         SET status = 'completed',
             emails_scanned = $2,
             receipts_found = $3,
             items_imported = $4,
             completed_at = NOW()
         WHERE id = $1`, [scanId, receipts.length, relevantReceipts.length, importedCount]);
            // Update user analytics
            await db_1.pool.query(`UPDATE user_analytics
         SET email_scans_completed = email_scans_completed + 1,
             items_added_via_email = items_added_via_email + $2,
             has_scanned_email = TRUE,
             updated_at = NOW()
         WHERE user_id = $1`, [userId, importedCount]);
            logger_1.logger.info({ scanId, userId, importedCount }, 'Email scan completed successfully');
        }
        catch (error) {
            logger_1.logger.error({ error, scanId }, 'Error performing email scan');
            await db_1.pool.query(`UPDATE email_scans
         SET status = 'failed',
             error_message = $2,
             completed_at = NOW()
         WHERE id = $1`, [scanId, error.message]);
        }
    }
    /**
     * Scan Gmail for receipts
     */
    static async scanGmail(accessToken, options) {
        const oauth2Client = new googleapis_1.google.auth.OAuth2();
        oauth2Client.setCredentials({ access_token: accessToken });
        const gmail = googleapis_1.google.gmail({ version: 'v1', auth: oauth2Client });
        const receipts = [];
        // Define search queries for major retailers
        const queries = [
            'from:(orders@amazon.com OR auto-confirm@amazon.com) subject:(order OR receipt)',
            'from:bestbuy.com subject:(receipt OR order OR purchase)',
            'from:homedepot.com subject:(receipt OR order)',
            'from:lowes.com subject:(order OR receipt)',
            'from:target.com subject:(receipt OR order)',
            'from:walmart.com subject:(order OR receipt)',
            'from:costco.com subject:(receipt OR order)',
            'from:samsclub.com subject:(receipt OR order)',
            'from:wayfair.com subject:(order OR receipt)',
            'receipt OR purchase OR order', // General search
        ];
        // Build date query
        let dateQuery = '';
        if (options.dateRangeStart) {
            const startDate = new Date(options.dateRangeStart);
            dateQuery += ` after:${startDate.getFullYear()}/${startDate.getMonth() + 1}/${startDate.getDate()}`;
        }
        if (options.dateRangeEnd) {
            const endDate = new Date(options.dateRangeEnd);
            dateQuery += ` before:${endDate.getFullYear()}/${endDate.getMonth() + 1}/${endDate.getDate()}`;
        }
        for (const baseQuery of queries) {
            try {
                const query = baseQuery + dateQuery;
                const messagesResponse = await gmail.users.messages.list({
                    userId: 'me',
                    q: query,
                    maxResults: 100,
                });
                const messages = messagesResponse.data.messages || [];
                for (const message of messages.slice(0, 50)) {
                    // Limit to 50 per query
                    try {
                        const messageData = await gmail.users.messages.get({
                            userId: 'me',
                            id: message.id,
                            format: 'full',
                        });
                        const emailData = this.parseGmailMessage(messageData.data);
                        const extracted = await this.extractReceiptData(emailData);
                        if (extracted) {
                            receipts.push(extracted);
                        }
                    }
                    catch (error) {
                        logger_1.logger.warn({ error, messageId: message.id }, 'Failed to process Gmail message');
                    }
                }
            }
            catch (error) {
                logger_1.logger.warn({ error, query: baseQuery }, 'Failed to query Gmail');
            }
        }
        return receipts;
    }
    /**
     * Scan Outlook for receipts
     */
    static async scanOutlook(accessToken, options) {
        const receipts = [];
        try {
            // Build filter query
            let filter = `contains(subject, 'receipt') or contains(subject, 'order') or contains(subject, 'purchase')`;
            if (options.dateRangeStart) {
                filter += ` and receivedDateTime ge ${new Date(options.dateRangeStart).toISOString()}`;
            }
            if (options.dateRangeEnd) {
                filter += ` and receivedDateTime le ${new Date(options.dateRangeEnd).toISOString()}`;
            }
            const response = await axios_1.default.get('https://graph.microsoft.com/v1.0/me/messages', {
                headers: {
                    Authorization: `Bearer ${accessToken}`,
                },
                params: {
                    $filter: filter,
                    $top: 100,
                    $select: 'subject,from,receivedDateTime,body',
                },
            });
            const messages = response.data.value || [];
            for (const message of messages.slice(0, 50)) {
                try {
                    const emailData = {
                        subject: message.subject,
                        from: message.from?.emailAddress?.address || '',
                        date: message.receivedDateTime,
                        body: message.body?.content || '',
                    };
                    const extracted = await this.extractReceiptData(emailData);
                    if (extracted) {
                        receipts.push(extracted);
                    }
                }
                catch (error) {
                    logger_1.logger.warn({ error, messageId: message.id }, 'Failed to process Outlook message');
                }
            }
        }
        catch (error) {
            logger_1.logger.error({ error }, 'Failed to scan Outlook');
            throw error;
        }
        return receipts;
    }
    /**
     * Parse Gmail message to extract relevant data
     */
    static parseGmailMessage(message) {
        const headers = message.payload?.headers || [];
        const subject = headers.find((h) => h.name === 'Subject')?.value || '';
        const from = headers.find((h) => h.name === 'From')?.value || '';
        const date = headers.find((h) => h.name === 'Date')?.value || '';
        // Extract body
        let body = '';
        if (message.payload?.body?.data) {
            body = Buffer.from(message.payload.body.data, 'base64').toString('utf-8');
        }
        else if (message.payload?.parts) {
            const textPart = message.payload.parts.find((p) => p.mimeType === 'text/plain' || p.mimeType === 'text/html');
            if (textPart?.body?.data) {
                body = Buffer.from(textPart.body.data, 'base64').toString('utf-8');
            }
        }
        return { subject, from, date, body };
    }
    /**
     * Extract receipt data using AI (OpenAI or Anthropic)
     */
    static async extractReceiptData(emailData) {
        try {
            // Use OpenAI (or Anthropic) to extract structured data
            const response = await axios_1.default.post('https://api.openai.com/v1/chat/completions', {
                model: 'gpt-4o-mini', // Cheaper, faster model
                messages: [
                    {
                        role: 'system',
                        content: `You are an AI that extracts purchase information from receipt emails.
Extract the following information and return as JSON:
- productName: Name of the product (if multiple, pick the most expensive/important appliance or electronic)
- brand: Brand name
- price: Total price (number only)
- purchaseDate: Date of purchase (ISO format)
- warrantyPeriod: Warranty period in months (default 12 if not specified)
- store: Store name
- modelNumber: Model number if available
- serialNumber: Serial number if available
- category: Best matching category (refrigerator, dishwasher, washer, dryer, oven_range, microwave, hvac, water_heater, tv, computer, other)

Only extract if this is clearly a purchase receipt for a physical product.
Focus on appliances, electronics, HVAC, and home systems.
Return null if this is not a product purchase receipt.`,
                    },
                    {
                        role: 'user',
                        content: `Subject: ${emailData.subject}
From: ${emailData.from}
Date: ${emailData.date}

Body (first 2000 chars):
${emailData.body.substring(0, 2000)}`,
                    },
                ],
                response_format: { type: 'json_object' },
                temperature: 0,
            }, {
                headers: {
                    'Authorization': `Bearer ${config_1.config.openai?.apiKey || process.env.OPENAI_API_KEY}`,
                    'Content-Type': 'application/json',
                },
            });
            let extracted;
            try {
                extracted = JSON.parse(response.data.choices[0].message.content);
            }
            catch (parseError) {
                logger_1.logger.warn({ parseError, subject: emailData.subject }, 'Failed to parse AI response as JSON');
                return null;
            }
            if (!extracted || !extracted.productName) {
                return null;
            }
            return {
                ...extracted,
                emailSubject: emailData.subject,
                emailDate: emailData.date,
            };
        }
        catch (error) {
            logger_1.logger.warn({ error, subject: emailData.subject }, 'Failed to extract receipt data with AI');
            return null;
        }
    }
    /**
     * Check if product is relevant (appliances, electronics, HVAC)
     */
    static isRelevantPurchase(productName, category) {
        const relevantCategories = [
            'refrigerator',
            'dishwasher',
            'washer',
            'dryer',
            'oven_range',
            'microwave',
            'hvac',
            'water_heater',
            'tv',
            'computer',
            'garbage_disposal',
            'range_hood',
            'furnace',
        ];
        if (category && relevantCategories.includes(category)) {
            return true;
        }
        // Check product name for keywords
        const keywords = [
            'refrigerator',
            'fridge',
            'dishwasher',
            'washer',
            'dryer',
            'oven',
            'range',
            'microwave',
            'hvac',
            'air conditioner',
            'furnace',
            'water heater',
            'television',
            'tv',
            'laptop',
            'computer',
            'disposal',
            'hood',
        ];
        const lowerName = productName.toLowerCase();
        return keywords.some((keyword) => lowerName.includes(keyword));
    }
    /**
     * Create item from extracted receipt
     */
    static async createItemFromReceipt(userId, receipt, scanId) {
        const client = await db_1.pool.connect();
        try {
            await client.query('BEGIN');
            // Get user's default home
            const homeResult = await client.query('SELECT id FROM homes WHERE user_id = $1 ORDER BY created_at ASC LIMIT 1', [userId]);
            if (homeResult.rows.length === 0) {
                throw new errors_1.AppError('User has no home', 400);
            }
            const homeId = homeResult.rows[0].id;
            const purchaseDate = receipt.purchaseDate
                ? new Date(receipt.purchaseDate)
                : new Date(receipt.emailDate || Date.now());
            const warrantyMonths = receipt.warrantyPeriod || 12;
            const warrantyEndDate = new Date(purchaseDate);
            const expectedMonth = (warrantyEndDate.getMonth() + warrantyMonths) % 12;
            warrantyEndDate.setMonth(warrantyEndDate.getMonth() + warrantyMonths);
            if (warrantyEndDate.getMonth() !== expectedMonth) {
                warrantyEndDate.setDate(0);
            }
            // Create item
            await client.query(`INSERT INTO items (
          home_id, user_id, name, brand, model_number, serial_number,
          category, purchase_date, store, price,
          warranty_months, warranty_end_date, warranty_type,
          notes, added_via
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`, [
                homeId,
                userId,
                receipt.productName,
                receipt.brand,
                receipt.modelNumber,
                receipt.serialNumber,
                receipt.category || 'other',
                purchaseDate,
                receipt.store,
                receipt.price,
                warrantyMonths,
                warrantyEndDate,
                'manufacturer',
                `Imported from email: ${receipt.emailSubject}`,
                'email',
            ]);
            await client.query('COMMIT');
            logger_1.logger.info({ userId, scanId, productName: receipt.productName }, 'Item created from receipt');
        }
        catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        finally {
            client.release();
        }
    }
    /**
     * Get scan status
     */
    static async getScanStatus(scanId, userId) {
        try {
            const result = await db_1.pool.query('SELECT * FROM email_scans WHERE id = $1 AND user_id = $2', [scanId, userId]);
            if (result.rows.length === 0) {
                throw new errors_1.AppError('Scan not found', 404);
            }
            return result.rows[0];
        }
        catch (error) {
            logger_1.logger.error({ error, scanId, userId }, 'Error fetching scan status');
            throw error;
        }
    }
    /**
     * Get user's scan history
     */
    static async getUserScans(userId) {
        try {
            const result = await db_1.pool.query(`SELECT * FROM email_scans
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 10`, [userId]);
            return result.rows;
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error fetching user scans');
            throw error;
        }
    }
}
exports.EmailScannerService = EmailScannerService;
//# sourceMappingURL=email-scanner.service.js.map