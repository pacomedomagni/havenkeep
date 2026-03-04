import { Router } from 'express';
import { pool } from '../db';
import { createClient } from 'redis';
import { config } from '../config';
import { minioClient, BUCKET_NAME } from '../config/minio';
import { authenticate, requireAdmin } from '../middleware/auth';

const router = Router();

// Basic health check
router.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: config.env,
  });
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
      health.checks.database = { status: 'error', message: error.message };
    }

    // Redis check
    let redis;
    try {
      redis = createClient({ url: config.redis.url });
      await redis.connect();
      await redis.ping();
      health.checks.redis = { status: 'ok' };
    } catch (error: any) {
      health.status = 'degraded';
      health.checks.redis = { status: 'error', message: error.message };
    } finally {
      try { if (redis) await redis.quit(); } catch { /* ignore cleanup errors */ }
    }

    // MinIO health check
    try {
      await minioClient.bucketExists(BUCKET_NAME);
      health.checks.minio = { status: 'ok' };
    } catch (error: any) {
      health.status = 'degraded';
      health.checks.minio = { status: 'error', message: error.message };
    }

    const statusCode = health.status === 'ok' ? 200 : 503;
    res.status(statusCode).json(health);
  } catch (error) {
    next(error);
  }
});

// Readiness check (for Kubernetes)
router.get('/ready', async (req, res, next) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ ready: true });
  } catch (error) {
    res.status(503).json({ ready: false });
  }
});

// Liveness check (for Kubernetes)
router.get('/live', (req, res) => {
  res.status(200).json({ alive: true });
});

export default router;
