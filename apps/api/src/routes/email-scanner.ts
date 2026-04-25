import { Router } from 'express';
import { authenticate, requirePremium } from '../middleware/auth';
import { EmailScannerService } from '../services/email-scanner.service';
import { asyncHandler } from '../utils/async-handler';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { uuidParamSchema } from '../validators';
import { sendSuccess, sendMessage } from '../utils/response';
import { AppError } from '../utils/errors';
import { isOAuthEncryptionConfigured } from '../utils/oauth-encryption';

const router = Router();

// All routes require authentication and premium plan
router.use(authenticate);
router.use(requirePremium);

/**
 * Initiate-scan body. The mobile/web client must send the OAuth
 * authorization `code` and the `redirect_uri` it used to obtain that code.
 * The server completes the code exchange — clients NEVER send a raw access
 * token. Any incoming `accessToken` / `access_token` field is rejected.
 */
// Snake_case API. Legacy `access_token` / `accessToken` fields are
// explicitly forbidden so a client that hasn't been updated fails loudly
// instead of silently sending a raw OAuth token the server no longer
// accepts.
const initiateScanSchema = Joi.object({
  provider: Joi.string().valid('gmail', 'outlook').required(),
  code: Joi.string().min(1).max(4096).required(),
  redirect_uri: Joi.string().uri({ scheme: ['http', 'https'] }).required(),
  date_range_start: Joi.date().iso().optional(),
  date_range_end: Joi.date().iso().optional(),
  access_token: Joi.any().forbidden(),
  accessToken: Joi.any().forbidden(),
})
  .rename('redirectUri', 'redirect_uri', { ignoreUndefined: true, override: false })
  .rename('dateRangeStart', 'date_range_start', { ignoreUndefined: true, override: false })
  .rename('dateRangeEnd', 'date_range_end', { ignoreUndefined: true, override: false });

const reviewActionSchema = Joi.object({
  reason: Joi.string().max(500).optional(),
});

const providerQuerySchema = Joi.object({
  provider: Joi.string().valid('gmail', 'outlook').optional(),
});

/**
 * @route   POST /api/v1/email-scanner/scan
 * @desc    Exchange an OAuth code for tokens and start a scan
 * @access  Private (premium)
 */
router.post(
  '/scan',
  validate(initiateScanSchema),
  asyncHandler(async (req, res) => {
    if (!isOAuthEncryptionConfigured()) {
      throw new AppError('OAuth integration not configured', 503);
    }

    const userId = req.user!.id;
    const { provider, code, redirect_uri, date_range_start, date_range_end } = req.body;

    const scan = await EmailScannerService.initiateScan(userId, provider, code, redirect_uri, {
      dateRangeStart: date_range_start,
      dateRangeEnd: date_range_end,
    });

    sendSuccess(res, scan, { status: 202, message: 'Email scan initiated. This may take a few minutes.' });
  })
);

/**
 * @route   GET /api/v1/email-scanner/scans/:id
 * @desc    Get email scan status
 * @access  Private
 */
router.get(
  '/scans/:id',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scan = await EmailScannerService.getScanStatus(req.params.id, userId);

    sendSuccess(res, scan);
  })
);

/**
 * @route   GET /api/v1/email-scanner/scans
 * @desc    Get user's email scan history
 * @access  Private
 */
router.get(
  '/scans',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scans = await EmailScannerService.getUserScans(userId);

    sendSuccess(res, scans);
  })
);

/**
 * @route   GET /api/v1/email-scanner/review
 * @desc    List pending review-queue rows for the authenticated user
 * @access  Private
 */
router.get(
  '/review',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const rows = await EmailScannerService.listPendingReviews(userId);
    sendSuccess(res, rows);
  })
);

/**
 * @route   POST /api/v1/email-scanner/review/:id/approve
 * @desc    Approve a queued review row, creating the underlying item
 * @access  Private
 */
router.post(
  '/review/:id/approve',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const result = await EmailScannerService.approveReview(userId, req.params.id);
    sendSuccess(res, result, { status: 201, message: 'Review approved and item created' });
  })
);

/**
 * @route   POST /api/v1/email-scanner/review/:id/reject
 * @desc    Reject a queued review row
 * @access  Private
 */
router.post(
  '/review/:id/reject',
  validate(uuidParamSchema, 'params'),
  validate(reviewActionSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await EmailScannerService.rejectReview(userId, req.params.id, req.body?.reason);
    sendMessage(res, 'Review rejected');
  })
);

/**
 * @route   POST /api/v1/email-scanner/scans/:id/cancel
 * @desc    Cancel an in-flight scan; flips status to failed with a clear
 *          "cancelled" message so the mobile progress dialog can detach.
 * @access  Private
 */
router.post(
  '/scans/:id/cancel',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scan = await EmailScannerService.cancelScan(req.params.id, userId);
    sendSuccess(res, scan, { message: 'Scan cancelled' });
  })
);

/**
 * @route   GET /api/v1/email-scanner/integrations
 * @desc    List the user's active OAuth integrations (provider, email,
 *          granted scopes). Powers the settings disconnect + scopes UI.
 * @access  Private
 */
router.get(
  '/integrations',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const integrations = await EmailScannerService.listIntegrations(userId);
    sendSuccess(res, integrations);
  })
);

/**
 * @route   DELETE /api/v1/email-scanner/integrations
 * @desc    Revoke OAuth integrations. Optional `?provider=gmail|outlook`
 *          query param targets a single provider; otherwise revokes all.
 * @access  Private
 */
router.delete(
  '/integrations',
  validate(providerQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const provider = (req.query.provider as 'gmail' | 'outlook' | undefined) || undefined;
    await EmailScannerService.revokeIntegration(userId, provider);
    sendMessage(res, 'Integration revoked');
  })
);

export default router;
