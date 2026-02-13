import { Request, Response, NextFunction } from 'express';
import { AuditAction } from '../services/audit.service';
/**
 * Middleware to automatically log API requests
 * Use this selectively on routes that need audit logging
 */
export declare function auditLog(action: AuditAction, options?: {
    resourceType?: string;
    getResourceId?: (req: Request) => string | undefined;
    getDescription?: (req: Request) => string | undefined;
    captureRequestBody?: boolean;
    captureResponseBody?: boolean;
}): (req: Request, res: Response, next: NextFunction) => Promise<void>;
/**
 * Middleware to log authentication attempts
 */
export declare function auditAuth(action: AuditAction): (req: Request, res: Response, next: NextFunction) => Promise<void>;
/**
 * Middleware to log security events
 */
export declare function logSecurityEvent(req: Request, action: AuditAction, description: string, severity?: 'warning' | 'error' | 'critical'): Promise<void>;
/**
 * Middleware to log resource changes (create, update, delete)
 * Typically used with route handlers where you have old/new values
 */
export declare function logResourceChange(params: {
    action: AuditAction;
    userId: string;
    userEmail?: string;
    resourceType: string;
    resourceId: string;
    description?: string;
    oldValue?: any;
    newValue?: any;
    changes?: Record<string, any>;
}): Promise<void>;
/**
 * Helper to calculate changes between old and new objects
 */
export declare function calculateChanges(oldValue: Record<string, any>, newValue: Record<string, any>): Record<string, {
    old: any;
    new: any;
}>;
//# sourceMappingURL=audit.d.ts.map