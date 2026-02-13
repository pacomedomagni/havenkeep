"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuditService = void 0;
const db_1 = require("../db");
class AuditService {
    /**
     * Create an audit log entry
     */
    static async log(params) {
        const { userId, userEmail, action, severity = 'info', resourceType, resourceId, description, metadata, ipAddress, userAgent, endpoint, httpMethod, success = true, errorMessage, } = params;
        const result = await db_1.pool.query(`INSERT INTO audit_logs (
        user_id, user_email, action, severity,
        resource_type, resource_id, description, metadata,
        ip_address, user_agent, endpoint, http_method,
        success, error_message
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *`, [
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
        ]);
        return result.rows[0];
    }
    /**
     * Create audit log from Express request
     */
    static async logFromRequest(req, action, options = {}) {
        const user = req.user;
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
    static async logAuth(params) {
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
    static async logSecurity(params) {
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
    static async logResourceChange(params) {
        const metadata = {};
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
    static async query(filters = {}) {
        const { userId, action, severity, resourceType, resourceId, startDate, endDate, success, limit = 100, offset = 0, } = filters;
        const conditions = [];
        const params = [];
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
        // Get total count
        const countResult = await db_1.pool.query(`SELECT COUNT(*) as count FROM audit_logs ${whereClause}`, params);
        const total = parseInt(countResult.rows[0].count, 10);
        // Get paginated results
        const logsResult = await db_1.pool.query(`SELECT * FROM audit_logs
       ${whereClause}
       ORDER BY created_at DESC
       LIMIT $${paramIndex++} OFFSET $${paramIndex++}`, [...params, limit, offset]);
        return {
            logs: logsResult.rows,
            total,
        };
    }
    /**
     * Get audit logs for a specific user
     */
    static async getUserLogs(userId, limit = 50, offset = 0) {
        return this.query({ userId, limit, offset });
    }
    /**
     * Get audit logs for a specific resource
     */
    static async getResourceLogs(resourceType, resourceId, limit = 50, offset = 0) {
        return this.query({ resourceType, resourceId, limit, offset });
    }
    /**
     * Get recent security events
     */
    static async getRecentSecurityEvents(limit = 100) {
        const result = await db_1.pool.query(`SELECT * FROM recent_security_events
       ORDER BY created_at DESC
       LIMIT $1`, [limit]);
        return result.rows;
    }
    /**
     * Get user activity summary
     */
    static async getUserActivitySummary(userId) {
        if (userId) {
            const result = await db_1.pool.query(`SELECT * FROM user_activity_summary WHERE user_id = $1`, [userId]);
            return result.rows;
        }
        const result = await db_1.pool.query(`SELECT * FROM user_activity_summary ORDER BY last_activity DESC NULLS LAST`);
        return result.rows;
    }
    /**
     * Clean up old audit logs (based on retention policy)
     */
    static async cleanup() {
        await db_1.pool.query('SELECT cleanup_old_audit_logs()');
    }
    /**
     * Get statistics about audit logs
     */
    static async getStats(startDate, endDate) {
        const conditions = [];
        const params = [];
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
        const result = await db_1.pool.query(`SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE severity = 'info') as severity_info,
        COUNT(*) FILTER (WHERE severity = 'warning') as severity_warning,
        COUNT(*) FILTER (WHERE severity = 'error') as severity_error,
        COUNT(*) FILTER (WHERE severity = 'critical') as severity_critical,
        COUNT(*) FILTER (WHERE success = FALSE) as failed_actions,
        jsonb_object_agg(action, action_count) as actions_breakdown
       FROM (
         SELECT
           action,
           COUNT(*) as action_count
         FROM audit_logs
         ${whereClause}
         GROUP BY action
       ) action_counts,
       audit_logs
       ${whereClause}`, params);
        const row = result.rows[0];
        return {
            total: parseInt(row.total, 10),
            by_severity: {
                info: parseInt(row.severity_info, 10),
                warning: parseInt(row.severity_warning, 10),
                error: parseInt(row.severity_error, 10),
                critical: parseInt(row.severity_critical, 10),
            },
            by_action: row.actions_breakdown || {},
            failed_actions: parseInt(row.failed_actions, 10),
        };
    }
    /**
     * Helper: Extract IP address from request
     */
    static getIpAddress(req) {
        return (req.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
            req.headers['x-real-ip'] ||
            req.socket.remoteAddress ||
            'unknown');
    }
}
exports.AuditService = AuditService;
//# sourceMappingURL=audit.service.js.map