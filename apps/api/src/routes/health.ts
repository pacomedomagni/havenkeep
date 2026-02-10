import { Router } from 'express';
import { pool } from '../db';
import { createClient } from 'redis';
import { config } from '../config';

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

// Detailed health check
router.get('/health/detailed', async (req, res) => {
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
  try {
    const redis = createClient({ url: config.redis.url });
    await redis.connect();
    await redis.ping();
    await redis.quit();
    health.checks.redis = { status: 'ok' };
  } catch (error: any) {
    health.status = 'degraded';
    health.checks.redis = { status: 'error', message: error.message };
  }

  const statusCode = health.status === 'ok' ? 200 : 503;
  res.status(statusCode).json(health);
});

// Readiness check (for Kubernetes)
router.get('/ready', async (req, res) => {
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
