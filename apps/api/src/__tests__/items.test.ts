import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, createTestHome, createTestItem } from './helpers';

const app = getTestApp();

/** Helper to build a valid item payload for POST /api/v1/items */
function buildItemPayload(homeId: string, overrides: Record<string, any> = {}) {
  return {
    homeId,
    name: 'Test Item',
    category: 'other',
    room: 'living_room',
    purchaseDate: '2024-01-15',
    warrantyMonths: 12,
    price: 199.99,
    ...overrides,
  };
}

describe('Items API', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  // ──────────────────────────────── Create ────────────────────────────────

  describe('POST /api/v1/items', () => {
    it('should create a new item', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      const res = await request(app)
        .post('/api/v1/items')
        .set('Authorization', `Bearer ${token}`)
        .send(buildItemPayload(home.id, { name: 'Smart TV', category: 'tv', room: 'living_room' }));

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.name).toBe('Smart TV');
      expect(res.body.data.category).toBe('tv');
      expect(res.body.data.home_id).toBe(home.id);
      expect(res.body.data.id).toBeDefined();
      expect(res.body.data.warranty_end_date).toBeDefined();
    });

    it('should reject creating an item without a homeId', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .post('/api/v1/items')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Orphan Item',
          purchaseDate: '2024-01-15',
          warrantyMonths: 12,
        });

      expect(res.status).toBe(400);
    });

    it('should reject creating an item for a home that does not belong to the user', async () => {
      const userA = await createTestUser({ email: 'itema@test.com' });
      const userB = await createTestUser({ email: 'itemb@test.com' });
      const homeB = await createTestHome(userB.user.id);

      const res = await request(app)
        .post('/api/v1/items')
        .set('Authorization', `Bearer ${userA.token}`)
        .send(buildItemPayload(homeB.id, { name: 'Sneaky Item' }));

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('Home not found');
    });

    it('should reject unauthenticated requests', async () => {
      const res = await request(app)
        .post('/api/v1/items')
        .send({ name: 'No Auth Item' });

      expect(res.status).toBe(401);
    });
  });

  // ──────────────────────────────── List with pagination ────────────────────────────────

  describe('GET /api/v1/items', () => {
    it('should list items for the authenticated user with pagination metadata', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      // Create 3 items
      for (let i = 1; i <= 3; i++) {
        await createTestItem(user.id, home.id, { name: `Item ${i}` });
      }

      const res = await request(app)
        .get('/api/v1/items?page=1&limit=2')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.length).toBe(2);
      expect(res.body.meta.pagination).toBeDefined();
      expect(res.body.meta.pagination.total).toBe(3);
      expect(res.body.meta.pagination.total_pages).toBe(2);
      expect(res.body.meta.pagination.page).toBe(1);
      expect(res.body.meta.pagination.limit).toBe(2);
    });

    it('should return the second page of items', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      for (let i = 1; i <= 3; i++) {
        await createTestItem(user.id, home.id, { name: `Item ${i}` });
      }

      const res = await request(app)
        .get('/api/v1/items?page=2&limit=2')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.meta.pagination.page).toBe(2);
    });

    it('should filter items by homeId', async () => {
      const { user, token } = await createTestUser();
      const homeA = await createTestHome(user.id, { name: 'Home A' });
      const homeB = await createTestHome(user.id, { name: 'Home B' });

      await createTestItem(user.id, homeA.id, { name: 'Item in A' });
      await createTestItem(user.id, homeB.id, { name: 'Item in B' });

      const res = await request(app)
        .get(`/api/v1/items?homeId=${homeA.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.data[0].name).toBe('Item in A');
    });

    it('should filter items by archived status', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      const item = await createTestItem(user.id, home.id, { name: 'Active Item' });
      const archivedItem = await createTestItem(user.id, home.id, { name: 'Archived Item' });

      // Archive one item
      await request(app)
        .put(`/api/v1/items/${archivedItem.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ isArchived: true });

      const res = await request(app)
        .get('/api/v1/items?archived=false')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.data[0].name).toBe('Active Item');
    });
  });

  // ──────────────────────────────── Get by ID ────────────────────────────────

  describe('GET /api/v1/items/:id', () => {
    it('should return a single item by ID with lifespan fields', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Toaster' });

      const res = await request(app)
        .get(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(item.id);
      expect(res.body.data.name).toBe('Toaster');
      // Lifespan fields should be computed
      expect(res.body.data).toHaveProperty('expected_lifespan_years');
      expect(res.body.data).toHaveProperty('lifespan_percentage');
    });

    it('should return 404 for a nonexistent item', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/items/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('Item not found');
    });
  });

  // ──────────────────────────────── Update ────────────────────────────────

  describe('PUT /api/v1/items/:id', () => {
    it('should update item fields', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Old Name' });

      const res = await request(app)
        .put(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ name: 'New Name', notes: 'Updated notes' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.name).toBe('New Name');
      expect(res.body.data.notes).toBe('Updated notes');
    });

    it('should return 404 when updating a nonexistent item', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .put('/api/v1/items/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${token}`)
        .send({ name: 'Ghost' });

      expect(res.status).toBe(404);
    });

    it('should reject an update with no valid fields', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);

      const res = await request(app)
        .put(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({});

      expect(res.status).toBe(400);
    });
  });

  // ──────────────────────────────── Archive / Unarchive ────────────────────────────────

  describe('Archive and unarchive', () => {
    it('should archive an item', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'To Archive' });

      const res = await request(app)
        .put(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ isArchived: true });

      expect(res.status).toBe(200);
      expect(res.body.data.is_archived).toBe(true);
      expect(res.body.data.archived_at).not.toBeNull();
    });

    it('should unarchive an item', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'To Unarchive' });

      // Archive first
      await request(app)
        .put(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ isArchived: true });

      // Unarchive
      const res = await request(app)
        .put(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ isArchived: false });

      expect(res.status).toBe(200);
      expect(res.body.data.is_archived).toBe(false);
      expect(res.body.data.archived_at).toBeNull();
    });
  });

  // ──────────────────────────────── Delete ────────────────────────────────

  describe('DELETE /api/v1/items/:id', () => {
    it('should delete an item', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Delete Me' });

      const res = await request(app)
        .delete(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.message).toBe('Item deleted successfully');

      // Verify deletion
      const getRes = await request(app)
        .get(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(getRes.status).toBe(404);
    });

    it('should return 404 when deleting a nonexistent item', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .delete('/api/v1/items/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(404);
    });
  });

  // ──────────────────────────────── Cross-user isolation ────────────────────────────────

  describe('Cross-user isolation', () => {
    it('should not allow user A to read user B items', async () => {
      const userA = await createTestUser({ email: 'isoa@test.com' });
      const userB = await createTestUser({ email: 'isob@test.com' });
      const homeB = await createTestHome(userB.user.id);
      const itemB = await createTestItem(userB.user.id, homeB.id, { name: 'Secret Item' });

      const res = await request(app)
        .get(`/api/v1/items/${itemB.id}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });

    it('should not allow user A to update user B items', async () => {
      const userA = await createTestUser({ email: 'isoa2@test.com' });
      const userB = await createTestUser({ email: 'isob2@test.com' });
      const homeB = await createTestHome(userB.user.id);
      const itemB = await createTestItem(userB.user.id, homeB.id, { name: 'Private Item' });

      const res = await request(app)
        .put(`/api/v1/items/${itemB.id}`)
        .set('Authorization', `Bearer ${userA.token}`)
        .send({ name: 'Hacked' });

      expect(res.status).toBe(404);
    });

    it('should not allow user A to delete user B items', async () => {
      const userA = await createTestUser({ email: 'isoa3@test.com' });
      const userB = await createTestUser({ email: 'isob3@test.com' });
      const homeB = await createTestHome(userB.user.id);
      const itemB = await createTestItem(userB.user.id, homeB.id, { name: 'Private Item' });

      const res = await request(app)
        .delete(`/api/v1/items/${itemB.id}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });
  });

  // ──────────────────────────────── Phase 6 hardening ────────────────────────────────

  // Audit Ch12-T039: future purchaseDate must be rejected by validator (Joi
  // .max('now')).
  describe('Date validation', () => {
    it('should reject a future purchase date', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const future = new Date();
      future.setFullYear(future.getFullYear() + 5);

      const res = await request(app)
        .post('/api/v1/items')
        .set('Authorization', `Bearer ${token}`)
        .send(buildItemPayload(home.id, { purchaseDate: future.toISOString().slice(0, 10) }));

      expect(res.status).toBe(400);
    });

    // Audit Ch02-F061: lastMaintenanceDate must be on/after installationDate.
    it('should reject lastMaintenanceDate earlier than installationDate', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      const res = await request(app)
        .post('/api/v1/items')
        .set('Authorization', `Bearer ${token}`)
        .send(buildItemPayload(home.id, {
          installationDate: '2024-06-01',
          lastMaintenanceDate: '2024-01-01',
        }));

      expect(res.status).toBe(400);
    });
  });

  // Audit Ch12-T056: numeric price must reject negative input.
  describe('Numeric validation', () => {
    it('should reject a negative price', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      const res = await request(app)
        .post('/api/v1/items')
        .set('Authorization', `Bearer ${token}`)
        .send(buildItemPayload(home.id, { price: -1 }));

      expect(res.status).toBe(400);
    });
  });

  // Audit Ch12-T043: sort/order params constrained to a closed allowlist.
  describe('Pagination validation', () => {
    it('should reject SQL-injection-shaped sort parameter', async () => {
      const { token } = await createTestUser();
      const res = await request(app)
        .get(`/api/v1/items?sort=name;DROP+TABLE+items--`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(400);
    });

    // Audit Ch12-T044: pagination clamps negative + huge values to safe ranges
    // OR rejects them. Either is acceptable as long as the route doesn't 500.
    it('should reject a negative page number', async () => {
      const { token } = await createTestUser();
      const res = await request(app)
        .get(`/api/v1/items?page=-5`)
        .set('Authorization', `Bearer ${token}`);

      // Joi with min(1) returns 400; route hand-clamping returns 200 with page=1.
      expect([200, 400]).toContain(res.status);
    });

    it('should reject a huge limit', async () => {
      const { token } = await createTestUser();
      const res = await request(app)
        .get(`/api/v1/items?limit=99999`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(400);
    });
  });

  // Audit Ch12-T029: CSV cells starting with =,+,-,@ must be prefixed with a
  // single quote so spreadsheet apps don't interpret them as formulas.
  describe('CSV export hardening', () => {
    it('should prefix formula-injection cells with a single quote', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      await createTestItem(user.id, home.id, { name: '=cmd|"calc"!A1' });

      const res = await request(app)
        .get('/api/v1/items/export.csv')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      // The cell will be wrapped in quotes by RFC 4180 escaping (commas/quotes
      // present); the embedded value is `'=cmd|"calc"!A1` (note leading ').
      expect(res.text).toMatch(/'=cmd/);
    });

    // Audit Ch12-T014: cross-user CSV export must scope to the caller.
    it('should not include other user items in CSV export', async () => {
      const userA = await createTestUser({ email: 'csva@test.com' });
      const userB = await createTestUser({ email: 'csvb@test.com' });
      const homeB = await createTestHome(userB.user.id);
      await createTestItem(userB.user.id, homeB.id, { name: 'Secret B Item' });

      const res = await request(app)
        .get('/api/v1/items/export.csv')
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(200);
      expect(res.text).not.toContain('Secret B Item');
    });
  });
});
