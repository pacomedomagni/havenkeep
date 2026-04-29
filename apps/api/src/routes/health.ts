import { Router } from 'express';
import { pool } from '../db';
import { config } from '../config';
import { minioClient, BUCKET_NAME } from '../config/minio';
import { authenticate, requireAdmin } from '../middleware/auth';
import { getRedisClient } from '../utils/redis';
import { isShuttingDown } from '../utils/lifecycle';

const router = Router();

/**
 * F102: scrub error messages before they leave the process. Connection
 * strings, S3 secret keys, and JWT secrets sometimes leak into the
 * underlying library's error.message; mask anything that looks like a
 * key=value pair with a credential-shaped value.
 */
function safeMessage(err: any): string {
  const raw = String(err?.message ?? err ?? 'unknown');
  return raw
    .replace(/(password|pass|pwd|token|secret|key)=([^\s&]+)/gi, '$1=[REDACTED]')
    .replace(/postgres(?:ql)?:\/\/[^\s]+/gi, 'postgres://[REDACTED]')
    .replace(/redis(?:s)?:\/\/[^\s]+/gi, 'redis://[REDACTED]');
}

// F099: /health pings the database. Was a no-op JSON before — load balancers
// would happily route to a pod whose DB pool was wedged.
router.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: config.env,
    });
  } catch (err: any) {
    res.status(503).json({
      status: 'degraded',
      timestamp: new Date().toISOString(),
      environment: config.env,
      error: safeMessage(err),
    });
  }
});

// Detailed health check (admin only — exposes internal service status)
router.get('/health/detailed', authenticate, requireAdmin, async (req, res, next) => {
  try {
    const health: any = {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: config.env,
      checks: {},
    };

    // Database check
    try {
      await pool.query('SELECT 1');
      health.checks.database = { status: 'ok' };
    } catch (error: any) {
      health.status = 'degraded';
      health.checks.database = { status: 'error', message: safeMessage(error) };
    }

    // F101: reuse the shared Redis client. The previous implementation
    // opened a brand-new connection on every health request, blowing
    // through Redis's connection cap during scraper bursts.
    try {
      const redis = await getRedisClient();
      await redis.ping();
      health.checks.redis = { status: 'ok' };
    } catch (error: any) {
      health.status = 'degraded';
      health.checks.redis = { status: 'error', message: safeMessage(error) };
    }

    // MinIO health check
    try {
      await minioClient.bucketExists(BUCKET_NAME);
      health.checks.minio = { status: 'ok' };
    } catch (error: any) {
      health.status = 'degraded';
      health.checks.minio = { status: 'error', message: safeMessage(error) };
    }

    const statusCode = health.status === 'ok' ? 200 : 503;
    res.status(statusCode).json(health);
  } catch (error) {
    next(error);
  }
});

// F100: readiness pings DB AND Redis. MinIO is treated as soft-fail (object
// storage outage shouldn't take the whole pod out of rotation; uploads
// degrade independently).
router.get('/ready', async (req, res) => {
  // 2.7: once shutdown begins we deregister from the LB IMMEDIATELY by
  // returning 503. The 5s drain in index.ts gives the LB a window to
  // notice and stop routing new traffic before server.close() runs.
  if (isShuttingDown()) {
    return res.status(503).json({ ready: false, reason: 'shutting-down' });
  }
  try {
    await pool.query('SELECT 1');
    try {
      const redis = await getRedisClient();
      await redis.ping();
    } catch (err: any) {
      // Redis required for rate limiting + token blacklist — degrade.
      return res.status(503).json({ ready: false, reason: 'redis', message: safeMessage(err) });
    }
    return res.status(200).json({ ready: true });
  } catch (err: any) {
    return res.status(503).json({ ready: false, reason: 'database', message: safeMessage(err) });
  }
});

// Liveness check (for Kubernetes)
router.get('/live', (req, res) => {
  res.status(200).json({ alive: true });
});

export default router;
