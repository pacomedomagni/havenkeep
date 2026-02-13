"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const stats_service_1 = require("../services/stats.service");
const async_handler_1 = require("../utils/async-handler");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   GET /api/v1/stats/dashboard
 * @desc    Get dashboard statistics
 * @access  Private
 */
router.get('/dashboard', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const stats = await stats_service_1.StatsService.getDashboardStats(userId);
    res.json({
        success: true,
        data: stats,
    });
}));
/**
 * @route   GET /api/v1/stats/health-score
 * @desc    Get health score and breakdown
 * @access  Private
 */
router.get('/health-score', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const breakdown = await stats_service_1.StatsService.getHealthScoreBreakdown(userId);
    res.json({
        success: true,
        data: breakdown,
    });
}));
/**
 * @route   POST /api/v1/stats/health-score/calculate
 * @desc    Recalculate health score
 * @access  Private
 */
router.post('/health-score/calculate', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const score = await stats_service_1.StatsService.calculateHealthScore(userId);
    res.json({
        success: true,
        data: { score },
        message: 'Health score recalculated',
    });
}));
/**
 * @route   GET /api/v1/stats/analytics
 * @desc    Get user analytics
 * @access  Private
 */
router.get('/analytics', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const analytics = await stats_service_1.StatsService.getUserAnalytics(userId);
    res.json({
        success: true,
        data: analytics,
    });
}));
/**
 * @route   GET /api/v1/stats/items-needing-attention
 * @desc    Get items that need attention (expiring warranties, etc.)
 * @access  Private
 */
router.get('/items-needing-attention', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const items = await stats_service_1.StatsService.getItemsNeedingAttention(userId);
    res.json({
        success: true,
        data: items,
    });
}));
/**
 * @route   POST /api/v1/stats/track-engagement
 * @desc    Track user engagement event
 * @access  Private
 */
router.post('/track-engagement', (0, validate_1.validate)(validators_1.trackEngagementSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { type, session_duration } = req.body;
    await stats_service_1.StatsService.trackEngagement(userId, {
        type,
        sessionDuration: session_duration,
    });
    res.json({
        success: true,
        message: 'Engagement tracked',
    });
}));
/**
 * @route   POST /api/v1/stats/track-feature
 * @desc    Track feature usage
 * @access  Private
 */
router.post('/track-feature', (0, validate_1.validate)(validators_1.trackFeatureSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { feature } = req.body;
    await stats_service_1.StatsService.trackFeatureUsage(userId, feature);
    res.json({
        success: true,
        message: 'Feature usage tracked',
    });
}));
exports.default = router;
//# sourceMappingURL=stats.js.map