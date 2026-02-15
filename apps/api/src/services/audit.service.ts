import { pool } from '../db';
import { Request } from 'express';

export type AuditAction =
  // Authentication
  | 'auth.login'
  | 'auth.logout'
  | 'auth.logout_all'
  | 'auth.register'
  | 'auth.password_reset_request'
  | 'auth.password_reset_complete'
  | 'auth.email_verify'
  | 'auth.token_refresh'
  | 'auth.oauth_login'
  // User actions
  | 'user.create'
  | 'user.update'
  | 'user.delete'
  | 'user.plan_upgrade'
  | 'user.plan_downgrade'
  // Item actions
  | 'item.create'
  | 'item.update'
  | 'item.delete'
  | 'item.archive'
  | 'item.unarchive'
  | 'item.transfer'
  // Home actions
  | 'home.create'
  | 'home.update'
  | 'home.delete'
  // Document actions
  | 'document.upload'
  | 'document.delete'
  | 'document.view'
  // Admin actions
  | 'admin.user_impersonate'
  | 'admin.user_delete'
  | 'admin.partner_approve'
  | 'admin.partner_reject'
  | 'admin.settings_change'
  // Partner actions
  | 'partner.gift_create'
  | 'partner.gift_update'
  | 'partner.gift_activate'
  | 'partner.warranty_create'
  | 'partner.warranty_update'
  // Security events
  | 'security.unauthorized_access'
  | 'security.rate_limit_exceeded'
  | 'security.suspicious_activity'
  | 'security.api_key_used'
  // System events
  | 'system.error'
  | 'system.maintenance_start'
  | 'system.maintenance_end';

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

export class AuditService {
  /**
   * Create an audit log entry
   */
  static async log(params: CreateAuditLogParams): Promise<AuditLogEntry> {
    const {
      userId,
      userEmail,
      action,
      severity = 'info',
      resourceType,
      resourceId,
      description,
      metadata,
      ipAddress,
      userAgent,
      endpoint,
      httpMethod,
      success = true,
      errorMessage,
    } = params;

    const result = await pool.query<AuditLogEntry>(
      `INSERT INTO audit_logs (
        user_id, user_email, action, severity,
        resource_type, resource_id, description, metadata,
        ip_address, user_agent, endpoint, http_method,
        success, error_message
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *`,
      [
        userId || null,
        userEmail || null,
        action,
        severity,
        resourceType || null,
        resourceId || null,
        description || null,
        metadata ? JSON.stringify(metadata) : null,
        ipAddress || null,
        userAgent || null,
        endpoint || null,
        httpMethod || null,
        success,
        errorMessage || null,
      ]
    );

    return result.rows[0];
  }

  /**
   * Create audit log from Express request
   */
  static async logFromRequest(
    req: Request,
    action: AuditAction,
    options: {
      severity?: AuditSeverity;
      resourceType?: string;
      resourceId?: string;
      description?: string;
      metadata?: Record<string, any>;
      success?: boolean;
      errorMessage?: string;
    } = {}
  ): Promise<AuditLogEntry> {
    const user = (req as any).user;

    return this.log({
      userId: user?.id,
      userEmail: user?.email,
      action,
      severity: options.severity,
      resourceType: options.resourceType,
      resourceId: options.resourceId,
      description: options.description,
      metadata: options.metadata,
      ipAddress: this.getIpAddress(req),
      userAgent: req.get('user-agent'),
      endpoint: req.path,
      httpMethod: req.method,
      success: options.success,
      errorMessage: options.errorMessage,
    });
  }

  /**
   * Log authentication event
   */
  static async logAuth(params: {
    action: AuditAction;
    userId?: string;
    email?: string;
    ipAddress?: string;
    userAgent?: string;
    success?: boolean;
    errorMessage?: string;
    metadata?: Record<string, any>;
  }): Promise<AuditLogEntry> {
    return this.log({
      userId: params.userId,
      userEmail: params.email,
      action: params.action,
      severity: params.success === false ? 'warning' : 'info',
      ipAddress: params.ipAddress,
      userAgent: params.userAgent,
      success: params.success ?? true,
      errorMessage: params.errorMessage,
      metadata: params.metadata,
    });
  }

  /**
   * Log security event
   */
  static async logSecurity(params: {
    action: AuditAction;
    userId?: string;
    email?: string;
    ipAddress?: string;
    userAgent?: string;
    description: string;
    severity?: AuditSeverity;
    metadata?: Record<string, any>;
  }): Promise<AuditLogEntry> {
    return this.log({
      userId: params.userId,
      userEmail: params.email,
      action: params.action,
      severity: params.severity || 'warning',
      description: params.description,
      ipAddress: params.ipAddress,
      userAgent: params.userAgent,
      metadata: params.metadata,
    });
  }

  /**
   * Log resource change (create, update, delete)
   */
  static async logResourceChange(params: {
    action: AuditAction;
    userId: string;
    userEmail?: string;
    resourceType: string;
    resourceId: string;
    description?: string;
    oldValue?: any;
    newValue?: any;
    changes?: Record<string, any>;
  }): Promise<AuditLogEntry> {
    const metadata: Record<string, any> = {};

    if (params.oldValue !== undefined) {
      metadata.old_value = params.oldValue;
    }

    if (params.newValue !== undefined) {
      metadata.new_value = params.newValue;
    }

    if (params.changes) {
      metadata.changes = params.changes;
    }

    return this.log({
      userId: params.userId,
      userEmail: params.userEmail,
      action: params.action,
      severity: 'info',
      resourceType: params.resourceType,
      resourceId: params.resourceId,
      description: params.description,
      metadata,
    });
  }

  /**
   * Query audit logs with filters
   */
  static async query(filters: AuditLogFilters = {}): Promise<{
    logs: AuditLogEntry[];
    total: number;
  }> {
    const {
      userId,
      action,
      severity,
      resourceType,
      resourceId,
      startDate,
      endDate,
      success,
      limit = 100,
      offset = 0,
    } = filters;

    const conditions: string[] = [];
    const params: any[] = [];
    let paramIndex = 1;

    if (userId) {
      conditions.push(`user_id = $${paramIndex++}`);
      params.push(userId);
    }

    if (action) {
      conditions.push(`action = $${paramIndex++}`);
      params.push(action);
    }

    if (severity) {
      conditions.push(`severity = $${paramIndex++}`);
      params.push(severity);
    }

    if (resourceType) {
      conditions.push(`resource_type = $${paramIndex++}`);
      params.push(resourceType);
    }

    if (resourceId) {
      conditions.push(`resource_id = $${paramIndex++}`);
      params.push(resourceId);
    }

    if (startDate) {
      conditions.push(`created_at >= $${paramIndex++}`);
      params.push(startDate);
    }

    if (endDate) {
      conditions.push(`created_at <= $${paramIndex++}`);
      params.push(endDate);
    }

    if (success !== undefined) {
      conditions.push(`success = $${paramIndex++}`);
      params.push(success);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    // Get total count — uses only the filter params ($1..$N)
    const countResult = await pool.query<{ count: string }>(
      `SELECT COUNT(*) as count FROM audit_logs ${whereClause}`,
      params
    );

    const total = parseInt(countResult.rows[0].count, 10);

    // Get paginated results — extends the filter params with LIMIT and OFFSET.
    // paramIndex is currently N+1 (where N = number of filter params), so LIMIT
    // becomes $N+1 and OFFSET becomes $N+2, matching the spread [...params, limit, offset].
    const limitIndex = paramIndex++;
    const offsetIndex = paramIndex++;
    const logsResult = await pool.query<AuditLogEntry>(
      `SELECT * FROM audit_logs
       ${whereClause}
       ORDER BY created_at DESC
       LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
      [...params, limit, offset]
    );

    return {
      logs: logsResult.rows,
      total,
    };
  }

  /**
   * Get audit logs for a specific user
   */
  static async getUserLogs(
    userId: string,
    limit: number = 50,
    offset: number = 0
  ): Promise<{ logs: AuditLogEntry[]; total: number }> {
    return this.query({ userId, limit, offset });
  }

  /**
   * Get audit logs for a specific resource
   */
  static async getResourceLogs(
    resourceType: string,
    resourceId: string,
    limit: number = 50,
    offset: number = 0
  ): Promise<{ logs: AuditLogEntry[]; total: number }> {
    return this.query({ resourceType, resourceId, limit, offset });
  }

  /**
   * Get recent security events
   */
  static async getRecentSecurityEvents(
    limit: number = 100
  ): Promise<AuditLogEntry[]> {
    const result = await pool.query<AuditLogEntry>(
      `SELECT * FROM recent_security_events
       ORDER BY created_at DESC
       LIMIT $1`,
      [limit]
    );

    return result.rows;
  }

  /**
   * Get user activity summary
   */
  static async getUserActivitySummary(userId?: string): Promise<any[]> {
    if (userId) {
      const result = await pool.query(
        `SELECT * FROM user_activity_summary WHERE user_id = $1`,
        [userId]
      );
      return result.rows;
    }

    const result = await pool.query(
      `SELECT * FROM user_activity_summary ORDER BY last_activity DESC NULLS LAST`
    );
    return result.rows;
  }

  /**
   * Clean up old audit logs (based on retention policy)
   */
  static async cleanup(): Promise<void> {
    await pool.query('SELECT cleanup_old_audit_logs()');
  }

  /**
   * Get statistics about audit logs
   */
  static async getStats(startDate?: Date, endDate?: Date): Promise<{
    total: number;
    by_severity: Record<string, number>;
    by_action: Record<string, number>;
    failed_actions: number;
  }> {
    const conditions: string[] = [];
    const params: any[] = [];
    let paramIndex = 1;

    if (startDate) {
      conditions.push(`created_at >= $${paramIndex++}`);
      params.push(startDate);
    }

    if (endDate) {
      conditions.push(`created_at <= $${paramIndex++}`);
      params.push(endDate);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    // Use two separate queries to avoid cartesian join
    const summaryResult = await pool.query(
      `SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE severity = 'info') as severity_info,
        COUNT(*) FILTER (WHERE severity = 'warning') as severity_warning,
        COUNT(*) FILTER (WHERE severity = 'error') as severity_error,
        COUNT(*) FILTER (WHERE severity = 'critical') as severity_critical,
        COUNT(*) FILTER (WHERE success = FALSE) as failed_actions
       FROM audit_logs
       ${whereClause}`,
      params
    );

    const breakdownResult = await pool.query(
      `SELECT jsonb_object_agg(action, action_count) as actions_breakdown
       FROM (
         SELECT action, COUNT(*) as action_count
         FROM audit_logs
         ${whereClause}
         GROUP BY action
       ) action_counts`,
      params
    );

    const row = summaryResult.rows[0];

    return {
      total: parseInt(row.total, 10),
      by_severity: {
        info: parseInt(row.severity_info, 10),
        warning: parseInt(row.severity_warning, 10),
        error: parseInt(row.severity_error, 10),
        critical: parseInt(row.severity_critical, 10),
      },
      by_action: breakdownResult.rows[0]?.actions_breakdown || {},
      failed_actions: parseInt(row.failed_actions, 10),
    };
  }

  /**
   * Helper: Extract IP address from request
   */
  private static getIpAddress(req: Request): string {
    return (
      (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
      (req.headers['x-real-ip'] as string) ||
      req.socket.remoteAddress ||
      'unknown'
    );
  }
}
