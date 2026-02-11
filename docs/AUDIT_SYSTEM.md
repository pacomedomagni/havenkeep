# HavenKeep Audit System

Complete end-to-end audit logging system for tracking all user actions, authentication events, security events, and system operations.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [API Endpoints](#api-endpoints)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)
- [Maintenance](#maintenance)

## Overview

The audit system provides comprehensive logging of all important actions in HavenKeep:

- **Authentication Events**: Login, logout, registration, password resets, OAuth
- **Resource Changes**: Item CRUD, home CRUD, document operations
- **Security Events**: Failed login attempts, rate limit violations, suspicious activity
- **Admin Actions**: User management, partner approvals, settings changes
- **System Events**: Errors, maintenance windows

### Key Features

- ✅ Automatic logging via middleware
- ✅ Manual logging via service methods
- ✅ User activity tracking and summaries
- ✅ Security event monitoring
- ✅ Configurable retention policies
- ✅ IP address and user agent tracking
- ✅ Structured metadata in JSONB format
- ✅ Efficient querying with indexes

## Architecture

### Components

1. **Database Table**: `audit_logs` with comprehensive columns and indexes
2. **Service Layer**: `AuditService` for all logging operations
3. **Middleware**: `auditLog()`, `auditAuth()` for automatic logging
4. **API Routes**: `/api/v1/audit/*` for querying logs
5. **Views**: Pre-built views for common queries

### Data Flow

```
Action → Middleware/Manual Call → AuditService → Database → API Query
```

## Database Schema

### audit_logs Table

```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,

  -- Who
  user_id UUID,
  user_email VARCHAR(255),

  -- What
  action audit_action NOT NULL,
  severity audit_severity DEFAULT 'info',

  -- Where
  resource_type VARCHAR(50),
  resource_id UUID,

  -- Details
  description TEXT,
  metadata JSONB,

  -- Context
  ip_address INET,
  user_agent TEXT,
  endpoint VARCHAR(255),
  http_method VARCHAR(10),

  -- Result
  success BOOLEAN DEFAULT TRUE,
  error_message TEXT,

  -- When
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Audit Actions

Actions are categorized by domain:

- **auth.***: `login`, `logout`, `register`, `password_reset_request`, `password_reset_complete`, `email_verify`, `token_refresh`, `oauth_login`
- **user.***: `create`, `update`, `delete`, `plan_upgrade`, `plan_downgrade`
- **item.***: `create`, `update`, `delete`, `archive`, `unarchive`, `transfer`
- **home.***: `create`, `update`, `delete`
- **document.***: `upload`, `delete`, `view`
- **admin.***: `user_impersonate`, `user_delete`, `partner_approve`, `partner_reject`, `settings_change`
- **partner.***: `gift_create`, `gift_update`, `gift_activate`, `warranty_create`, `warranty_update`
- **security.***: `unauthorized_access`, `rate_limit_exceeded`, `suspicious_activity`, `api_key_used`
- **system.***: `error`, `maintenance_start`, `maintenance_end`

### Severity Levels

- `info`: Normal operations
- `warning`: Attention required (failed logins, rate limits)
- `error`: Errors that need investigation
- `critical`: Critical security or system issues

### Indexes

```sql
-- Primary indexes
idx_audit_logs_user_id
idx_audit_logs_created_at
idx_audit_logs_action
idx_audit_logs_severity
idx_audit_logs_resource

-- Composite indexes
idx_audit_logs_user_created (user_id, created_at DESC)
idx_audit_logs_admin_view (severity, created_at DESC)

-- JSONB index
idx_audit_logs_metadata GIN (metadata)
```

## API Endpoints

All audit endpoints require authentication. Non-admin users can only see their own logs.

### Query Audit Logs

```http
GET /api/v1/audit/logs
```

**Query Parameters:**
- `userId` (string, admin only): Filter by user ID
- `action` (string): Filter by action type
- `severity` (string): Filter by severity
- `resourceType` (string): Filter by resource type
- `resourceId` (string): Filter by resource ID
- `startDate` (ISO date): Filter from date
- `endDate` (ISO date): Filter to date
- `success` (boolean): Filter by success status
- `limit` (number, max 100): Results per page
- `offset` (number): Pagination offset

**Response:**
```json
{
  "logs": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "user_email": "user@example.com",
      "action": "auth.login",
      "severity": "info",
      "resource_type": null,
      "resource_id": null,
      "description": null,
      "metadata": {},
      "ip_address": "192.168.1.1",
      "user_agent": "Mozilla/5.0...",
      "endpoint": "/api/v1/auth/login",
      "http_method": "POST",
      "success": true,
      "error_message": null,
      "created_at": "2026-02-11T10:00:00Z"
    }
  ],
  "pagination": {
    "total": 150,
    "limit": 50,
    "offset": 0,
    "hasMore": true
  }
}
```

### Get Current User's Logs

```http
GET /api/v1/audit/logs/me
```

**Query Parameters:**
- `limit` (number, max 100)
- `offset` (number)

### Get Resource Logs

```http
GET /api/v1/audit/logs/resource/:resourceType/:resourceId
```

Get all audit logs for a specific resource (e.g., item, home).

### Get Security Events (Admin Only)

```http
GET /api/v1/audit/security
```

**Query Parameters:**
- `limit` (number, max 500)

Returns recent security events from the last 30 days.

### Get Audit Statistics (Admin Only)

```http
GET /api/v1/audit/stats
```

**Query Parameters:**
- `startDate` (ISO date)
- `endDate` (ISO date)

**Response:**
```json
{
  "stats": {
    "total": 5000,
    "by_severity": {
      "info": 4500,
      "warning": 400,
      "error": 90,
      "critical": 10
    },
    "by_action": {
      "auth.login": 1200,
      "item.create": 800,
      "item.update": 500
    },
    "failed_actions": 150
  }
}
```

### Get User Activity Summary (Admin Only)

```http
GET /api/v1/audit/activity-summary
```

**Query Parameters:**
- `userId` (string, optional): Specific user ID

Returns activity summary including total actions, recent activity, and failed actions.

### Trigger Cleanup (Admin Only)

```http
POST /api/v1/audit/cleanup
```

Manually triggers the retention policy cleanup (removes logs older than 1 year for `info`, 3 years for `warning`/`error`/`critical`).

## Usage Examples

### Automatic Logging with Middleware

```typescript
import { auditLog } from '../middleware/audit';

// Basic usage
router.post('/items',
  authenticate,
  auditLog('item.create', {
    resourceType: 'item',
    getResourceId: (req) => req.body.id,
  }),
  async (req, res) => {
    // Your handler
  }
);
```

### Manual Logging

```typescript
import { AuditService } from '../services/audit.service';

// Log from request
await AuditService.logFromRequest(req, 'item.update', {
  resourceType: 'item',
  resourceId: item.id,
  description: `Updated item: ${item.name}`,
  metadata: {
    updated_fields: ['name', 'price'],
  },
});

// Log authentication event
await AuditService.logAuth({
  action: 'auth.login',
  userId: user.id,
  email: user.email,
  ipAddress: req.ip,
  userAgent: req.get('user-agent'),
  success: true,
});

// Log security event
await AuditService.logSecurity({
  action: 'security.unauthorized_access',
  userId: user?.id,
  ipAddress: req.ip,
  description: 'Attempted to access admin endpoint',
  severity: 'warning',
});

// Log resource change with old/new values
await AuditService.logResourceChange({
  action: 'item.update',
  userId: user.id,
  resourceType: 'item',
  resourceId: itemId,
  description: 'Updated item name',
  oldValue: { name: 'Old Name' },
  newValue: { name: 'New Name' },
});
```

### Querying Logs

```typescript
// Get user's logs
const { logs, total } = await AuditService.getUserLogs(userId, 50, 0);

// Get resource logs
const { logs, total } = await AuditService.getResourceLogs('item', itemId);

// Query with filters
const result = await AuditService.query({
  action: 'auth.login',
  severity: 'warning',
  startDate: new Date('2026-01-01'),
  success: false,
  limit: 100,
});

// Get security events
const events = await AuditService.getRecentSecurityEvents(100);

// Get statistics
const stats = await AuditService.getStats(
  new Date('2026-01-01'),
  new Date('2026-02-01')
);
```

## Best Practices

### What to Log

✅ **DO log:**
- All authentication events (success and failure)
- Resource creation, updates, and deletions
- Administrative actions
- Security-related events
- Permission changes
- Payment and billing events
- API key usage
- Data exports

❌ **DON'T log:**
- Passwords or tokens (even hashed)
- Credit card numbers
- SSNs or other PII
- Health information
- High-frequency read operations (unless suspicious)

### Sensitive Data

Always sanitize sensitive data before logging:

```typescript
const sanitizedBody = { ...req.body };
delete sanitizedBody.password;
delete sanitizedBody.password_hash;
delete sanitizedBody.token;
delete sanitizedBody.creditCard;

await AuditService.log({
  // ...
  metadata: { request_body: sanitizedBody },
});
```

### Performance Considerations

1. **Asynchronous Logging**: Never block the main request flow
   ```typescript
   // Don't await in critical path
   AuditService.logFromRequest(req, action, options).catch(err =>
     console.error('Audit log failed:', err)
   );
   ```

2. **Use Indexes**: Always filter by indexed columns
3. **Limit Results**: Use pagination for large result sets
4. **Metadata**: Keep metadata under 10KB

### Retention Policy

- **Info logs**: 1 year
- **Warning/Error/Critical logs**: 3 years

Run cleanup manually or via cron:

```bash
# Manually
./scripts/run-audit-cleanup.sh

# Cron (daily at 2 AM)
0 2 * * * /path/to/havenkeep/scripts/run-audit-cleanup.sh
```

## Maintenance

### Running the Migration

```bash
# Initial setup
./scripts/run-audit-migration.sh

# Or manually
psql $DATABASE_URL -f apps/api/src/db/migrations/004_audit_system.sql
```

### Monitoring

1. **Check table size:**
   ```sql
   SELECT
     pg_size_pretty(pg_total_relation_size('audit_logs')) as total_size,
     (SELECT COUNT(*) FROM audit_logs) as row_count;
   ```

2. **Monitor growth rate:**
   ```sql
   SELECT
     DATE_TRUNC('day', created_at) as day,
     COUNT(*) as logs_created
   FROM audit_logs
   WHERE created_at > NOW() - INTERVAL '30 days'
   GROUP BY day
   ORDER BY day DESC;
   ```

3. **Check for errors:**
   ```sql
   SELECT COUNT(*)
   FROM audit_logs
   WHERE severity IN ('error', 'critical')
     AND created_at > NOW() - INTERVAL '24 hours';
   ```

### Troubleshooting

**Issue: Too many logs**
- Review what's being logged
- Increase retention policy cleanup frequency
- Consider archiving to cold storage

**Issue: Slow queries**
- Check index usage: `EXPLAIN ANALYZE SELECT ...`
- Add composite indexes for common queries
- Partition table by date if >10M rows

**Issue: Missing logs**
- Check for exceptions in application logs
- Verify middleware is applied
- Test `AuditService` methods directly

## Security Considerations

1. **Access Control**: Only admins can see all logs, users see their own
2. **Data Protection**: No sensitive data in logs
3. **Tamper Protection**: Audit logs are append-only (no UPDATE capability in API)
4. **Log Integrity**: Consider write-once storage for critical logs
5. **Encryption**: Enable PostgreSQL encryption at rest
6. **Network Security**: Secure database connections with SSL/TLS

## Integration with Mobile App

Mobile app should not query audit logs directly. All audit logging happens server-side automatically when API endpoints are called.

For user-facing "Activity" screens, create a separate `user_activity` table with denormalized data optimized for mobile.

## Future Enhancements

- [ ] Export logs to external SIEM (Splunk, Elasticsearch)
- [ ] Real-time alerting for critical events
- [ ] Anomaly detection using ML
- [ ] Automated compliance reporting (GDPR, SOC 2)
- [ ] Log encryption with customer-managed keys
- [ ] Blockchain-based tamper-proof audit trail
