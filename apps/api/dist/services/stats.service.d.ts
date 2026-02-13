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