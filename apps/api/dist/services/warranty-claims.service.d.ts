import { WarrantyClaim, CreateWarrantyClaimDto, SavingsFeedEntry } from '../types/database.types';
export declare class WarrantyClaimsService {
    /**
     * Create a new warranty claim
     */
    static createClaim(userId: string, data: CreateWarrantyClaimDto): Promise<WarrantyClaim>;
    /**
     * Get all claims for a user
     */
    static getUserClaims(userId: string, options?: {
        limit?: number;
        offset?: number;
        itemId?: string;
    }): Promise<{
        claims: WarrantyClaim[];
        total: number;
    }>;
    /**
     * Get claim by ID
     */
    static getClaimById(claimId: string, userId: string): Promise<WarrantyClaim>;
    /**
     * Update warranty claim
     */
    static updateClaim(claimId: string, userId: string, data: Partial<CreateWarrantyClaimDto>): Promise<WarrantyClaim>;
    /**
     * Delete warranty claim
     */
    static deleteClaim(claimId: string, userId: string): Promise<void>;
    /**
     * Get total savings for user
     */
    static getTotalSavings(userId: string): Promise<{
        total_warranty_savings: number;
        total_preventive_savings: number;
        total_savings: number;
        total_claims: number;
    }>;
    /**
     * Get savings feed (public social proof)
     */
    static getSavingsFeed(limit?: number): Promise<SavingsFeedEntry[]>;
}
//# sourceMappingURL=warranty-claims.service.d.ts.map