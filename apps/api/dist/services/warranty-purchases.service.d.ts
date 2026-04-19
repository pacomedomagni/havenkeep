import { WarrantyPurchase } from '../types/database.types';
interface CreateWarrantyPurchaseData {
    itemId: string;
    provider: string;
    planName: string;
    externalPolicyId?: string;
    durationMonths: number;
    startsAt: string;
    coverageDetails?: Record<string, any>;
    price: number;
    deductible?: number;
    claimLimit?: number;
    commissionAmount?: number;
    commissionRate?: number;
    stripePaymentIntentId?: string;
}
export declare class WarrantyPurchasesService {
    /**
     * Get all warranty purchases for a user with pagination and optional filters
     */
    static getUserPurchases(userId: string, options?: {
        limit?: number;
        offset?: number;
        itemId?: string;
        status?: string;
    }): Promise<{
        purchases: WarrantyPurchase[];
        total: number;
    }>;
    /**
     * Get a single warranty purchase by ID with ownership check
     */
    static getPurchaseById(purchaseId: string, userId: string): Promise<WarrantyPurchase>;
    /**
     * Create a new warranty purchase
     */
    static createPurchase(userId: string, data: CreateWarrantyPurchaseData): Promise<WarrantyPurchase>;
    /**
     * Cancel a warranty purchase
     */
    static cancelPurchase(purchaseId: string, userId: string, reason?: string): Promise<WarrantyPurchase>;
    /**
     * Get all active warranty coverage grouped by item
     */
    static getActiveCoverage(userId: string): Promise<any[]>;
    /**
     * Get warranties expiring within N days
     */
    static getExpiringWarranties(userId: string, daysAhead?: number): Promise<WarrantyPurchase[]>;
    /**
     * Expire all overdue active warranties in a single batch update.
     * Designed to be called from a daily scheduled job.
     */
    static expireOverdueWarranties(): Promise<number>;
}
export {};
//# sourceMappingURL=warranty-purchases.service.d.ts.map