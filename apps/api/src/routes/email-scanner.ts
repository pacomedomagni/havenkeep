import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { EmailScannerService } from '../services/email-scanner.service';
import { asyncHandler } from '../utils/async-handler';
import Joi from 'joi';
import { validate } from '../middleware/validate';

const router = Router();

// All routes require authentication
router.use(authenticate);

const initiateScanSchema = Joi.object({
  provider: Joi.string().valid('gmail', 'outlook').required(),
  access_token: Joi.string().required(),
  date_range_start: Joi.date().iso().optional(),
  date_range_end: Joi.date().iso().optional(),
});

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
    const { provider, access_token, date_range_start, date_range_end } = req.body;

    const scan = await EmailScannerService.initiateScan(userId, provider, access_token, {
      dateRangeStart: date_range_start,
      dateRangeEnd: date_range_end,
    });

    res.status(202).json({
      success: true,
      data: scan,
      message: 'Email scan initiated. This may take a few minutes.',
    });
  })
);

/**
 * @route   GET /api/v1/email-scanner/scans/:id
 * @desc    Get email scan status
 * @access  Private
 */
router.get(
  '/scans/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scan = await EmailScannerService.getScanStatus(req.params.id, userId);

    res.json({
      success: true,
      data: scan,
    });
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

    res.json({
      success: true,
      data: scans,
    });
  })
);

export default router;
