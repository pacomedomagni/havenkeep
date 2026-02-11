# Audit System Quick Reference

Quick reference for using the HavenKeep audit system.

## Installation

```bash
# Run migration
./scripts/run-audit-migration.sh
```

## Import

```typescript
import { AuditService } from '../services/audit.service';
import { auditLog, auditAuth } from '../middleware/audit';
```

## Common Patterns

### 1. Log Authentication Events

```typescript
// Success
await AuditService.logAuth({
  action: 'auth.login',
  userId: user.id,
  email: user.email,
  ipAddress: req.ip,
  userAgent: req.get('user-agent'),
  success: true,
});

// Failure
await AuditService.logAuth({
  action: 'auth.login',
  email: req.body.email,
  ipAddress: req.ip,
  userAgent: req.get('user-agent'),
  success: false,
  errorMessage: 'Invalid credentials',
});
```

### 2. Log Resource Changes

```typescript
// Create
await AuditService.logFromRequest(req, 'item.create', {
  resourceType: 'item',
  resourceId: item.id,
  description: `Created item: ${item.name}`,
});

// Update
await AuditService.logFromRequest(req, 'item.update', {
  resourceType: 'item',
  resourceId: item.id,
  description: `Updated item: ${item.name}`,
  metadata: { updated_fields: Object.keys(updates) },
});

// Delete
await AuditService.logFromRequest(req, 'item.delete', {
  resourceType: 'item',
  resourceId: item.id,
  description: `Deleted item: ${item.name}`,
});
```

### 3. Log with Old/New Values

```typescript
await AuditService.logResourceChange({
  action: 'user.update',
  userId: user.id,
  userEmail: user.email,
  resourceType: 'user',
  resourceId: user.id,
  description: 'Updated user profile',
  oldValue: { name: 'John Doe', email: 'old@example.com' },
  newValue: { name: 'Jane Doe', email: 'new@example.com' },
});
```

### 4. Log Security Events

```typescript
await AuditService.logSecurity({
  action: 'security.unauthorized_access',
  userId: user?.id,
  ipAddress: req.ip,
  userAgent: req.get('user-agent'),
  description: 'Attempted to access admin-only endpoint',
  severity: 'warning',
});
```

### 5. Use Middleware (Automatic)

```typescript
router.post('/items',
  authenticate,
  auditLog('item.create', {
    resourceType: 'item',
    getResourceId: (req) => req.body.id,
  }),
  handler
);

router.post('/login',
  auditAuth('auth.login'),
  handler
);
```

## Query Examples

### Get User's Logs

```typescript
const { logs, total } = await AuditService.getUserLogs(userId, 50, 0);
```

### Get Resource History

```typescript
const { logs, total } = await AuditService.getResourceLogs('item', itemId);
```

### Find Failed Login Attempts

```typescript
const result = await AuditService.query({
  action: 'auth.login',
  success: false,
  startDate: new Date('2026-02-01'),
  limit: 100,
});
```

### Get Recent Security Events

```typescript
const events = await AuditService.getRecentSecurityEvents(100);
```

### Get Statistics

```typescript
const stats = await AuditService.getStats(
  new Date('2026-01-01'),
  new Date('2026-02-01')
);
```

## API Endpoints

```bash
# Get logs (with filters)
GET /api/v1/audit/logs?action=auth.login&limit=50

# Get current user's logs
GET /api/v1/audit/logs/me

# Get resource logs
GET /api/v1/audit/logs/resource/item/123e4567-e89b-12d3-a456-426614174000

# Get security events (admin)
GET /api/v1/audit/security

# Get statistics (admin)
GET /api/v1/audit/stats?startDate=2026-01-01&endDate=2026-02-01

# Get activity summary (admin)
GET /api/v1/audit/activity-summary

# Run cleanup (admin)
POST /api/v1/audit/cleanup
```

## Maintenance

```bash
# Run cleanup manually
./scripts/run-audit-cleanup.sh

# Schedule via cron (daily at 2 AM)
0 2 * * * /path/to/havenkeep/scripts/run-audit-cleanup.sh
```

## Action Types

### Authentication
- `auth.login`
- `auth.logout`
- `auth.register`
- `auth.password_reset_request`
- `auth.password_reset_complete`
- `auth.email_verify`
- `auth.token_refresh`
- `auth.oauth_login`

### Items
- `item.create`
- `item.update`
- `item.delete`
- `item.archive`
- `item.unarchive`

### Users
- `user.create`
- `user.update`
- `user.delete`
- `user.plan_upgrade`
- `user.plan_downgrade`

### Security
- `security.unauthorized_access`
- `security.rate_limit_exceeded`
- `security.suspicious_activity`
- `security.api_key_used`

### Admin
- `admin.user_impersonate`
- `admin.user_delete`
- `admin.partner_approve`
- `admin.partner_reject`

## Severity Levels

- `info` - Normal operations (default)
- `warning` - Attention required (failed logins, rate limits)
- `error` - Errors needing investigation
- `critical` - Critical security/system issues

## Best Practices

✅ DO:
- Log all auth events (success AND failure)
- Log CRUD operations on important resources
- Log admin actions
- Log security events
- Use appropriate severity levels

❌ DON'T:
- Log passwords or tokens
- Log credit card numbers
- Log PII without sanitization
- Log high-frequency operations
- Block the request waiting for audit log

## Troubleshooting

### Check if audit system is working

```sql
SELECT COUNT(*) FROM audit_logs;
SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 10;
```

### Check table size

```sql
SELECT
  pg_size_pretty(pg_total_relation_size('audit_logs')) as size,
  COUNT(*) as rows
FROM audit_logs;
```

### Find errors

```sql
SELECT *
FROM audit_logs
WHERE success = false
ORDER BY created_at DESC
LIMIT 20;
```
