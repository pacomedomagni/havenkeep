import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { StatsService } from '../services/stats.service';
import { asyncHandler } from '../utils/async-handler';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * @route   GET /api/v1/stats/dashboard
 * @desc    Get dashboard statistics
 * @access  Private
 */
router.get(
  '/dashboard',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const stats = await StatsService.getDashboardStats(userId);

    res.json({
      success: true,
      data: stats,
    });
  })
);

/**
 * @route   GET /api/v1/stats/health-score
 * @desc    Get health score and breakdown
 * @access  Private
 */
router.get(
  '/health-score',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const breakdown = await StatsService.getHealthScoreBreakdown(userId);

    res.json({
      success: true,
      data: breakdown,
    });
  })
);

/**
 * @route   POST /api/v1/stats/health-score/calculate
 * @desc    Recalculate health score
 * @access  Private
 */
router.post(
  '/health-score/calculate',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const score = await StatsService.calculateHealthScore(userId);

    res.json({
      success: true,
      data: { score },
      message: 'Health score recalculated',
    });
  })
);

/**
 * @route   GET /api/v1/stats/analytics
 * @desc    Get user analytics
 * @access  Private
 */
router.get(
  '/analytics',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const analytics = await StatsService.getUserAnalytics(userId);

    res.json({
      success: true,
      data: analytics,
    });
  })
);

/**
 * @route   GET /api/v1/stats/items-needing-attention
 * @desc    Get items that need attention (expiring warranties, etc.)
 * @access  Private
 */
router.get(
  '/items-needing-attention',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const items = await StatsService.getItemsNeedingAttention(userId);

    res.json({
      success: true,
      data: items,
    });
  })
);

/**
 * @route   POST /api/v1/stats/track-engagement
 * @desc    Track user engagement event
 * @access  Private
 */
router.post(
  '/track-engagement',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { type, session_duration } = req.body;

    await StatsService.trackEngagement(userId, {
      type,
      sessionDuration: session_duration,
    });

    res.json({
      success: true,
      message: 'Engagement tracked',
    });
  })
);

/**
 * @route   POST /api/v1/stats/track-feature
 * @desc    Track feature usage
 * @access  Private
 */
router.post(
  '/track-feature',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { feature } = req.body;

    await StatsService.trackFeatureUsage(userId, feature);

    res.json({
      success: true,
      message: 'Feature usage tracked',
    });
  })
);

export default router;
