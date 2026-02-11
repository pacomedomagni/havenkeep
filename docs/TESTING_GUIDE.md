# 🧪 HavenKeep Testing Guide

## Overview

Comprehensive testing guide for all new features in the MVP Option A release.

---

## 1. API Testing

### A. Warranty Claims API

#### Create Warranty Claim

```bash
POST /api/v1/warranty-claims
Authorization: Bearer <token>
Content-Type: application/json

{
  "item_id": "uuid-of-item",
  "claim_date": "2026-02-10",
  "issue_description": "Refrigerator stopped cooling",
  "repair_description": "Replaced compressor",
  "repair_cost": 450.00,
  "amount_saved": 450.00,
  "out_of_pocket": 0,
  "status": "completed",
  "filed_with": "Samsung Warranty",
  "claim_number": "CLM-2026-001"
}

# Expected Response: 201 Created
{
  "success": true,
  "data": {
    "id": "claim-uuid",
    "item_id": "uuid-of-item",
    "user_id": "user-uuid",
    "claim_date": "2026-02-10",
    "amount_saved": 450.00,
    ...
  },
  "message": "Warranty claim created successfully"
}
```

#### Get All Claims

```bash
GET /api/v1/warranty-claims?limit=10&offset=0
Authorization: Bearer <token>

# Expected Response: 200 OK
{
  "success": true,
  "data": [
    {
      "id": "claim-uuid",
      "item_name": "Samsung Refrigerator",
      "amount_saved": 450.00,
      ...
    }
  ],
  "pagination": {
    "total": 5,
    "limit": 10,
    "offset": 0,
    "has_more": false
  }
}
```

#### Get Total Savings

```bash
GET /api/v1/warranty-claims/savings
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": {
    "total_warranty_savings": 1240.00,
    "total_preventive_savings": 0,
    "total_savings": 1240.00,
    "total_claims": 3
  }
}
```

#### Get Savings Feed (Social Proof)

```bash
GET /api/v1/warranty-claims/feed?limit=20
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": [
    {
      "id": "feed-uuid",
      "user_city": "Austin",
      "user_state": "TX",
      "amount_saved": 520.00,
      "item_category": "dishwasher",
      "display_text": "Austin just saved $520 on a dishwasher repair",
      "created_at": "2026-02-10T..."
    }
  ]
}
```

### B. Stats/Analytics API

#### Get Dashboard Stats

```bash
GET /api/v1/stats/dashboard
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": {
    "total_value": 47350.00,
    "total_items": 18,
    "active_warranties": 15,
    "expiring_soon": 2,
    "expired": 1,
    "total_repair_value": 3200.00,
    "health_score": 87
  }
}
```

#### Get Health Score Breakdown

```bash
GET /api/v1/stats/health-score
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": {
    "score": 87,
    "components": [
      {
        "name": "Items Tracked",
        "points": 30,
        "max_points": 30,
        "status": "good",
        "suggestion": null
      },
      {
        "name": "Active Warranties",
        "points": 25,
        "max_points": 25,
        "status": "good"
      },
      ...
    ]
  }
}
```

#### Recalculate Health Score

```bash
POST /api/v1/stats/health-score/calculate
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": {
    "score": 87
  },
  "message": "Health score recalculated"
}
```

#### Get Items Needing Attention

```bash
GET /api/v1/stats/items-needing-attention
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": [
    {
      "id": "item-uuid",
      "name": "Coffee Maker",
      "category": "other",
      "warranty_end_date": "2026-03-15",
      "attention_reason": "expiring_soon",
      "days_until_expiry": 34
    }
  ]
}
```

#### Track Engagement

```bash
POST /api/v1/stats/track-engagement
Authorization: Bearer <token>
Content-Type: application/json

{
  "type": "app_open"
}

# Or for session end:
{
  "type": "session_end",
  "session_duration": 180
}

# Expected Response:
{
  "success": true,
  "message": "Engagement tracked"
}
```

### C. Email Scanner API

#### Initiate Email Scan

```bash
POST /api/v1/email-scanner/scan
Authorization: Bearer <token>
Content-Type: application/json

{
  "provider": "gmail",
  "access_token": "ya29.a0AfH6...",
  "date_range_start": "2024-01-01",
  "date_range_end": "2026-02-10"
}

# Expected Response: 202 Accepted
{
  "success": true,
  "data": {
    "id": "scan-uuid",
    "user_id": "user-uuid",
    "provider": "gmail",
    "status": "pending",
    "created_at": "2026-02-10T..."
  },
  "message": "Email scan initiated. This may take a few minutes."
}
```

#### Check Scan Status

```bash
GET /api/v1/email-scanner/scans/{scan_id}
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": {
    "id": "scan-uuid",
    "user_id": "user-uuid",
    "provider": "gmail",
    "status": "completed",  // or "scanning", "failed"
    "emails_scanned": 247,
    "receipts_found": 23,
    "items_imported": 18,
    "completed_at": "2026-02-10T...",
    "error_message": null
  }
}
```

#### Get Scan History

```bash
GET /api/v1/email-scanner/scans
Authorization: Bearer <token>

# Expected Response:
{
  "success": true,
  "data": [
    {
      "id": "scan-uuid",
      "provider": "gmail",
      "status": "completed",
      "items_imported": 18,
      "created_at": "2026-02-10T..."
    }
  ]
}
```

---

## 2. Database Testing

### A. Health Score Calculation

```sql
-- Test health score function
SELECT calculate_health_score('user-uuid');

-- Should return value between 0 and 100

-- Verify user_analytics updated
SELECT current_health_score, health_score_history
FROM user_analytics
WHERE user_id = 'user-uuid';
```

### B. Dashboard Stats Function

```sql
-- Test dashboard stats function
SELECT get_dashboard_stats('user-uuid');

-- Should return JSON with all stats
```

### C. Verify Data Integrity

```sql
-- Check warranty claims are properly linked
SELECT c.*, i.name
FROM warranty_claims c
JOIN items i ON i.id = c.item_id
WHERE c.user_id = 'user-uuid';

-- Check user analytics is updating
SELECT *
FROM user_analytics
WHERE user_id = 'user-uuid';

-- Verify savings feed
SELECT * FROM savings_feed
ORDER BY created_at DESC
LIMIT 10;
```

---

## 3. Integration Testing

### A. End-to-End Warranty Claim Flow

```
1. User creates item
2. Item develops issue
3. User creates warranty claim
4. Check:
   - Claim created in database
   - User analytics updated (total_warranty_savings, total_claims_filed)
   - Savings feed entry created
   - Health score recalculated
```

### B. Email Scanner Flow

```
1. User initiates Gmail scan
2. Check scan record created with status="pending"
3. Wait for background processing
4. Check:
   - Scan status changes to "scanning" then "completed"
   - Items created from receipts
   - User analytics updated (email_scans_completed, items_added_via_email)
   - Health score recalculated
```

### C. Dashboard Stats Flow

```
1. Add multiple items
2. Create warranty claims
3. Complete maintenance tasks
4. Call GET /api/v1/stats/dashboard
5. Verify all calculations are correct
```

---

## 4. Performance Testing

### A. Load Testing with Apache Bench

```bash
# Test dashboard stats endpoint
ab -n 1000 -c 10 \
  -H "Authorization: Bearer <token>" \
  https://api.havenkeep.com/api/v1/stats/dashboard

# Target:
# - Requests per second: >50
# - Mean response time: <200ms
# - 95th percentile: <500ms
```

### B. Database Query Performance

```sql
-- Check query execution times
EXPLAIN ANALYZE
SELECT get_dashboard_stats('user-uuid');

-- Should complete in <100ms

EXPLAIN ANALYZE
SELECT calculate_health_score('user-uuid');

-- Should complete in <100ms
```

### C. Email Scanner Performance

```bash
# Test with varying email counts
# Target: Process 100 emails in <60 seconds
```

---

## 5. Security Testing

### A. Authentication

```bash
# Test without token - should return 401
curl https://api.havenkeep.com/api/v1/warranty-claims

# Test with invalid token - should return 401
curl -H "Authorization: Bearer invalid-token" \
  https://api.havenkeep.com/api/v1/warranty-claims

# Test with valid token - should return 200
curl -H "Authorization: Bearer valid-token" \
  https://api.havenkeep.com/api/v1/warranty-claims
```

### B. Authorization

```bash
# Test accessing another user's claim - should return 404 or 403
curl -H "Authorization: Bearer user1-token" \
  https://api.havenkeep.com/api/v1/warranty-claims/user2-claim-id
```

### C. Input Validation

```bash
# Test invalid data types
POST /api/v1/warranty-claims
{
  "item_id": "not-a-uuid",  # Should return 400
  "repair_cost": "not-a-number",  # Should return 400
  "amount_saved": -100  # Should return 400
}

# Test SQL injection attempts
POST /api/v1/warranty-claims
{
  "item_id": "'; DROP TABLE items; --",  # Should be safely handled
  ...
}
```

### D. Rate Limiting

```bash
# Send 101 requests in 1 minute - 101st should return 429
for i in {1..101}; do
  curl https://api.havenkeep.com/api/v1/stats/dashboard \
    -H "Authorization: Bearer <token>"
done
```

---

## 6. Error Handling Testing

### A. Database Errors

```sql
-- Simulate database down
pg_ctl stop

-- Test API responses
# Should return 500 with generic error message (not exposing database details)
```

### B. External API Failures

```typescript
// Mock OpenAI API failure
// Email scanner should:
// - Mark scan as "failed"
// - Log error message
// - Not crash the application
```

### C. Invalid OAuth Tokens

```bash
# Test with expired Google token
POST /api/v1/email-scanner/scan
{
  "provider": "gmail",
  "access_token": "expired-token"
}

# Should return meaningful error
```

---

## 7. Mobile App Testing

### A. Warranty Claims UI

```
Test Cases:
1. Create new claim
   - Fill all fields
   - Submit
   - Verify shows in list immediately (optimistic UI)
   - Verify syncs to server

2. View claim details
   - Shows item info
   - Shows financial impact
   - Shows savings calculation

3. Edit claim
   - Update amount saved
   - Verify savings recalculated

4. Delete claim
   - Confirm dialog appears
   - Verify removed from list
   - Verify savings updated
```

### B. Dashboard UI

```
Test Cases:
1. Dashboard loads with stats
   - Total value
   - Health score (with animation)
   - Items needing attention
   - Quick actions

2. Health score tap
   - Shows breakdown
   - Shows improvement suggestions
   - Shows comparison to neighbors

3. Items needing attention
   - Shows sorted by urgency
   - Tap item → goes to detail
   - Shows days until expiry

4. Quick actions
   - Add item
   - Email scan
   - File claim
   - Extend warranty
```

### C. Email Scanner UI

```
Test Cases:
1. OAuth flow
   - Tap "Connect Gmail"
   - Opens OAuth screen
   - Authorize
   - Returns to app
   - Shows scanning progress

2. Scanning progress
   - Shows loading indicator
   - Shows "Scanning X emails..."
   - Shows "Found X receipts"
   - Completion message

3. Review imported items
   - Shows list of found items
   - Select/deselect items
   - Edit details before importing
   - Import selected items

4. Error handling
   - OAuth cancelled
   - Network error during scan
   - No receipts found
```

---

## 8. Regression Testing

### A. Existing Features Still Work

```
1. User authentication
   - Sign up
   - Login
   - Logout
   - Password reset

2. Items CRUD
   - Create item
   - View items list
   - Update item
   - Delete item
   - Archive item

3. Documents
   - Upload receipt
   - View document
   - Delete document

4. Homes
   - Create home
   - Switch homes
   - Update home

5. Premium subscription
   - Upgrade to premium
   - Stripe payment
   - Features unlock
```

---

## 9. Test Automation

### A. API Test Suite (Jest)

```typescript
// apps/api/tests/warranty-claims.test.ts
import { describe, it, expect } from '@jest/globals';
import request from 'supertest';
import app from '../src/index';

describe('Warranty Claims API', () => {
  let authToken: string;
  let itemId: string;

  beforeAll(async () => {
    // Setup test user and get token
    authToken = await getTestToken();
    itemId = await createTestItem(authToken);
  });

  describe('POST /api/v1/warranty-claims', () => {
    it('should create a new warranty claim', async () => {
      const response = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          item_id: itemId,
          repair_cost: 450,
          amount_saved: 450,
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.amount_saved).toBe(450);
    });

    it('should return 400 for invalid data', async () => {
      const response = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          item_id: 'not-a-uuid',
          repair_cost: -100,
        });

      expect(response.status).toBe(400);
    });

    it('should return 401 without auth token', async () => {
      const response = await request(app)
        .post('/api/v1/warranty-claims')
        .send({
          item_id: itemId,
          repair_cost: 450,
          amount_saved: 450,
        });

      expect(response.status).toBe(401);
    });
  });

  describe('GET /api/v1/warranty-claims', () => {
    it('should return user claims', async () => {
      const response = await request(app)
        .get('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(Array.isArray(response.body.data)).toBe(true);
    });
  });

  // ... more tests
});
```

### B. Run Tests

```bash
# Run all tests
npm test

# Run with coverage
npm test -- --coverage

# Target: >80% code coverage
```

---

## 10. User Acceptance Testing (UAT)

### Test Scenarios

#### Scenario 1: New User Onboarding
```
As a new homeowner:
1. Sign up for account
2. Create first home
3. Connect Gmail
4. Scan emails → 15 items imported
5. View dashboard → See total value $45,000
6. Check health score → 65/100
7. Add missing receipts → Score increases to 75
8. File first warranty claim → See savings tracked
9. Upgrade to premium → Unlock all features
```

#### Scenario 2: Existing User Adding Claims
```
As an existing user:
1. My fridge breaks
2. Tap "File Claim" from dashboard
3. Select fridge from items
4. Fill claim details: $520 repair, $520 saved
5. Submit
6. See updated savings: $520
7. View savings feed → My city shows $520 saved
8. Check health score → Maintained
```

#### Scenario 3: Email Scanner Power User
```
As a power user:
1. Connect Gmail
2. Scan last 2 years
3. Review 47 found receipts
4. Deselect 12 non-appliances
5. Edit 5 items with wrong categories
6. Import 35 items
7. Dashboard updates: $67,000 protected
8. Health score jumps to 92/100
9. Share screenshot on social media
```

---

## Success Criteria

### API Performance
- ✅ All endpoints respond in <500ms (p95)
- ✅ Error rate <1%
- ✅ Uptime >99.9%

### Functionality
- ✅ All test cases pass
- ✅ No critical bugs
- ✅ Data integrity maintained

### User Experience
- ✅ Email scanner completes in <2 minutes
- ✅ Dashboard loads in <1 second
- ✅ Health score animates smoothly
- ✅ Mobile app doesn't crash

### Business Metrics
- ✅ Email scan completion rate >70%
- ✅ Warranty claim tracking adoption >40%
- ✅ Health score engagement >50% weekly
- ✅ Premium conversion increase >5%

---

**Testing Status:** Ready for QA
**Last Updated:** 2026-02-11
