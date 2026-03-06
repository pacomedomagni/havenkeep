import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { StatsService } from '../services/stats.service';
import { asyncHandler } from '../utils/async-handler';
import { validate } from '../middleware/validate';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { trackEngagementSchema, trackFeatureSchema } from '../validators';
import { sendSuccess, sendMessage } from '../utils/response';

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

    sendSuccess(res, stats);
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

    sendSuccess(res, breakdown);
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

    sendSuccess(res, { score }, { message: 'Health score recalculated' });
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

    sendSuccess(res, analytics);
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

    sendSuccess(res, items);
  })
);

/**
 * @route   POST /api/v1/stats/track-engagement
 * @desc    Track user engagement event
 * @access  Private
 */
router.post(
  '/track-engagement',
  writeRateLimiter,
  validate(trackEngagementSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { type, sessionDuration } = req.body;

    await StatsService.trackEngagement(userId, {
      type,
      sessionDuration,
    });

    sendMessage(res, 'Engagement tracked');
  })
);

/**
 * @route   POST /api/v1/stats/track-feature
 * @desc    Track feature usage
 * @access  Private
 */
router.post(
  '/track-feature',
  writeRateLimiter,
  validate(trackFeatureSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { feature } = req.body;

    await StatsService.trackFeatureUsage(userId, feature);

    sendMessage(res, 'Feature usage tracked');
  })
);

export default router;
