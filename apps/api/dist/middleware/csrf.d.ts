import { Request, Response, NextFunction } from 'express';
export declare function setCsrfToken(req: Request, res: Response, next: NextFunction): void;
/**
 * Validate that the CSRF token in the request header matches the one in the cookie.
 * Only applies to state-changing methods (POST, PUT, PATCH, DELETE).
 * GET/HEAD/OPTIONS are safe methods and skip validation.
 */
export declare function validateCsrfToken(req: Request, res: Response, next: NextFunction): void | Response<any, Record<string, any>>;
//# sourceMappingURL=csrf.d.ts.map