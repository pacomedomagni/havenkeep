"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const redis_1 = require("redis");
const config_1 = require("../config");
const minio_1 = require("../config/minio");
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
// Basic health check
router.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        environment: config_1.config.env,
    });
});
// Detailed health check (admin only — exposes internal service status)
router.get('/health/detailed', auth_1.authenticate, auth_1.requireAdmin, async (req, res, next) => {
    try {
        const health = {
            status: 'ok',
            timestamp: new Date().toISOString(),
            uptime: process.uptime(),
            environment: config_1.config.env,
            checks: {},
        };
        // Database check
        try {
            await db_1.pool.query('SELECT 1');
            health.checks.database = { status: 'ok' };
        }
        catch (error) {
            health.status = 'degraded';
            health.checks.database = { status: 'error', message: error.message };
        }
        // Redis check
        let redis;
        try {
            redis = (0, redis_1.createClient)({ url: config_1.config.redis.url });
            await redis.connect();
            await redis.ping();
            health.checks.redis = { status: 'ok' };
        }
        catch (error) {
            health.status = 'degraded';
            health.checks.redis = { status: 'error', message: error.message };
        }
        finally {
            try {
                if (redis)
                    await redis.quit();
            }
            catch { /* ignore cleanup errors */ }
        }
        // MinIO health check
        try {
            await minio_1.minioClient.bucketExists(minio_1.BUCKET_NAME);
            health.checks.minio = { status: 'ok' };
        }
        catch (error) {
            health.status = 'degraded';
            health.checks.minio = { status: 'error', message: error.message };
        }
        const statusCode = health.status === 'ok' ? 200 : 503;
        res.status(statusCode).json(health);
    }
    catch (error) {
        next(error);
    }
});
// Readiness check (for Kubernetes)
router.get('/ready', async (req, res, next) => {
    try {
        await db_1.pool.query('SELECT 1');
        res.status(200).json({ ready: true });
    }
    catch (error) {
        res.status(503).json({ ready: false });
    }
});
// Liveness check (for Kubernetes)
router.get('/live', (req, res) => {
    res.status(200).json({ alive: true });
});
exports.default = router;
//# sourceMappingURL=health.js.map