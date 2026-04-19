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
const validators_1 = require("../validators");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
// All routes require authentication and premium plan
router.use(auth_1.authenticate);
router.use(auth_1.requirePremium);
const initiateScanSchema = joi_1.default.object({
    provider: joi_1.default.string().valid('gmail', 'outlook').required(),
    accessToken: joi_1.default.string().required(),
    dateRangeStart: joi_1.default.date().iso().optional(),
    dateRangeEnd: joi_1.default.date().iso().optional(),
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
router.post('/scan', (0, validate_1.validate)(initiateScanSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { provider, accessToken, dateRangeStart, dateRangeEnd } = req.body;
    const scan = await email_scanner_service_1.EmailScannerService.initiateScan(userId, provider, accessToken, {
        dateRangeStart,
        dateRangeEnd,
    });
    (0, response_1.sendSuccess)(res, scan, { status: 202, message: 'Email scan initiated. This may take a few minutes.' });
}));
/**
 * @route   GET /api/v1/email-scanner/scans/:id
 * @desc    Get email scan status
 * @access  Private
 */
router.get('/scans/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const scan = await email_scanner_service_1.EmailScannerService.getScanStatus(req.params.id, userId);
    (0, response_1.sendSuccess)(res, scan);
}));
/**
 * @route   GET /api/v1/email-scanner/scans
 * @desc    Get user's email scan history
 * @access  Private
 */
router.get('/scans', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const scans = await email_scanner_service_1.EmailScannerService.getUserScans(userId);
    (0, response_1.sendSuccess)(res, scans);
}));
exports.default = router;
//# sourceMappingURL=email-scanner.js.map