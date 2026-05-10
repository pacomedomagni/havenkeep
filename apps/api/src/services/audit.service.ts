import type { PoolClient } from 'pg';
import { pool } from '../db';
import { Request } from 'express';
import { getIpAddress as resolveIpAddress } from '../utils/ip-address';

// F092: deep OFFSET pagination scans the entire table; cap so an attacker
// can't DoS us with /audit/logs?offset=1000000.
const MAX_AUDIT_OFFSET = 1000;

// F094: metadata payload size cap. Mirrors the CHECK installed in
// migration 065 so service-side rejects are friendly (400) instead of
// surfacing as a Postgres constraint violation.
const MAX_METADATA_BYTES = 8 * 1024;

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
  // 4.5: a suspended account that re-verifies premium isn't an
  // "upgrade" (the user wasn't on free → went to paid; they were
  // *blocked* and got their access restored). Different label so
  // forensics can tell the difference.
  | 'user.plan_reactivate'
  | 'user.email_change_requested'
  // Item actions
  | 'item.create'
  | 'item.update'
  | 'item.delete'
  | 'item.archive'
  | 'item.unarchive'
  | 'item.transfer'
  | 'item.export'
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
  // H76: commission state-change audit trail. DB enum gets these via
  // migration 104.
  | 'admin.commission_approve'
  | 'admin.commission_pay'
  | 'admin.commission_cancel'
  // Partner actions
  | 'partner.gift_create'
  | 'partner.gift_update'
  | 'partner.gift_activate'
  | 'partner.warranty_create'
  | 'partner.warranty_update'
  | 'partner.payout_request'
  // Security events
  | 'security.unauthorized_access'
  | 'security.rate_limit_exceeded'
  | 'security.suspicious_activity'
  | 'security.api_key_used'
  // System events
  | 'system.error'
  | 'system.maintenance_start'
  | 'system.maintenance_end'
  // H1: emitted by the daily verify-hash-chain cron when
  // verify_audit_chain() returns any broken rows. Severity=critical so
  // any log forwarder pages on it; also fed back into the chain so the
  // tampering attempt itself leaves a forensic breadcrumb.
  | 'system.audit_chain_break';

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

    // F094: cap metadata at 8KB. The DB has a CHECK as a safety net, but
    // returning a useful message here is friendlier than surfacing a raw
    // 23514 to a service caller. Truncating silently would lose data the
    // caller wanted persisted, so we hard-fail.
    const metadataJson = metadata ? JSON.stringify(metadata) : null;
    if (metadataJson && Buffer.byteLength(metadataJson, 'utf8') > MAX_METADATA_BYTES) {
      throw new Error(`audit log metadata exceeds ${MAX_METADATA_BYTES} bytes`);
    }

    const values = [
      userId || null,
      userEmail || null,
      action,
      severity,
      resourceType || null,
      resourceId || null,
      description || null,
      metadataJson,
      ipAddress || null,
      userAgent || null,
      endpoint || null,
      httpMethod || null,
      success,
      errorMessage || null,
    ];

    // Retry on transient failure so a fire-and-forget audit call from
    // auth / registration doesn't silently drop the trail when Postgres
    // is briefly unreachable.
    //
    // 4.9: tighten the retry budget. The previous shape ran 3 attempts
    // with 50/100/200ms backoff = up to 350ms blocking the request
    // path. Under a sustained PG flap that holds an HTTP request open
    // for 350ms PER mutation, including login / refresh / item-create
    // — high-traffic endpoints stack to the pool cap quickly. Drop to
    // 2 attempts with 30ms backoff (worst case ~30ms added latency on
    // a single retry) and rely on the request handler itself to either
    // surface or swallow the second failure. A proper async-queue
    // backed audit pipe is bigger work and is parked.
    let lastErr: unknown;
    const maxAttempts = 2;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const result = await pool.query<AuditLogEntry>(
          `INSERT INTO audit_logs (
            user_id, user_email, action, severity,
            resource_type, resource_id, description, metadata,
            ip_address, user_agent, endpoint, http_method,
            success, error_message
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
          RETURNING *`,
          values,
        );
        return result.rows[0];
      } catch (err) {
        lastErr = err;
        if (attempt + 1 < maxAttempts) {
          await new Promise((r) => setTimeout(r, 30));
        }
      }
    }
    throw lastErr;
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
   * Create audit log inside an existing transaction. Audit Ch02-F036:
   * `documents.upload` writes the audit row with the same client that wrote
   * the document rows so a rollback also rolls back the audit. No retries
   * here — caller's transaction owns the failure path.
   */
  static async logFromRequestWithClient(
    client: PoolClient,
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
    } = {},
  ): Promise<AuditLogEntry> {
    const user = (req as any).user;
    const result = await client.query<AuditLogEntry>(
      `INSERT INTO audit_logs (
        user_id, user_email, action, severity,
        resource_type, resource_id, description, metadata,
        ip_address, user_agent, endpoint, http_method,
        success, error_message
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *`,
      [
        user?.id ?? null,
        user?.email ?? null,
        action,
        options.severity ?? 'info',
        options.resourceType ?? null,
        options.resourceId ?? null,
        options.description ?? null,
        options.metadata ? JSON.stringify(options.metadata) : null,
        this.getIpAddress(req),
        req.get('user-agent') ?? null,
        req.path,
        req.method,
        options.success ?? true,
        options.errorMessage ?? null,
      ],
    );
    return result.rows[0];
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

    // F092: deny deep OFFSET reads. Page through with sensible windows or
    // use a cursor (createdAt + id) — not implemented here yet, but this
    // guard means a misbehaving client can't lock a table scan.
    if (offset > MAX_AUDIT_OFFSET) {
      throw new Error(`audit log offset exceeds max allowed (${MAX_AUDIT_OFFSET})`);
    }

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
   * F095: verify the audit hash chain installed by migration 065. Returns
   * the array of broken rows (created_at + id). Empty array = chain intact.
   * Designed for an admin-only diagnostic endpoint or a periodic audit job.
   */
  static async verifyHashChain(): Promise<Array<{ broken_at: Date; broken_id: string }>> {
    const result = await pool.query<{ broken_at: Date; broken_id: string }>(
      `SELECT broken_at, broken_id FROM verify_audit_chain()`,
    );
    return result.rows;
  }

  /**
   * F091: extract the client IP from the request, but only honor
   * X-Forwarded-For up to `TRUST_PROXY_HOPS` entries. Anything past that
   * count is attacker-controlled (a bare client can claim arbitrary XFF
   * values). The implementation walks the XFF list from right to left,
   * dropping `TRUST_PROXY_HOPS` proxies, and returns whatever's left — or
   * the socket address if XFF is absent / fully consumed.
   */
  private static getIpAddress(req: Request): string {
    return resolveIpAddress(req);
  }
}
