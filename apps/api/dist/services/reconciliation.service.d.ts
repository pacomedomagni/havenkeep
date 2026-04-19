/**
 * ReconciliationService — detects and fixes drift between source tables
 * and the denormalized `user_analytics` counters.
 *
 * Designed to run periodically (e.g., weekly) to ensure analytics accuracy.
 */
export declare class ReconciliationService {
    /**
     * Reconcile `total_warranty_savings`, `total_claims_filed`, and
     * `total_maintenance_completed` in `user_analytics` by recalculating
     * from the source-of-truth tables (warranty_claims, maintenance_history).
     *
     * Any discrepancy is logged and corrected in-place.
     */
    static reconcileUserAnalytics(): Promise<{
        usersChecked: number;
        discrepanciesFound: number;
        discrepanciesFixed: number;
    }>;
}
//# sourceMappingURL=reconciliation.service.d.ts.map