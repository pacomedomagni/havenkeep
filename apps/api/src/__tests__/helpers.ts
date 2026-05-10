import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { pool } from '../db';
import { config } from '../config';
import { createApp } from '../app';
import { preHashForBcrypt } from '../utils/password';

export function getTestApp() {
  return createApp();
}

/**
 * Sign a JWT for the given user. The `email` claim is required so the token
 * matches what the user row actually carries — without it the auth middleware
 * sees a drift between JWT.email and DB.email and refuses the request, which
 * masked real activation/refresh-token bugs in the audit.
 */
export function getAuthToken(
  userId: string,
  claims: { email: string; isAdmin?: boolean; isPartner?: boolean; [k: string]: any }
) {
  const { email, isAdmin = false, isPartner = false, ...rest } = claims;
  // H13: production auth middleware pins iss + aud. Mint tokens here
  // with the same claims so middleware accepts them — otherwise every
  // authed route returns 401 in tests.
  return jwt.sign(
    { userId, email, isAdmin, isPartner, ...rest },
    config.jwt.secret,
    {
      expiresIn: '1h',
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
      jwtid: crypto.randomUUID(),
    }
  );
}

export function getAdminToken(userId: string, email: string) {
  return getAuthToken(userId, { email, isAdmin: true });
}

export async function createTestUser(overrides: Record<string, any> = {}) {
  const email = (overrides.email || `test-${crypto.randomUUID()}@test.com`).toLowerCase();
  // Mirror the production hashing pipeline — preHashForBcrypt + bcrypt — so
  // long-password regressions surface in tests instead of being silently
  // truncated by bcrypt's 72-byte input cap (S3-12 / S1-C).
  const passwordHash = await bcrypt.hash(
    preHashForBcrypt(overrides.password || 'TestPassword123!'),
    4, // low rounds for speed
  );
  const fullName = overrides.fullName || 'Test User';
  const isAdmin = overrides.isAdmin || false;
  const plan = overrides.plan || 'free';

  const result = await pool.query(
    `INSERT INTO users (email, password_hash, full_name, is_admin, plan, referral_code, email_verified)
     VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, FALSE))
     RETURNING *`,
    [
      email,
      passwordHash,
      fullName,
      isAdmin,
      plan,
      crypto.randomUUID().slice(0, 8),
      overrides.emailVerified ?? true,
    ]
  );

  const user = result.rows[0];
  const token = getAuthToken(user.id, {
    email: user.email,
    isAdmin: user.is_admin,
    isPartner: !!overrides.isPartner,
  });

  return { user, token };
}

export async function createTestHome(userId: string, overrides: Record<string, any> = {}) {
  const name = overrides.name || 'Test Home';
  const result = await pool.query(
    `INSERT INTO homes (user_id, name, address, city, state, zip)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`,
    [userId, name, overrides.address || '123 Test St', overrides.city || 'Testville', overrides.state || 'TS', overrides.zip || '12345']
  );
  return result.rows[0];
}

export async function createTestItem(userId: string, homeId: string, overrides: Record<string, any> = {}) {
  const name = overrides.name || 'Test Item';
  const purchaseDate = overrides.purchaseDate || '2024-01-01';
  const warrantyMonths = overrides.warrantyMonths || 12;
  // Calculate warranty_end_date from purchase_date + warranty_months
  const purchaseDateObj = new Date(purchaseDate);
  purchaseDateObj.setMonth(purchaseDateObj.getMonth() + warrantyMonths);
  const warrantyEndDate = overrides.warrantyEndDate || purchaseDateObj.toISOString().split('T')[0];

  const result = await pool.query(
    `INSERT INTO items (user_id, home_id, name, category, room, price, purchase_date, warranty_months, warranty_end_date)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING *`,
    [userId, homeId, name, overrides.category || 'other', overrides.room || 'living_room', overrides.price || 99.99, purchaseDate, warrantyMonths, warrantyEndDate]
  );
  return result.rows[0];
}
