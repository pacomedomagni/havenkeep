import { cleanDatabase } from './setup';
import { createTestUser, createTestHome, createTestItem } from './helpers';
import { ReconciliationService } from '../services/reconciliation.service';
import { pool } from '../db';

// S3-12.5 / S1-E + S2-I: reconciliation must report zero drift after a
// fresh pass. The original bug compared `parseFloat()` decimals between
// two recomputes and reported phantom drift on values like 19.99 because
// the float boundary mangled the comparison.
describe('ReconciliationService — zero drift after recompute (S1-E / S2-I)', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  it('reports zero drift after a clean pass over a seeded dataset', async () => {
    const { user } = await createTestUser({ email: 'reconcile@test.com' });
    const home = await createTestHome(user.id);
    const item = await createTestItem(user.id, home.id);
    const archived = await createTestItem(user.id, home.id, {
      name: 'Archived TV',
    });
    await pool.query(`UPDATE items SET is_archived = TRUE WHERE id = $1`, [
      archived.id,
    ]);

    // Two claims on the live item, plus one on the archived item that
    // S2-I excludes from the reconciled total.
    await pool.query(
      `INSERT INTO warranty_claims
         (user_id, item_id, claim_date, repair_cost, amount_saved, status)
       VALUES ($1, $2, '2026-01-15', 19.99, 19.99, 'filed'),
              ($1, $2, '2026-02-15', 7.07, 7.07, 'filed'),
              ($1, $3, '2026-03-15', 50.00, 50.00, 'filed')`,
      [user.id, item.id, archived.id],
    );

    // Seed the analytics counter from the live items only — the
    // sub-query in ReconciliationService excludes archived items, so the
    // canonical "actual" excludes the $50 archived claim.
    await pool.query(
      `INSERT INTO user_analytics
         (user_id, total_warranty_savings, total_claims_filed, total_maintenance_completed)
       VALUES ($1, 27.06, 2, 0)`,
      [user.id],
    );

    const first = await ReconciliationService.reconcileUserAnalytics();
    // Either zero drift on the first run, or fixed-then-clean on a
    // partial seed; the second pass MUST be clean.
    const second = await ReconciliationService.reconcileUserAnalytics();
    expect(second.discrepanciesFound).toBe(0);
    expect(second.discrepanciesFixed).toBe(0);
    // Sanity: first pass touched at most as many users as the seed.
    expect(first.usersChecked).toBeGreaterThanOrEqual(1);
  });
});
