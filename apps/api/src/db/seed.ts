/**
 * Dev seed — idempotent. Re-run safely; rows that already exist are left
 * alone. Designed for local dev only — refuses to run in NODE_ENV=production.
 *
 * Creates two users:
 *   1. `dev@havenkeep.com` / `DevPass1234!`
 *      - email_verified=true, plan=premium (10y), default home pre-created
 *      - Use this for everyday dev: drops you straight on the dashboard.
 *   2. `onboarding@havenkeep.com` / `OnboardPass1234!`
 *      - email_verified=true, plan=free, NO home, NO premium
 *      - Use this when you want to walk the onboarding flow end-to-end
 *        (welcome → first action → home setup → room setup → add item).
 *
 * Run with: `npm run db:seed` (uses tsx, reads .env from the repo root).
 */

import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { pool } from './index';
import { config } from '../config';
import { logger } from '../utils/logger';

interface SeedUserSpec {
  email: string;
  password: string;
  name: string;
  referralCode: string;
  plan: 'free' | 'premium';
  premiumExpiry: string | null;
  withDefaultHome: boolean;
  homeName?: string;
}

const SEED_USERS: SeedUserSpec[] = [
  {
    email: 'dev@havenkeep.com',
    password: 'DevPass1234!',
    name: 'Dev User',
    referralCode: 'DEVUSER1',
    plan: 'premium',
    premiumExpiry: "NOW() + INTERVAL '10 years'",
    withDefaultHome: true,
    homeName: 'Dev Home',
  },
  {
    email: 'onboarding@havenkeep.com',
    password: 'OnboardPass1234!',
    name: 'Onboarding User',
    referralCode: 'ONBOARD1',
    plan: 'free',
    premiumExpiry: null,
    withDefaultHome: false,
  },
];

// Mirror the register handler's pre-hash so the resulting bcrypt hash is
// compatible with the production sign-in path (bcrypt only sees a 44-char
// SHA-256 base64 string, never the raw password).
function preHashForBcrypt(password: string): string {
  return crypto.createHash('sha256').update(password, 'utf8').digest('base64').slice(0, 72);
}

async function seedUser(spec: SeedUserSpec): Promise<{ userId: string; created: boolean }> {
  const passwordHash = await bcrypt.hash(preHashForBcrypt(spec.password), 10);
  const expiryFragment = spec.premiumExpiry ?? 'NULL';

  // INSERT ... ON CONFLICT DO NOTHING + RETURNING — gives us the row
  // whether we just created it or it already existed.
  const insertResult = await pool.query<{ id: string }>(
    `INSERT INTO users (
       email, password_hash, full_name, auth_provider,
       email_verified, plan, plan_expires_at, referral_code, is_admin
     )
     VALUES ($1, $2, $3, 'email', TRUE, $4, ${expiryFragment}, $5, FALSE)
     ON CONFLICT (email) DO NOTHING
     RETURNING id`,
    [spec.email, passwordHash, spec.name, spec.plan, spec.referralCode],
  );

  let userId: string;
  let created = false;
  if (insertResult.rows.length > 0) {
    userId = insertResult.rows[0].id;
    created = true;
  } else {
    const existing = await pool.query<{ id: string }>(
      `SELECT id FROM users WHERE email = $1`,
      [spec.email],
    );
    if (existing.rows.length === 0) {
      throw new Error(`Failed to upsert seed user ${spec.email}`);
    }
    userId = existing.rows[0].id;
  }

  if (spec.withDefaultHome && spec.homeName) {
    // Idempotent via ON CONFLICT — the (user_id, name) tuple identifies a
    // home unambiguously for our seed purposes.
    await pool.query(
      `INSERT INTO homes (user_id, name)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [userId, spec.homeName],
    );
  }

  return { userId, created };
}

/**
 * Seed sample warranties + maintenance + a savings claim onto the dev
 * user so the App Store / Play Store screenshots show realistic content
 * instead of empty-state cards. Idempotent — keyed on item name; running
 * the seed multiple times is a no-op for these rows.
 */
async function seedSampleData(devUserId: string): Promise<void> {
  // Find the dev user's home (created above by seedUser).
  const homeRes = await pool.query<{ id: string }>(
    `SELECT id FROM homes WHERE user_id = $1 ORDER BY created_at LIMIT 1`,
    [devUserId],
  );
  if (homeRes.rows.length === 0) {
    logger.warn({ devUserId }, 'Dev user has no home — skipping sample data');
    return;
  }
  const homeId = homeRes.rows[0].id;

  // Warranty mix: a few currently-active, two expiring soon, one expired.
  // Spans appliance / electronics / furniture so screenshots look broad.
  const items = [
    {
      name: 'French Door Refrigerator',
      brand: 'LG',
      model: 'LRFXS2503S',
      category: 'refrigerator',
      room: 'kitchen',
      price: 2199,
      purchaseMonthsAgo: 8,
      warrantyMonths: 60,
      store: 'Best Buy',
    },
    {
      name: 'Front-Load Washer',
      brand: 'Samsung',
      model: 'WF45T6000AW',
      category: 'washer',
      room: 'laundry',
      price: 949,
      purchaseMonthsAgo: 14,
      warrantyMonths: 24,
      store: 'Lowe\'s',
    },
    {
      name: 'OLED 65" 4K Smart TV',
      brand: 'Sony',
      model: 'XR-65A80L',
      category: 'tv',
      room: 'living_room',
      price: 1799,
      purchaseMonthsAgo: 4,
      warrantyMonths: 12,
      store: 'Costco',
    },
    {
      name: 'MacBook Pro 16"',
      brand: 'Apple',
      model: 'M3 Pro 18GB',
      category: 'computer',
      room: 'office',
      price: 2499,
      purchaseMonthsAgo: 11,
      warrantyMonths: 12,
      store: 'Apple Store',
    },
    {
      name: 'Robot Vacuum',
      brand: 'iRobot',
      model: 'Roomba j7+',
      category: 'other',
      room: 'living_room',
      price: 599,
      purchaseMonthsAgo: 22,
      warrantyMonths: 24,
      store: 'Amazon',
    },
    {
      name: 'Tankless Water Heater',
      brand: 'Rinnai',
      model: 'V94iN',
      category: 'water_heater',
      room: 'basement',
      price: 1499,
      purchaseMonthsAgo: 6,
      warrantyMonths: 144,
      store: 'Home Depot',
    },
    {
      name: 'Espresso Machine',
      brand: 'Breville',
      model: 'Barista Touch',
      category: 'other',
      room: 'kitchen',
      price: 1099,
      purchaseMonthsAgo: 2,
      warrantyMonths: 12,
      store: 'Williams Sonoma',
    },
  ];

  for (const it of items) {
    const purchaseDate = `NOW() - INTERVAL '${it.purchaseMonthsAgo} months'`;
    const warrantyEnd = `(NOW() - INTERVAL '${it.purchaseMonthsAgo} months' + INTERVAL '${it.warrantyMonths} months')::date`;

    await pool.query(
      `INSERT INTO items (
         user_id, home_id, name, brand, model_number, category, room,
         price, store, purchase_date, warranty_months, warranty_end_date,
         warranty_type, added_via
       )
       SELECT $1::uuid, $2::uuid, $3::varchar, $4::varchar, $5::varchar,
              $6::item_category, $7::item_room,
              $8::numeric, $9::varchar, ${purchaseDate}, $10::int, ${warrantyEnd},
              'manufacturer', 'manual'
       WHERE NOT EXISTS (
         SELECT 1 FROM items WHERE user_id = $1::uuid AND name = $3::varchar
       )`,
      [
        devUserId,
        homeId,
        it.name,
        it.brand,
        it.model,
        it.category,
        it.room,
        it.price,
        it.store,
        it.warrantyMonths,
      ],
    );
  }

  // Add 2 completed maintenance entries for the refrigerator so the
  // history screen + recent maintenance card aren't empty.
  await pool.query(
    `INSERT INTO maintenance_history (
       user_id, item_id, task_name, completed_date, duration_minutes, cost, notes
     )
     SELECT $1::uuid, i.id, 'Replaced water filter',
            (NOW() - INTERVAL '21 days')::date, 10, 49.99,
            'Used the OEM LG cartridge — 6-month interval per manual.'
       FROM items i
      WHERE i.user_id = $1::uuid AND i.name = 'French Door Refrigerator'
        AND NOT EXISTS (
          SELECT 1 FROM maintenance_history m
           WHERE m.user_id = $1::uuid AND m.item_id = i.id AND m.task_name = 'Replaced water filter'
        )`,
    [devUserId],
  );
  await pool.query(
    `INSERT INTO maintenance_history (
       user_id, item_id, task_name, completed_date, duration_minutes, cost
     )
     SELECT $1::uuid, i.id, 'Cleaned condenser coils',
            (NOW() - INTERVAL '92 days')::date, 15, 0
       FROM items i
      WHERE i.user_id = $1::uuid AND i.name = 'French Door Refrigerator'
        AND NOT EXISTS (
          SELECT 1 FROM maintenance_history m
           WHERE m.user_id = $1::uuid AND m.item_id = i.id AND m.task_name = 'Cleaned condenser coils'
        )`,
    [devUserId],
  );

  // One successful warranty claim with savings, against the washer (still
  // under coverage). Drives the dashboard "savings" surface.
  await pool.query(
    `INSERT INTO warranty_claims (
       user_id, item_id, claim_date, status, issue_description,
       repair_description, repair_cost, amount_saved, out_of_pocket, filed_with
     )
     SELECT $1::uuid, i.id, (NOW() - INTERVAL '40 days')::date, 'approved',
            'Washer drum stopped spinning during the rinse cycle. Diagnosed as a failed motor coupler.',
            'Samsung dispatched authorized tech; parts + labor covered under standard warranty.',
            389.50, 389.50, 0.00, 'Samsung'
       FROM items i
      WHERE i.user_id = $1::uuid AND i.name = 'Front-Load Washer'
        AND NOT EXISTS (
          SELECT 1 FROM warranty_claims c WHERE c.user_id = $1::uuid AND c.item_id = i.id
        )`,
    [devUserId],
  );

  logger.info({ devUserId }, 'Sample data seeded for dev user');
}

async function seed() {
  if (config.env === 'production') {
    throw new Error('seed.ts must not run in production');
  }

  logger.info({ env: config.env }, 'Seeding dev data');

  const results: Array<{ spec: SeedUserSpec; userId: string; created: boolean }> = [];
  for (const spec of SEED_USERS) {
    const { userId, created } = await seedUser(spec);
    results.push({ spec, userId, created });
    logger.info(
      { userId, email: spec.email, created, plan: spec.plan, withHome: spec.withDefaultHome },
      created ? 'Created seed user' : 'Seed user already existed — skipped',
    );
  }

  // Sample data only goes to the homed dev user — onboarding user must
  // stay empty so the post-signup flow plays end-to-end.
  const devResult = results.find((r) => r.spec.email === 'dev@havenkeep.com');
  if (devResult) {
    await seedSampleData(devResult.userId);
  }

  // Operator-friendly recap to stdout (logger may suppress if level is high).
  // eslint-disable-next-line no-console
  console.log('');
  for (const { spec, userId } of results) {
    // eslint-disable-next-line no-console
    console.log(`  ${spec.email}`);
    // eslint-disable-next-line no-console
    console.log(`    password: ${spec.password}`);
    // eslint-disable-next-line no-console
    console.log(
      `    plan:     ${spec.plan}${spec.plan === 'premium' ? ' (10y)' : ''}`,
    );
    // eslint-disable-next-line no-console
    console.log(`    home:     ${spec.withDefaultHome ? 'pre-created' : 'NOT created (onboarding will play)'}`);
    // eslint-disable-next-line no-console
    console.log(`    user id:  ${userId}`);
    // eslint-disable-next-line no-console
    console.log('');
  }
}

seed()
  .then(() => pool.end())
  .then(() => process.exit(0))
  .catch((err) => {
    logger.error({ err }, 'Seed failed');
    pool.end().finally(() => process.exit(1));
  });
