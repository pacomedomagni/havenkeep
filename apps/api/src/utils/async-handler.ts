import { Request, Response, NextFunction } from 'express';

type AsyncFunction = (req: Request, res: Response, next: NextFunction) => Promise<unknown>;

/**
 * Wrap an async route handler so a thrown error / rejection flows to
 * Express's `next(err)`. The error handler middleware logs once — the prior
 * version logged here AND in errorHandler, producing duplicate entries that
 * polluted Loki (audit Ch11-I014).
 *
 * Sync throws inside an async function become rejections automatically; this
 * wrapper does NOT need a separate try/catch — the audit's worry (Ch11-I015)
 * is only when a wrapped handler is non-async (no implicit Promise wrap),
 * which the type signature forbids.
 */
export const asyncHandler = (fn: AsyncFunction) => {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};
