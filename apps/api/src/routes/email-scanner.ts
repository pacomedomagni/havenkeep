import { Router } from 'express';
import { authenticate, requirePremium } from '../middleware/auth';
import { EmailScannerService } from '../services/email-scanner.service';
import { asyncHandler } from '../utils/async-handler';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { uuidParamSchema } from '../validators';
import { sendSuccess } from '../utils/response';

const router = Router();

// All routes require authentication and premium plan
router.use(authenticate);
router.use(requirePremium);

const initiateScanSchema = Joi.object({
  provider: Joi.string().valid('gmail', 'outlook').required(),
  accessToken: Joi.string().required(),
  dateRangeStart: Joi.date().iso().optional(),
  dateRangeEnd: Joi.date().iso().optional(),
})
  // Accept snake_case from mobile clients
  .rename('access_token', 'accessToken', { ignoreUndefined: true, override: false })
  .rename('date_range_start', 'dateRangeStart', { ignoreUndefined: true, override: false })
  .rename('date_range_end', 'dateRangeEnd', { ignoreUndefined: true, override: false });

/**
 * @route   POST /api/v1/email-scanner/scan
 * @desc    Initiate email scan for receipts
 * @access  Private
 */
router.post(
  '/scan',
  validate(initiateScanSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { provider, accessToken, dateRangeStart, dateRangeEnd } = req.body;

    const scan = await EmailScannerService.initiateScan(userId, provider, accessToken, {
      dateRangeStart,
      dateRangeEnd,
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

export default router;
