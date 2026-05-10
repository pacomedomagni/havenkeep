// H20: MfaService coverage. Drives the service directly (no HTTP layer)
// because the audit's concern is "the MFA pipeline has zero automated
// coverage and the otplib stub returns valid=true for every code."
//
// Strategy:
//   - Use the existing otplib mock that ships in `__tests__/__mocks__/`.
//     We extended it (H20) with a per-suite `__setExpectedToken(value)`
//     escape hatch so tests can distinguish "right code" from "wrong
//     code" without pulling in real otplib's ESM dependency chain
//     (@scure/base trips Jest's CommonJS resolver).
//   - Each test seeds a fresh user via the same createTestUser helper
//     other suites use, runs the MfaService method, then asserts on
//     DB state directly so the test doesn't rely on response-shape
//     conventions that might drift.

import { pool } from '../db';
import { cleanDatabase } from './setup';
import { createTestUser } from './helpers';
import { MfaService, mintMfaChallengeToken, verifyMfaChallengeToken } from '../services/mfa.service';

// Pull in the mock's escape hatch.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { __setExpectedToken } = require('./__mocks__/otplib.cjs') as {
  __setExpectedToken: (value: string | null) => void;
};

beforeEach(async () => {
  await cleanDatabase();
  __setExpectedToken(null); // default: accept every code (matches prior mock behaviour)
});

// NOTE: no local `afterAll(() => pool.end())` — `setup.ts` registers a
// process-global `afterAll` that closes the pool exactly once. Adding a
// second one here would call `pool.end()` twice and surface "Called end
// on pool more than once" as a suite failure.

describe('MfaService.getStatus', () => {
  it('returns hasVerifiedFactor=false for a user with no MFA rows', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const status = await MfaService.getStatus(userId);
    expect(status.hasVerifiedFactor).toBe(false);
    expect(status.factorTypes).toEqual([]);
  });

  it('returns hasVerifiedFactor=true only after verify-enrollment flips verified_at', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);
    // Pre-verify: row exists but verified_at is NULL.
    const before = await MfaService.getStatus(userId);
    expect(before.hasVerifiedFactor).toBe(false);

    await MfaService.verifyEnrollmentCode(userId, '123456');
    const after = await MfaService.getStatus(userId);
    expect(after.hasVerifiedFactor).toBe(true);
    expect(after.factorTypes).toEqual(['totp']);
  });
});

describe('MfaService.enrollTotp', () => {
  it('persists a single unverified factor + ten backup codes', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    const enroll = await MfaService.enrollTotp(userId, email);

    expect(enroll.secret).toBeTruthy();
    expect(enroll.otpauthUrl).toContain('otpauth://totp/');
    expect(enroll.qrCodeDataUrl.startsWith('data:image/')).toBe(true);
    expect(enroll.backupCodes).toHaveLength(10);

    const factor = await pool.query(
      `SELECT id, verified_at FROM user_mfa_factors WHERE user_id = $1`,
      [userId],
    );
    expect(factor.rows).toHaveLength(1);
    expect(factor.rows[0].verified_at).toBeNull();

    const backups = await pool.query(
      `SELECT COUNT(*)::int AS c FROM user_mfa_backup_codes WHERE user_id = $1`,
      [userId],
    );
    expect(backups.rows[0].c).toBe(10);
  });

  it('a re-enroll overwrites the previous unverified factor (no accumulation)', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    const first = await MfaService.enrollTotp(userId, email);
    const second = await MfaService.enrollTotp(userId, email);
    expect(second.factorId).not.toBe(first.factorId);

    const rows = await pool.query(
      `SELECT id FROM user_mfa_factors WHERE user_id = $1 AND verified_at IS NULL`,
      [userId],
    );
    expect(rows.rows).toHaveLength(1);
    expect(rows.rows[0].id).toBe(second.factorId);
  });
});

describe('MfaService.verifyEnrollmentCode', () => {
  it('happy path: a correct code flips verified_at to NOT NULL', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);

    __setExpectedToken('654321');
    await expect(MfaService.verifyEnrollmentCode(userId, '654321')).resolves.toBeUndefined();

    const row = await pool.query(
      `SELECT verified_at FROM user_mfa_factors WHERE user_id = $1`,
      [userId],
    );
    expect(row.rows[0].verified_at).not.toBeNull();
  });

  it('wrong code throws AppError 400 and leaves verified_at NULL', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);

    __setExpectedToken('111111');
    await expect(MfaService.verifyEnrollmentCode(userId, '999999')).rejects.toMatchObject({
      statusCode: 400,
    });

    const row = await pool.query(
      `SELECT verified_at FROM user_mfa_factors WHERE user_id = $1`,
      [userId],
    );
    expect(row.rows[0].verified_at).toBeNull();
  });

  it('throws 404 when there is no pending enrollment', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    await expect(MfaService.verifyEnrollmentCode(userId, '123456')).rejects.toMatchObject({
      statusCode: 404,
    });
  });
});

describe('MfaService.verifyChallengeCode', () => {
  it('TOTP happy path: a 6-digit code accepted by otplib resolves', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);
    await MfaService.verifyEnrollmentCode(userId, '123456');

    __setExpectedToken('424242');
    await expect(MfaService.verifyChallengeCode(userId, '424242')).resolves.toBeUndefined();
  });

  it('TOTP wrong code throws 400', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);
    await MfaService.verifyEnrollmentCode(userId, '123456');

    __setExpectedToken('123456');
    await expect(MfaService.verifyChallengeCode(userId, '999999')).rejects.toMatchObject({
      statusCode: 400,
    });
  });

  it('backup-code path consumes the code (single-use)', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    const enroll = await MfaService.enrollTotp(userId, email);
    await MfaService.verifyEnrollmentCode(userId, '123456');

    const aBackup = enroll.backupCodes[0];
    await expect(MfaService.verifyChallengeCode(userId, aBackup)).resolves.toBeUndefined();

    // Same backup code a second time must fail.
    await expect(MfaService.verifyChallengeCode(userId, aBackup)).rejects.toMatchObject({
      statusCode: 400,
    });
  });
});

describe('MfaService.disableTotp', () => {
  it('removes the factor + every backup code after a successful challenge', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);
    await MfaService.verifyEnrollmentCode(userId, '123456');

    __setExpectedToken('777777');
    await MfaService.disableTotp(userId, '777777');

    const factors = await pool.query(
      `SELECT COUNT(*)::int AS c FROM user_mfa_factors WHERE user_id = $1`,
      [userId],
    );
    const backups = await pool.query(
      `SELECT COUNT(*)::int AS c FROM user_mfa_backup_codes WHERE user_id = $1`,
      [userId],
    );
    expect(factors.rows[0].c).toBe(0);
    expect(backups.rows[0].c).toBe(0);
  });

  it('refuses to disable when the code is wrong (factor stays intact)', async () => {
    const { user } = await createTestUser();
    const userId = user.id;
    const email = user.email;
    await MfaService.enrollTotp(userId, email);
    await MfaService.verifyEnrollmentCode(userId, '123456');

    __setExpectedToken('correct');
    await expect(MfaService.disableTotp(userId, 'incorrect')).rejects.toMatchObject({
      statusCode: 400,
    });

    const factors = await pool.query(
      `SELECT COUNT(*)::int AS c FROM user_mfa_factors WHERE user_id = $1`,
      [userId],
    );
    expect(factors.rows[0].c).toBe(1);
  });
});

describe('MFA challenge JWT', () => {
  it('mint + verify round-trips with the right purpose claim', () => {
    const userId = '00000000-0000-0000-0000-000000000001';
    const token = mintMfaChallengeToken(userId);
    expect(token.split('.')).toHaveLength(3); // shape: header.payload.sig

    const decoded = verifyMfaChallengeToken(token);
    expect(decoded.userId).toBe(userId);
  });

  it('a token with the wrong purpose claim is rejected', () => {
    // Mint via jwt directly with a different purpose; verify should reject.
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const jwt = require('jsonwebtoken') as typeof import('jsonwebtoken');
    const { config } = require('../config');
    const token = jwt.sign(
      { userId: 'u', purpose: 'account_recover' },
      config.jwt.secret,
      {
        algorithm: 'HS256',
        expiresIn: 300,
        issuer: config.jwt.issuer,
        audience: config.jwt.audience,
      },
    );
    expect(() => verifyMfaChallengeToken(token)).toThrow();
  });
});
