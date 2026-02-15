import { Request, Response, NextFunction } from 'express';
import { AuditService, AuditAction } from '../services/audit.service';
import { logger } from '../utils/logger';

/**
 * Middleware to automatically log API requests
 * Use this selectively on routes that need audit logging
 */
export function auditLog(action: AuditAction, options?: {
  resourceType?: string;
  getResourceId?: (req: Request) => string | undefined;
  getDescription?: (req: Request) => string | undefined;
  captureRequestBody?: boolean;
  captureResponseBody?: boolean;
}) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const user = (req as any).user;
    const startTime = Date.now();

    // Capture original res.json to intercept response
    const originalJson = res.json.bind(res);
    let responseBody: any;

    res.json = function (body: any) {
      responseBody = body;
      return originalJson(body);
    };

    // Wait for response to finish
    res.on('finish', () => {
      const metadata: Record<string, any> = {
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

      // Wrap in a caught promise to prevent unhandled rejection from
      // crashing the process if AuditService.logFromRequest() throws.
      AuditService.logFromRequest(req, action, {
        resourceType: options?.resourceType,
        resourceId,
        description,
        metadata,
        success: res.statusCode >= 200 && res.statusCode < 400,
        errorMessage: res.statusCode >= 400 ? responseBody?.error || responseBody?.message : undefined,
      }).catch((error) => {
        // Don't fail the request if audit logging fails
        logger.error({ error }, 'Audit logging error');
      });
    });

    next();
  };
}

/**
 * Middleware to log authentication attempts
 */
export function auditAuth(action: AuditAction) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const originalJson = res.json.bind(res);

    res.json = function (body: any) {
      // Log after response is sent
      setImmediate(async () => {
        try {
          const user = (req as any).user;
          const email = req.body?.email || user?.email;

          await AuditService.logAuth({
            action,
            userId: user?.id,
            email,
            ipAddress: AuditService['getIpAddress'](req),
            userAgent: req.get('user-agent'),
            success: res.statusCode >= 200 && res.statusCode < 400,
            errorMessage: res.statusCode >= 400 ? body?.error || body?.message : undefined,
            metadata: {
              status_code: res.statusCode,
            },
          });
        } catch (error) {
          logger.error({ error }, 'Auth audit logging error');
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
export async function logSecurityEvent(
  req: Request,
  action: AuditAction,
  description: string,
  severity: 'warning' | 'error' | 'critical' = 'warning'
): Promise<void> {
  const user = (req as any).user;

  try {
    await AuditService.logSecurity({
      action,
      userId: user?.id,
      email: user?.email,
      ipAddress: AuditService['getIpAddress'](req),
      userAgent: req.get('user-agent'),
      description,
      severity,
      metadata: {
        endpoint: req.path,
        method: req.method,
      },
    });
  } catch (error) {
    logger.error({ error }, 'Security audit logging error');
  }
}

/**
 * Middleware to log resource changes (create, update, delete)
 * Typically used with route handlers where you have old/new values
 */
export async function logResourceChange(params: {
  action: AuditAction;
  userId: string;
  userEmail?: string;
  resourceType: string;
  resourceId: string;
  description?: string;
  oldValue?: any;
  newValue?: any;
  changes?: Record<string, any>;
}): Promise<void> {
  try {
    await AuditService.logResourceChange(params);
  } catch (error) {
    logger.error({ error }, 'Resource change audit logging error');
  }
}

/**
 * Helper to calculate changes between old and new objects
 */
export function calculateChanges(
  oldValue: Record<string, any>,
  newValue: Record<string, any>
): Record<string, { old: any; new: any }> {
  const changes: Record<string, { old: any; new: any }> = {};

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
