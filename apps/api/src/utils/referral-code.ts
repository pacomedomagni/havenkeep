import crypto from 'crypto';
import { query } from '../db';

const REFERRAL_CODE_PREFIX = 'HK';
const REFERRAL_CODE_ATTEMPTS = 5;

function formatReferralCode(raw: string): string {
  const upper = raw.toUpperCase();
  return `${REFERRAL_CODE_PREFIX}-${upper.slice(0, 4)}-${upper.slice(4, 8)}`;
}

export async function generateUniqueReferralCode(): Promise<string> {
  for (let attempt = 0; attempt < REFERRAL_CODE_ATTEMPTS; attempt += 1) {
    const raw = crypto.randomBytes(4).toString('hex');
    const code = formatReferralCode(raw);

    const exists = await query(
      `SELECT 1 FROM users WHERE referral_code = $1`,
      [code]
    );
    if (exists.rows.length === 0) {
      return code;
    }
  }

  throw new Error('Failed to generate unique referral code');
}
