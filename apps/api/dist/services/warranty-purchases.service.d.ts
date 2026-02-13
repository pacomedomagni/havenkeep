import { WarrantyPurchase } from '../types/database.types';
interface CreateWarrantyPurchaseData {
    item_id: string;
    provider: string;
    plan_name: string;
    external_policy_id?: string;
    duration_months: number;
    starts_at: string;
    coverage_details?: Record<string, any>;
    price: number;
    deductible?: number;
    claim_limit?: number;
    commission_amount?: number;
    commission_rate?: number;
    stripe_payment_intent_id?: string;
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
     * Update warranty purchase status (internal method, e.g., for auto-expiring)
     */
    static updatePurchaseStatus(purchaseId: string, status: 'active' | 'expired' | 'cancelled' | 'pending'): Promise<WarrantyPurchase>;
}
export {};
//# sourceMappingURL=warranty-purchases.service.d.ts.map