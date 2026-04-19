import { DashboardStats, UserAnalytics } from '../types/database.types';
export declare class StatsService {
    /**
     * Get dashboard statistics for user
     */
    static getDashboardStats(userId: string): Promise<DashboardStats>;
    /**
     * Calculate and update health score for user
     */
    static calculateHealthScore(userId: string): Promise<number>;
    /**
     * Get user analytics
     */
    static getUserAnalytics(userId: string): Promise<UserAnalytics>;
    /**
     * Update user engagement metrics
     */
    static trackEngagement(userId: string, event: {
        type: 'app_open' | 'session_start' | 'session_end';
        sessionDuration?: number;
    }): Promise<void>;
    /**
     * Get items needing attention
     */
    static getItemsNeedingAttention(userId: string, limit?: number): Promise<any[]>;
    /**
     * Get health score breakdown/components
     *
     * NOTE: The overall `score` is the single source of truth and is computed by
     * the DB function `calculate_health_score` (see migration 002_enhanced_features.sql).
     * The `components` array below mirrors that function's logic for display purposes.
     *
     * IMPORTANT: If the scoring logic changes, update BOTH the DB function AND the
     * component breakdown below to keep them consistent. The DB function is authoritative;
     * the JS breakdown is derived from the same inputs to show users how their score
     * breaks down.
     *
     * Current scoring formula (must match DB function):
     *   Items Tracked:         min(total_items * 2, 30)               max 30 pts
     *   Active Warranties:     min(active_warranties * 3, 25)         max 25 pts
     *   Documentation:         min(floor(documented/total * 20), 20)  max 20 pts
     *   Maintenance (6mo):     min(recent_maintenance_count, 15)      max 15 pts
     *   Expired Penalty:       -min(expired_count * 2, 10)            max -10 pts
     *   Final score clamped to [0, 100].
     */
    static getHealthScoreBreakdown(userId: string): Promise<{
        score: number;
        components: Array<{
            name: string;
            points: number;
            max_points: number;
            status: 'good' | 'warning' | 'needs_improvement';
            suggestion?: string;
        }>;
    }>;
    /**
     * Track feature usage
     */
    static trackFeatureUsage(userId: string, feature: 'email_scan' | 'manual_add' | 'email_add' | 'barcode_add' | 'document_upload' | 'report_generated' | 'claim_filed'): Promise<void>;
}
//# sourceMappingURL=stats.service.d.ts.map