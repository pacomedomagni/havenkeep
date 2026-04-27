import { Router } from 'express';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { query, getClient } from '../db';
import { authenticate } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { validate } from '../middleware/validate';
import { updateUserSchema, pushTokenSchema } from '../validators';
import { changePasswordSchema, deleteAccountSchema, providerParamSchema } from '../validators/users.validator';
import { changeEmailSchema } from '../validators/auth.validator';
import { blacklistTokenAuto } from '../utils/token-blacklist';
import { config } from '../config';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';
import { EmailService } from '../services/email.service';
import { EmailScannerService } from '../services/email-scanner.service';
import { verifyPremiumRateLimiter, passwordChangeRateLimiter, writeRateLimiter } from '../middleware/rateLimiter';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';
import { preHashForBcrypt } from '../utils/password';

const router = Router();
router.use(authenticate);

// Get current user profile.
//
// Ch08-User-D003 / D004: deleted_at + deletion_scheduled_for are returned so
// the client can render the "your account is scheduled for deletion in N days"
// banner and the recover button. They're NULL outside the cooling-off window.
//
// Ch08-User-D005: stripe_customer_id is intentionally NOT in the SELECT — it's
// internal billing plumbing the client has no business reading.
router.get('/me', asyncHandler(async (req, res) => {
  // email_change_pending / email_change_target are derived from the most
  // recent active change-email token (the change-email route stores the new
  // address in metadata->>'new_email' with metadata->>'type' = 'change_email').
  // The mobile UI uses these to render a "verification pending" badge next
  // to the email field.
  const result = await query(
    `SELECT u.id, u.email, u.full_name, u.avatar_url, u.auth_provider, u.plan, u.plan_expires_at,
            u.referred_by, u.referral_code, u.email_verified, u.apple_user_id, u.is_admin,
            u.deleted_at, u.deletion_scheduled_for, u.created_at, u.updated_at,
            (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) AS is_partner,
            (
              SELECT t.metadata->>'new_email'
                FROM email_verification_tokens t
               WHERE t.user_id = u.id
                 AND t.metadata->>'type' = 'change_email'
                 AND t.expires_at > NOW()
               ORDER BY t.created_at DESC
               LIMIT 1
            ) AS email_change_target
       FROM users u
      WHERE u.id = $1`,
    [req.user!.id]
  );

  if (result.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  const row = result.rows[0];
  sendSuccess(res, {
    ...row,
    email_change_pending: row.email_change_target !== null,
  });
}));

// Update user profile
router.put('/me', writeRateLimiter, validate(updateUserSchema), asyncHandler(async (req, res) => {
  const { fullName, avatarUrl } = req.body;
  const updates: string[] = [];
  const values: any[] = [];
  let paramIndex = 1;

  if (fullName !== undefined) {
    updates.push(`full_name = $${paramIndex++}`);
    values.push(fullName);
  }

  if (avatarUrl !== undefined) {
    updates.push(`avatar_url = $${paramIndex++}`);
    values.push(avatarUrl);
  }

  if (updates.length === 0) {
    throw new AppError('No fields to update', 400);
  }

  values.push(req.user!.id);

  // Mirror the GET /me response shape so the mobile cache update path gets
  // identical fields back (including the email-change-pending derivation).
  const result = await query(
    `UPDATE users SET
      ${updates.join(', ')},
      updated_at = NOW()
     WHERE id = $${paramIndex}
     RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
               referred_by, referral_code, email_verified, apple_user_id, is_admin,
               deleted_at, deletion_scheduled_for, created_at, updated_at,
               (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) AS is_partner,
               (
                 SELECT t.metadata->>'new_email'
                   FROM email_verification_tokens t
                  WHERE t.user_id = users.id
                    AND t.metadata->>'type' = 'change_email'
                    AND t.expires_at > NOW()
                  ORDER BY t.created_at DESC
                  LIMIT 1
               ) AS email_change_target`,
    values
  );

  if (result.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  const row = result.rows[0];
  sendSuccess(res, {
    ...row,
    email_change_pending: row.email_change_target !== null,
  });
}));

// Register push notification token.
//
// S1-I: an FCM token uniquely identifies a single device install. If a
// previous owner of this device sent the same token under a different
// account, we must not let their row coexist — both rows would receive
// pushes addressed to the new owner. The fix: in one transaction, evict
// any rows for this token belonging to other users, then upsert ours.
// This matches the real-world flow (sign out → sign in as someone else
// on the same phone) and is safe because FCM rotates tokens on app
// reinstall / data clear.
router.post('/push-token', writeRateLimiter, validate(pushTokenSchema), asyncHandler(async (req, res) => {
  const { fcmToken, platform } = req.body;
  const userId = req.user!.id;
  const platformValue = platform || 'unknown';

  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `DELETE FROM user_push_tokens WHERE fcm_token = $1 AND user_id <> $2`,
      [fcmToken, userId],
    );
    await client.query(
      `INSERT INTO user_push_tokens (user_id, fcm_token, platform, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id, fcm_token)
       DO UPDATE SET platform = $3, updated_at = NOW()`,
      [userId, fcmToken, platformValue],
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }

  sendMessage(res, 'Push token registered');
}));

// Verify premium subscription via RevenueCat.
// Ownership rule: we ONLY verify the subscription attached to the
// authenticated user's id. Clients are expected to set RevenueCat
// `app_user_id` == HavenKeep user uuid at SDK init time (the same
// assumption the RC webhook makes). This stops anyone from upgrading
// their own account by passing a victim's RC id.
router.post('/me/verify-premium', verifyPremiumRateLimiter, asyncHandler(async (req, res) => {
  const { revenueCatAppUserId } = req.body;
  const authUserId = req.user!.id;

  if (revenueCatAppUserId && typeof revenueCatAppUserId === 'string' && revenueCatAppUserId !== authUserId) {
    logger.warn(
      { authUserId, providedRcId: revenueCatAppUserId },
      'verify-premium: client-supplied RevenueCat id does not match authenticated user — rejecting',
    );
    throw new AppError('revenueCatAppUserId must match the authenticated user', 403);
  }

  const subjectId = authUserId;

  const rcApiKey = config.revenuecat.apiKey;
  if (!rcApiKey) {
    throw new AppError('RevenueCat is not configured on this server', 503);
  }

  // Call RevenueCat REST API to get subscriber info
  const rcResponse = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(subjectId)}`,
    {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${rcApiKey}`,
        'Content-Type': 'application/json',
      },
    }
  );

  if (!rcResponse.ok) {
    const errorBody = await rcResponse.text();
    logger.error({ statusCode: rcResponse.status, body: errorBody }, 'RevenueCat API error');
    throw new AppError('Failed to verify subscription with RevenueCat', 502);
  }

  const rcData = await rcResponse.json() as {
    subscriber: {
      entitlements: Record<string, {
        expires_date: string | null;
        purchase_date: string;
        product_identifier: string;
      }>;
    };
  };

  // Check for active premium entitlement
  const premiumEntitlement = rcData.subscriber?.entitlements?.premium;
  let isPremium = false;
  let expiresAt: string | null = null;

  if (premiumEntitlement) {
    const expiresDate = premiumEntitlement.expires_date;
    if (expiresDate === null) {
      // Lifetime / non-expiring entitlement
      isPremium = true;
    } else {
      isPremium = new Date(expiresDate) > new Date();
      expiresAt = expiresDate;
    }
  }

  // Update user plan in the database
  const prevPlanResult = await query(
    `SELECT plan FROM users WHERE id = $1`,
    [req.user!.id]
  );
  const previousPlan = prevPlanResult.rows[0]?.plan;

  const newPlan = isPremium ? 'premium' : 'free';
  const result = await query(
    `UPDATE users SET
      plan = $1,
      plan_expires_at = $2,
      updated_at = NOW()
     WHERE id = $3
     RETURNING id, email, plan, plan_expires_at`,
    [newPlan, expiresAt, req.user!.id]
  );

  if (result.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  if (previousPlan && previousPlan !== newPlan) {
    const action =
      newPlan === 'premium' ? 'user.plan_upgrade' : 'user.plan_downgrade';
    await AuditService.logFromRequest(req, action, {
      resourceType: 'user',
      resourceId: result.rows[0].id,
      description:
        newPlan === 'premium'
          ? 'Upgraded to premium'
          : 'Downgraded to free',
      metadata: {
        previous_plan: previousPlan,
        new_plan: newPlan,
        expires_at: expiresAt,
      },
    });
  }

  logger.info(
    { userId: req.user!.id, plan: newPlan, expiresAt },
    'Premium verification completed'
  );

  res.json({
    success: true,
    data: {
      plan: result.rows[0].plan,
      planExpiresAt: result.rows[0].plan_expires_at,
      verified: true,
    },
  });
}));

// Change email — initiates verification flow
router.post('/me/change-email', writeRateLimiter, validate(changeEmailSchema), asyncHandler(async (req, res) => {
  const { newEmail, password } = req.body;

  // Get current user
  const userResult = await query(
    `SELECT email, password_hash, full_name FROM users WHERE id = $1`,
    [req.user!.id]
  );

  if (userResult.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  const user = userResult.rows[0];

  if (!user.password_hash) {
    throw new AppError('Password is not set for this account. OAuth users cannot change email this way.', 400);
  }

  // Verify current password
  const valid = await bcrypt.compare(preHashForBcrypt(password), user.password_hash);
  if (!valid) {
    throw new AppError('Incorrect password', 401);
  }

  // Ensure new email is different from current
  if (newEmail.toLowerCase() === user.email.toLowerCase()) {
    throw new AppError('New email must be different from your current email', 400);
  }

  // Check if new email is already in use
  const existingUser = await query(
    `SELECT id FROM users WHERE LOWER(email) = LOWER($1)`,
    [newEmail]
  );

  if (existingUser.rows.length > 0) {
    throw new AppError('This email is already in use', 409);
  }

  // Generate a verification token
  const token = crypto.randomBytes(32).toString('hex');
  const hashedToken = crypto.createHash('sha256').update(token).digest('hex');

  // Delete any existing change-email tokens for this user
  await query(
    `DELETE FROM email_verification_tokens WHERE user_id = $1 AND metadata->>'type' = 'change_email'`,
    [req.user!.id]
  );

  // Store the hashed token with new_email metadata
  await query(
    `INSERT INTO email_verification_tokens (user_id, token, metadata, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '24 hours')`,
    [
      req.user!.id,
      hashedToken,
      JSON.stringify({ type: 'change_email', new_email: newEmail }),
    ]
  );

  // Build verification URL
  const verifyUrl = `${config.app.frontendUrl}/verify-email-change?token=${token}`;

  // Send verification email to the NEW address
  await EmailService.sendEmailChangeVerificationEmail({
    to: newEmail,
    user_name: user.full_name || 'there',
    verify_url: verifyUrl,
    new_email: newEmail,
  });

  // Audit log
  await AuditService.logFromRequest(req, 'user.email_change_requested', {
    resourceType: 'user',
    resourceId: req.user!.id,
    description: 'Email change verification sent',
    metadata: { new_email: newEmail },
  });

  logger.info(
    { userId: req.user!.id, newEmail },
    'Email change verification sent'
  );

  sendMessage(res, 'Verification email sent to your new address. Please check your inbox.');
}));

// Change password
router.put('/me/password', passwordChangeRateLimiter, validate(changePasswordSchema), asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.body;

  // Get current password hash
  const userResult = await query(
    `SELECT password_hash FROM users WHERE id = $1`,
    [req.user!.id]
  );

  if (userResult.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  if (!userResult.rows[0].password_hash) {
    throw new AppError('Password is not set for this account', 400);
  }

  // Verify current password
  const valid = await bcrypt.compare(preHashForBcrypt(currentPassword), userResult.rows[0].password_hash);
  if (!valid) {
    throw new AppError('Current password is incorrect', 401);
  }

  // Prevent setting the same password
  const samePassword = await bcrypt.compare(preHashForBcrypt(newPassword), userResult.rows[0].password_hash);
  if (samePassword) {
    throw new AppError('New password must be different from current password', 400);
  }

  // Hash and update new password
  const newHash = await bcrypt.hash(preHashForBcrypt(newPassword), 12);
  await query(
    `UPDATE users SET password_hash = $1 WHERE id = $2`,
    [newHash, req.user!.id]
  );

  // Blacklist the current access token using its actual remaining TTL
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const accessToken = authHeader.substring(7);
    await blacklistTokenAuto(accessToken);
  }

  // Invalidate all refresh tokens (force re-login on other devices)
  await query(
    `DELETE FROM refresh_tokens WHERE user_id = $1`,
    [req.user!.id]
  );

  // Audit log: password changed
  await AuditService.logFromRequest(req, 'user.update', {
    resourceType: 'user',
    resourceId: req.user!.id,
    description: 'Password changed',
  });

  sendMessage(res, 'Password changed successfully');
}));

// Delete account (soft-delete with 30-day cooling-off period)
// For email users: requires password confirmation.
// For OAuth users (no password): requires confirmDelete=true in body.
router.delete('/me', validate(deleteAccountSchema), asyncHandler(async (req, res) => {
  const { password, confirmDelete } = req.body || {};

  // Get user info to determine auth method
  const userResult = await query(
    `SELECT password_hash, auth_provider, email, full_name FROM users WHERE id = $1`,
    [req.user!.id]
  );

  if (userResult.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  const user = userResult.rows[0];

  if (user.password_hash) {
    // Email user: require password confirmation
    if (!password) {
      throw new AppError('Password is required to delete your account', 400);
    }
    const valid = await bcrypt.compare(preHashForBcrypt(password), user.password_hash);
    if (!valid) {
      throw new AppError('Invalid password', 401);
    }
  } else {
    // OAuth user: require explicit confirmation flag
    if (confirmDelete !== true) {
      throw new AppError('Please confirm account deletion by setting confirmDelete to true', 400);
    }
  }

  // Atomic soft-delete + token invalidation
  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Capture the prior plan so /me/recover can restore it later. We move
    // the user to 'suspended' for the 30-day grace window — recover swaps
    // back to plan_before_delete.
    await client.query(
      `UPDATE users
          SET plan_before_delete = CASE
                                     WHEN plan <> 'suspended' THEN plan
                                     ELSE plan_before_delete
                                   END,
              deleted_at = NOW(),
              deletion_scheduled_for = NOW() + INTERVAL '30 days',
              plan = 'suspended',
              updated_at = NOW()
        WHERE id = $1`,
      [req.user!.id],
    );

    // Invalidate all refresh tokens to log the user out everywhere
    await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [req.user!.id]);

    await client.query('COMMIT');
  } catch (txError) {
    await client.query('ROLLBACK');
    throw txError;
  } finally {
    client.release();
  }

  // Revoke any stored OAuth integrations (Gmail/Outlook scanner). Done
  // outside the txn because it touches a separate concern (provider auth)
  // and we don't want a missing oauth-integrations table to roll back the
  // primary user soft-delete in older test environments.
  try {
    await EmailScannerService.revokeIntegration(req.user!.id);
  } catch (revokeErr) {
    logger.warn({ error: revokeErr, userId: req.user!.id }, 'Failed to revoke OAuth integrations on delete');
  }

  // Blacklist the current access token
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    try {
      await blacklistTokenAuto(authHeader.substring(7));
    } catch {
      // Best-effort
    }
  }

  // Fire-and-forget: send account deletion confirmation email
  EmailService.sendAccountDeletionEmail({
    to: user.email,
    user_name: user.full_name || 'there',
  }).catch((err) => {
    logger.warn({ error: err, userId: req.user!.id }, 'Failed to send account deletion email (non-blocking)');
  });

  await AuditService.logFromRequest(req, 'user.delete', {
    resourceType: 'user',
    resourceId: req.user!.id,
    description: 'User scheduled account for deletion (30-day cooling-off)',
  });

  sendMessage(res, 'Account scheduled for deletion in 30 days. You can recover it by logging in before then.');
}));

// Recover a soft-deleted account during the cooling-off period
router.post('/me/recover', asyncHandler(async (req, res) => {
  const userResult = await query(
    `SELECT id, deleted_at, deletion_scheduled_for FROM users WHERE id = $1`,
    [req.user!.id]
  );

  if (userResult.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  const user = userResult.rows[0];

  if (!user.deleted_at) {
    throw new AppError('Account is not scheduled for deletion', 400);
  }

  // Clear soft-delete markers and restore the prior plan captured at delete
  // time. Falls back to 'free' only when no prior plan was captured (e.g.
  // user soft-deleted before plan_before_delete shipped).
  const recovered = await query(
    `UPDATE users
        SET deleted_at = NULL,
            deletion_scheduled_for = NULL,
            plan = COALESCE(plan_before_delete, 'free'),
            plan_before_delete = NULL,
            updated_at = NOW()
      WHERE id = $1
      RETURNING plan`,
    [req.user!.id],
  );

  await AuditService.logFromRequest(req, 'user.update', {
    resourceType: 'user',
    resourceId: req.user!.id,
    description: 'User recovered account from scheduled deletion',
  });

  sendMessage(res, `Account recovered successfully. Your plan has been restored to ${recovered.rows[0]?.plan || 'free'}.`);
}));

// ─────────────────────────── Linked sign-in providers ───────────────────────────
//
// Backs the mobile "Settings → Linked accounts" screen. The data model that
// determines whether a provider is currently linked:
//
//   • email  — `users.password_hash IS NOT NULL`
//   • google — `users.auth_provider = 'google'` OR an active row exists in
//              `user_oauth_integrations` with provider='gmail'. Migration 038
//              uses the same OAuth token table for the email-scanner; the
//              scopes overlap by provider, so a Gmail integration also signals
//              "Google is linked" for sign-in purposes.
//   • apple  — `users.auth_provider = 'apple'` OR `users.apple_user_id` is set.
//
// `isPrimary` is the original signup path (`users.auth_provider`).
// `linkedAt` prefers the provider-specific timestamp (oauth-integration row
// for google) and falls back to `users.created_at` when no later linkage row
// exists. The unlink endpoint refuses any request that would leave the
// account with zero usable sign-in paths.

interface LinkedProvider {
  provider: 'email' | 'google' | 'apple';
  linkedAt: string;
  providerEmail: string;
  isPrimary: boolean;
}

router.get('/me/providers', asyncHandler(async (req, res) => {
  const result = await query(
    `SELECT u.email, u.auth_provider, u.password_hash IS NOT NULL AS has_password,
            u.apple_user_id, u.created_at,
            (
              SELECT json_build_object(
                'provider_email', oi.provider_email,
                'created_at',     oi.created_at
              )
                FROM user_oauth_integrations oi
               WHERE oi.user_id = u.id
                 AND oi.provider = 'gmail'
                 AND oi.revoked_at IS NULL
               ORDER BY oi.created_at ASC
               LIMIT 1
            ) AS gmail_integration
       FROM users u
      WHERE u.id = $1`,
    [req.user!.id],
  );

  if (result.rows.length === 0) {
    throw new AppError('User not found', 404);
  }

  const row = result.rows[0];
  const providers: LinkedProvider[] = [];

  if (row.has_password) {
    providers.push({
      provider: 'email',
      linkedAt: row.created_at,
      providerEmail: row.email,
      isPrimary: row.auth_provider === 'email',
    });
  }

  if (row.auth_provider === 'google' || row.gmail_integration) {
    providers.push({
      provider: 'google',
      linkedAt: row.gmail_integration?.created_at ?? row.created_at,
      providerEmail: row.gmail_integration?.provider_email ?? row.email,
      isPrimary: row.auth_provider === 'google',
    });
  }

  if (row.auth_provider === 'apple' || row.apple_user_id) {
    providers.push({
      provider: 'apple',
      linkedAt: row.created_at,
      providerEmail: row.email,
      isPrimary: row.auth_provider === 'apple',
    });
  }

  sendSuccess(res, providers);
}));

router.delete(
  '/me/providers/:provider',
  writeRateLimiter,
  validate({ params: providerParamSchema }),
  asyncHandler(async (req, res) => {
    const provider = req.params.provider as 'email' | 'google' | 'apple';

    const userResult = await query(
      `SELECT u.password_hash IS NOT NULL AS has_password,
              u.auth_provider,
              u.apple_user_id IS NOT NULL AS has_apple,
              EXISTS(
                SELECT 1 FROM user_oauth_integrations oi
                 WHERE oi.user_id = u.id
                   AND oi.provider = 'gmail'
                   AND oi.revoked_at IS NULL
              ) AS has_gmail_oauth
         FROM users u
        WHERE u.id = $1`,
      [req.user!.id],
    );

    if (userResult.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    const u = userResult.rows[0];

    // Compute which sign-in paths exist BEFORE the unlink, then verify at
    // least one will remain AFTER. Refuse otherwise — orphaning the account
    // is a data-loss footgun (no remaining way to log in or reset password).
    const hasEmail = u.has_password;
    const hasGoogle = u.auth_provider === 'google' || u.has_gmail_oauth;
    const hasApple = u.auth_provider === 'apple' || u.has_apple;

    const remaining =
      (provider === 'email' ? false : hasEmail) ||
      (provider === 'google' ? false : hasGoogle) ||
      (provider === 'apple' ? false : hasApple);

    if (!remaining) {
      throw new AppError(
        'Cannot unlink the only remaining sign-in method. Add a password or another OAuth provider first.',
        409,
      );
    }

    // Determine the new primary `auth_provider` if we're unlinking the
    // current primary. Pick the first remaining path in deterministic order
    // (email → google → apple). Otherwise leave auth_provider untouched.
    let newAuthProvider: string | null = null;
    if (u.auth_provider === provider) {
      if (provider !== 'email' && hasEmail) newAuthProvider = 'email';
      else if (provider !== 'google' && hasGoogle) newAuthProvider = 'google';
      else if (provider !== 'apple' && hasApple) newAuthProvider = 'apple';
    }

    const client = await getClient();
    try {
      await client.query('BEGIN');

      if (provider === 'email') {
        await client.query(
          `UPDATE users SET password_hash = NULL, updated_at = NOW() WHERE id = $1`,
          [req.user!.id],
        );
      } else if (provider === 'google') {
        // Soft-revoke any Gmail OAuth integration rows and (if google was
        // primary) flip auth_provider over to the new primary.
        await client.query(
          `UPDATE user_oauth_integrations
              SET revoked_at = NOW(),
                  access_token_ciphertext = NULL,
                  access_token_iv = NULL,
                  access_token_tag = NULL,
                  access_token_expires_at = NULL,
                  updated_at = NOW()
            WHERE user_id = $1
              AND provider = 'gmail'
              AND revoked_at IS NULL`,
          [req.user!.id],
        );
      } else {
        // provider === 'apple'
        await client.query(
          `UPDATE users SET apple_user_id = NULL, updated_at = NOW() WHERE id = $1`,
          [req.user!.id],
        );
      }

      if (newAuthProvider) {
        await client.query(
          `UPDATE users SET auth_provider = $1, updated_at = NOW() WHERE id = $2`,
          [newAuthProvider, req.user!.id],
        );
      }

      await client.query('COMMIT');
    } catch (txError) {
      await client.query('ROLLBACK');
      throw txError;
    } finally {
      client.release();
    }

    await AuditService.logFromRequest(req, 'user.update', {
      resourceType: 'user',
      resourceId: req.user!.id,
      description: `Unlinked ${provider} sign-in provider`,
      metadata: {
        provider,
        action: 'unlink',
        new_primary: newAuthProvider,
      },
    });

    logger.info(
      { userId: req.user!.id, provider, newPrimary: newAuthProvider },
      'Sign-in provider unlinked',
    );

    sendMessage(res, `${provider} sign-in provider unlinked.`);
  }),
);

// ─────────────────────────── Recipient gifts ───────────────────────────
//
// Powers the mobile "Recent gifts" screen — every partner gift the
// authenticated user has activated. Joins partners for display fields
// (company name, brand color, logo) and computes the post-activation
// expiry as `activated_at + premium_months` so the client can render a
// "premium days remaining" badge without re-deriving the schedule.
router.get('/me/gifts', asyncHandler(async (req, res) => {
  const result = await query(
    `SELECT g.id,
            g.status,
            g.is_activated,
            g.premium_months,
            g.custom_message,
            g.activated_at,
            g.expires_at,
            (g.activated_at + (g.premium_months || ' months')::interval) AS premium_expires_at,
            p.company_name AS partner_name,
            p.brand_color  AS partner_brand_color,
            p.logo_url     AS partner_logo_url
       FROM partner_gifts g
       JOIN partners p ON p.id = g.partner_id
      WHERE g.activated_user_id = $1
      ORDER BY g.activated_at DESC NULLS LAST, g.created_at DESC`,
    [req.user!.id],
  );

  sendSuccess(res, result.rows);
}));

export default router;
