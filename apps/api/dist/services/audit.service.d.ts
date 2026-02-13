import { Request } from 'express';
export type AuditAction = 'auth.login' | 'auth.logout' | 'auth.register' | 'auth.password_reset_request' | 'auth.password_reset_complete' | 'auth.email_verify' | 'auth.token_refresh' | 'auth.oauth_login' | 'user.create' | 'user.update' | 'user.delete' | 'user.plan_upgrade' | 'user.plan_downgrade' | 'item.create' | 'item.update' | 'item.delete' | 'item.archive' | 'item.unarchive' | 'item.transfer' | 'home.create' | 'home.update' | 'home.delete' | 'document.upload' | 'document.delete' | 'document.view' | 'admin.user_impersonate' | 'admin.user_delete' | 'admin.partner_approve' | 'admin.partner_reject' | 'admin.settings_change' | 'partner.gift_create' | 'partner.gift_update' | 'partner.gift_activate' | 'partner.warranty_create' | 'partner.warranty_update' | 'security.unauthorized_access' | 'security.rate_limit_exceeded' | 'security.suspicious_activity' | 'security.api_key_used' | 'system.error' | 'system.maintenance_start' | 'system.maintenance_end';
export type AuditSeverity = 'info' | 'warning' | 'error' | 'critical';
export interface AuditLogEntry {
    id: string;
    user_id?: string;
    user_email?: string;
    action: AuditAction;
    severity: AuditSeverity;
    resource_type?: string;
    resource_id?: string;
    description?: string;
    metadata?: Record<string, any>;
    ip_address?: string;
    user_agent?: string;
    endpoint?: string;
    http_method?: string;
    success: boolean;
    error_message?: string;
    created_at: Date;
}
export interface CreateAuditLogParams {
    userId?: string;
    userEmail?: string;
    action: AuditAction;
    severity?: AuditSeverity;
    resourceType?: string;
    resourceId?: string;
    description?: string;
    metadata?: Record<string, any>;
    ipAddress?: string;
    userAgent?: string;
    endpoint?: string;
    httpMethod?: string;
    success?: boolean;
    errorMessage?: string;
}
export interface AuditLogFilters {
    userId?: string;
    action?: AuditAction;
    severity?: AuditSeverity;
    resourceType?: string;
    resourceId?: string;
    startDate?: Date;
    endDate?: Date;
    success?: boolean;
    limit?: number;
    offset?: number;
}
export declare class AuditService {
    /**
     * Create an audit log entry
     */
    static log(params: CreateAuditLogParams): Promise<AuditLogEntry>;
    /**
     * Create audit log from Express request
     */
    static logFromRequest(req: Request, action: AuditAction, options?: {
        severity?: AuditSeverity;
        resourceType?: string;
        resourceId?: string;
        description?: string;
        metadata?: Record<string, any>;
        success?: boolean;
        errorMessage?: string;
    }): Promise<AuditLogEntry>;
    /**
     * Log authentication event
     */
    static logAuth(params: {
        action: AuditAction;
        userId?: string;
        email?: string;
        ipAddress?: string;
        userAgent?: string;
        success?: boolean;
        errorMessage?: string;
        metadata?: Record<string, any>;
    }): Promise<AuditLogEntry>;
    /**
     * Log security event
     */
    static logSecurity(params: {
        action: AuditAction;
        userId?: string;
        email?: string;
        ipAddress?: string;
        userAgent?: string;
        description: string;
        severity?: AuditSeverity;
        metadata?: Record<string, any>;
    }): Promise<AuditLogEntry>;
    /**
     * Log resource change (create, update, delete)
     */
    static logResourceChange(params: {
        action: AuditAction;
        userId: string;
        userEmail?: string;
        resourceType: string;
        resourceId: string;
        description?: string;
        oldValue?: any;
        newValue?: any;
        changes?: Record<string, any>;
    }): Promise<AuditLogEntry>;
    /**
     * Query audit logs with filters
     */
    static query(filters?: AuditLogFilters): Promise<{
        logs: AuditLogEntry[];
        total: number;
    }>;
    /**
     * Get audit logs for a specific user
     */
    static getUserLogs(userId: string, limit?: number, offset?: number): Promise<{
        logs: AuditLogEntry[];
        total: number;
    }>;
    /**
     * Get audit logs for a specific resource
     */
    static getResourceLogs(resourceType: string, resourceId: string, limit?: number, offset?: number): Promise<{
        logs: AuditLogEntry[];
        total: number;
    }>;
    /**
     * Get recent security events
     */
    static getRecentSecurityEvents(limit?: number): Promise<AuditLogEntry[]>;
    /**
     * Get user activity summary
     */
    static getUserActivitySummary(userId?: string): Promise<any[]>;
    /**
     * Clean up old audit logs (based on retention policy)
     */
    static cleanup(): Promise<void>;
    /**
     * Get statistics about audit logs
     */
    static getStats(startDate?: Date, endDate?: Date): Promise<{
        total: number;
        by_severity: Record<string, number>;
        by_action: Record<string, number>;
        failed_actions: number;
    }>;
    /**
     * Helper: Extract IP address from request
     */
    private static getIpAddress;
}
//# sourceMappingURL=audit.service.d.ts.map