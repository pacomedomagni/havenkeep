"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const email_scanner_service_1 = require("../services/email-scanner.service");
const async_handler_1 = require("../utils/async-handler");
const joi_1 = __importDefault(require("joi"));
const validate_1 = require("../middleware/validate");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
const initiateScanSchema = joi_1.default.object({
    provider: joi_1.default.string().valid('gmail', 'outlook').required(),
    access_token: joi_1.default.string().required(),
    date_range_start: joi_1.default.date().iso().optional(),
    date_range_end: joi_1.default.date().iso().optional(),
});
/**
 * @route   POST /api/v1/email-scanner/scan
 * @desc    Initiate email scan for receipts
 * @access  Private
 */
router.post('/scan', (0, validate_1.validate)(initiateScanSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { provider, access_token, date_range_start, date_range_end } = req.body;
    const scan = await email_scanner_service_1.EmailScannerService.initiateScan(userId, provider, access_token, {
        dateRangeStart: date_range_start,
        dateRangeEnd: date_range_end,
    });
    res.status(202).json({
        success: true,
        data: scan,
        message: 'Email scan initiated. This may take a few minutes.',
    });
}));
/**
 * @route   GET /api/v1/email-scanner/scans/:id
 * @desc    Get email scan status
 * @access  Private
 */
router.get('/scans/:id', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const scan = await email_scanner_service_1.EmailScannerService.getScanStatus(req.params.id, userId);
    res.json({
        success: true,
        data: scan,
    });
}));
/**
 * @route   GET /api/v1/email-scanner/scans
 * @desc    Get user's email scan history
 * @access  Private
 */
router.get('/scans', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const scans = await email_scanner_service_1.EmailScannerService.getUserScans(userId);
    res.json({
        success: true,
        data: scans,
    });
}));
exports.default = router;
//# sourceMappingURL=email-scanner.js.map