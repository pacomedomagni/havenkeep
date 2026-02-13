import { Request, Response, NextFunction } from 'express';
export declare function generateCsrfToken(): string;
export declare function csrfProtection(req: Request, res: Response, next: NextFunction): void;
export declare function setCsrfToken(req: Request, res: Response, next: NextFunction): void;
//# sourceMappingURL=csrf.d.ts.map