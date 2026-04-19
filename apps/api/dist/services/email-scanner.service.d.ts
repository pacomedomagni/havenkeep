import { EmailScan } from '../types/database.types';
export declare class EmailScannerService {
    /**
     * Initiate email scan
     */
    static initiateScan(userId: string, provider: 'gmail' | 'outlook', accessToken: string, options?: {
        dateRangeStart?: string;
        dateRangeEnd?: string;
    }): Promise<EmailScan>;
    /**
     * Perform the actual email scanning (runs in background)
     */
    private static performScan;
    /**
     * Scan Gmail for receipts
     */
    private static scanGmail;
    /**
     * Scan Outlook for receipts
     */
    private static scanOutlook;
    /**
     * Parse Gmail message to extract relevant data
     */
    private static parseGmailMessage;
    /**
     * Extract receipt data using AI (OpenAI or Anthropic)
     *
     * PRIVACY NOTE: Email body content (up to 2000 chars) is sent to OpenAI for
     * receipt extraction. Ensure users are informed of this in the app's privacy
     * policy and terms of service. The access token is used only for email access
     * and is not stored.
     */
    private static extractReceiptData;
    /**
     * Check if product is relevant (appliances, electronics, HVAC)
     */
    private static isRelevantPurchase;
    /**
     * Create item from extracted receipt.
     * Returns true if item was created, false if skipped due to free plan limit.
     */
    private static createItemFromReceipt;
    /**
     * Get scan status
     */
    static getScanStatus(scanId: string, userId: string): Promise<EmailScan>;
    /**
     * Get user's scan history
     */
    static getUserScans(userId: string): Promise<EmailScan[]>;
}
//# sourceMappingURL=email-scanner.service.d.ts.map