"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.auditLog = auditLog;
exports.auditAuth = auditAuth;
exports.logSecurityEvent = logSecurityEvent;
exports.logResourceChange = logResourceChange;
exports.calculateChanges = calculateChanges;
const audit_service_1 = require("../services/audit.service");
/**
 * Middleware to automatically log API requests
 * Use this selectively on routes that need audit logging
 */
function auditLog(action, options) {
    return async (req, res, next) => {
        const user = req.user;
        const startTime = Date.now();
        // Capture original res.json to intercept response
        const originalJson = res.json.bind(res);
        let responseBody;
        res.json = function (body) {
            responseBody = body;
            return originalJson(body);
        };
        // Wait for response to finish
        res.on('finish', async () => {
            try {
                const metadata = {
                    duration_ms: Date.now() - startTime,
                    status_code: res.statusCode,
                };
                // Capture request body if enabled (be careful with sensitive data)
                if (options?.captureRequestBody && req.body) {
                    // Sanitize sensitive fields
                    const sanitizedBody = { ...req.body };
                    delete sanitizedBody.password;
                    delete sanitizedBody.password_hash;
                    delete sanitizedBody.token;
                    delete sanitizedBody.refresh_token;
                    metadata.request_body = sanitizedBody;
                }
                // Capture response body if enabled
                if (options?.captureResponseBody && responseBody) {
                    metadata.response_body = responseBody;
                }
                const resourceId = options?.getResourceId?.(req);
                const description = options?.getDescription?.(req);
                await audit_service_1.AuditService.logFromRequest(req, action, {
                    resourceType: options?.resourceType,
                    resourceId,
                    description,
                    metadata,
                    success: res.statusCode >= 200 && res.statusCode < 400,
                    errorMessage: res.statusCode >= 400 ? responseBody?.error || responseBody?.message : undefined,
                });
            }
            catch (error) {
                // Don't fail the request if audit logging fails
                console.error('Audit logging error:', error);
            }
        });
        next();
    };
}
/**
 * Middleware to log authentication attempts
 */
function auditAuth(action) {
    return async (req, res, next) => {
        const originalJson = res.json.bind(res);
        res.json = function (body) {
            // Log after response is sent
            setImmediate(async () => {
                try {
                    const user = req.user;
                    const email = req.body?.email || user?.email;
                    await audit_service_1.AuditService.logAuth({
                        action,
                        userId: user?.id,
                        email,
                        ipAddress: audit_service_1.AuditService['getIpAddress'](req),
                        userAgent: req.get('user-agent'),
                        success: res.statusCode >= 200 && res.statusCode < 400,
                        errorMessage: res.statusCode >= 400 ? body?.error || body?.message : undefined,
                        metadata: {
                            status_code: res.statusCode,
                        },
                    });
                }
                catch (error) {
                    console.error('Auth audit logging error:', error);
                }
            });
            return originalJson(body);
        };
        next();
    };
}
/**
 * Middleware to log security events
 */
async function logSecurityEvent(req, action, description, severity = 'warning') {
    const user = req.user;
    try {
        await audit_service_1.AuditService.logSecurity({
            action,
            userId: user?.id,
            email: user?.email,
            ipAddress: audit_service_1.AuditService['getIpAddress'](req),
            userAgent: req.get('user-agent'),
            description,
            severity,
            metadata: {
                endpoint: req.path,
                method: req.method,
            },
        });
    }
    catch (error) {
        console.error('Security audit logging error:', error);
    }
}
/**
 * Middleware to log resource changes (create, update, delete)
 * Typically used with route handlers where you have old/new values
 */
async function logResourceChange(params) {
    try {
        await audit_service_1.AuditService.logResourceChange(params);
    }
    catch (error) {
        console.error('Resource change audit logging error:', error);
    }
}
/**
 * Helper to calculate changes between old and new objects
 */
function calculateChanges(oldValue, newValue) {
    const changes = {};
    // Check all keys in new value
    for (const key in newValue) {
        if (oldValue[key] !== newValue[key]) {
            // Don't log sensitive fields
            if (['password', 'password_hash', 'token', 'secret'].includes(key)) {
                continue;
            }
            changes[key] = {
                old: oldValue[key],
                new: newValue[key],
            };
        }
    }
    // Check for deleted keys
    for (const key in oldValue) {
        if (!(key in newValue) && oldValue[key] !== undefined) {
            changes[key] = {
                old: oldValue[key],
                new: undefined,
            };
        }
    }
    return changes;
}
//# sourceMappingURL=audit.js.map