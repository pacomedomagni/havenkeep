import { Router } from 'express';
import Joi from 'joi';
import { authenticate } from '../middleware/auth';
import { authRateLimiter } from '../middleware/rateLimiter';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';
import { AppError } from '../utils/errors';
import { MfaService } from '../services/mfa.service';
import { logger } from '../utils/logger';

/**
 * S-C2 (audit): MFA enrollment + factor management.
 *
 * The login challenge endpoint (/auth/mfa/challenge) lives in routes/auth.ts
 * because it consumes the short-lived MFA challenge token minted in
 * /auth/login when the user has any verified factor — colocating it
 * with the rest of the auth flow keeps the lifecycle obvious.
 *
 * All routes here require an existing access token (the user is already
 * authenticated via password or OAuth) — MFA is enrolled / managed AFTER
 * sign-in, then enforced on subsequent sign-ins.
 */
const router = Router();

router.use(authenticate);

const enrollSchema = Joi.object({
  // Optional human-readable label shown in the authenticator app and in
  // the user's MFA settings page.
  label: Joi.string().min(1).max(64).optional(),
});

const verifyCodeSchema = Joi.object({
  code: Joi.string().min(6).max(64).required(),
});

/**
 * POST /api/v1/mfa/totp/enroll
 *
 * Returns the secret (raw + otpauth URL + QR data URL) and 10 backup codes.
 * The plaintext secret + backup codes are returned ONCE — the client must
 * surface them to the user immediately. Calling this again before
 * verification rolls a fresh secret + backup codes.
 */
router.post(
  '/totp/enroll',
  authRateLimiter,
  validate(enrollSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const email = req.user!.email;
    const label = (req.body?.label as string | undefined) ?? email;

    const result = await MfaService.enrollTotp(userId, label);

    logger.info({ userId, factorId: result.factorId }, 'MFA TOTP enrollment started');

    sendSuccess(res, {
      factor_id: result.factorId,
      secret: result.secret,
      otpauth_url: result.otpauthUrl,
      qr_code_data_url: result.qrCodeDataUrl,
      backup_codes: result.backupCodes,
    });
  }),
);

/**
 * POST /api/v1/mfa/totp/verify
 *
 * Submit the first TOTP code from the authenticator app to flip the
 * factor from un-verified to verified. Until this succeeds the factor
 * is NEVER honored at login — defends against an attacker who has the
 * password completing enrollment + login in one step.
 */
router.post(
  '/totp/verify',
  authRateLimiter,
  validate(verifyCodeSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { code } = req.body;
    await MfaService.verifyEnrollmentCode(userId, code);
    logger.info({ userId }, 'MFA TOTP factor verified and active');
    sendMessage(res, 'TOTP factor verified. MFA is now active for this account.');
  }),
);

/**
 * POST /api/v1/mfa/totp/disable
 *
 * Disable the TOTP factor. Requires a current TOTP code or unused backup
 * code so an attacker with only the password can't remove MFA.
 */
router.post(
  '/totp/disable',
  authRateLimiter,
  validate(verifyCodeSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { code } = req.body;
    await MfaService.disableTotp(userId, code);
    sendMessage(res, 'TOTP factor disabled.');
  }),
);

/**
 * GET /api/v1/mfa/status
 *
 * Returns whether the user has any verified factor on file. Used by the
 * mobile + dashboard UIs to render the "MFA enabled" banner and gate
 * the "disable MFA" button.
 */
router.get(
  '/status',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const status = await MfaService.getStatus(userId);
    sendSuccess(res, {
      has_verified_factor: status.hasVerifiedFactor,
      factor_types: status.factorTypes,
    });
  }),
);

export default router;
