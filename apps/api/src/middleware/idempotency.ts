import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { pool } from '../db';
import { AppError } from '../utils/errors';
import { logger } from '../utils/logger';

// S2-D / S2-E / S2-C: generic Idempotency-Key middleware. Routes opt in
// per-handler with `idempotency('warranty-claims:create')` etc. — the
// `routeKey` scopes the cache so the same client-supplied UUID can be
// reused safely across endpoints.
//
// Behavior on the request side:
//   1. Read `Idempotency-Key` header.
//   2. If absent, pass through (idempotency is opt-in for the client).
//   3. If present, look up `(user_id, routeKey, key)`. Hit + matching
//      body hash → replay the cached response and SHORT-CIRCUIT before
//      the route handler runs.
//   4. Hit + different body hash → 409 (RFC 9110 §17).
//   5. Miss → continue. We attach the key + body hash to `res.locals`
//      and wrap `res.json` so the *first* successful response (2xx)
//      is persisted before being sent.
//
// Persisted writes are best-effort; a DB error during persist is logged
// and swallowed so the user-facing response is never delayed by it. The
// downside is a near-simultaneous double-send could both proceed once;
// the route handler should still rely on its own DB-level uniqueness
// (`ON CONFLICT DO NOTHING`) for true idempotence.

export function idempotency(routeKey: string) {
  return async function idempotencyMiddleware(
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    const userId = (req as any).user?.id as string | undefined;
    const headerVal = req.headers['idempotency-key'] || req.headers['Idempotency-Key'];
    const idempotencyKey = Array.isArray(headerVal) ? headerVal[0] : headerVal;

    if (!userId || !idempotencyKey) {
      next();
      return;
    }

    // Hash the request body deterministically. JSON.stringify on an Express
    // body parsed by `express.json()` is good enough for our purposes —
    // routes never mutate the body before the middleware runs.
    const bodyForHash = JSON.stringify(req.body ?? {});
    const requestHash = crypto.createHash('sha256').update(bodyForHash).digest('hex');

    try {
      const prior = await pool.query(
        `SELECT request_hash, response_status, response_json
           FROM request_idempotency
          WHERE user_id = $1 AND route_key = $2 AND idempotency_key = $3
            AND expires_at > NOW()`,
        [userId, routeKey, idempotencyKey],
      );
      if (prior.rows.length > 0) {
        const row = prior.rows[0];
        if (row.request_hash !== requestHash) {
          throw new AppError(
            'Idempotency-Key reused with a different request body',
            409,
          );
        }
        res.status(row.response_status).json(row.response_json);
        return;
      }
    } catch (err) {
      if (err instanceof AppError) {
        next(err);
        return;
      }
      logger.warn({ err, routeKey }, 'Idempotency lookup failed; continuing');
    }

    // Miss — wrap res.json so the first 2xx response is persisted.
    const originalJson = res.json.bind(res);
    let persisted = false;
    res.json = function (body: any): Response {
      const status = res.statusCode || 200;
      if (!persisted && status >= 200 && status < 300) {
        persisted = true;
        // Fire-and-forget; failures must not block the response.
        pool
          .query(
            `INSERT INTO request_idempotency
                (user_id, route_key, idempotency_key, request_hash,
                 response_status, response_json)
              VALUES ($1, $2, $3, $4, $5, $6)
              ON CONFLICT (user_id, route_key, idempotency_key) DO NOTHING`,
            [userId, routeKey, idempotencyKey, requestHash, status, JSON.stringify(body)],
          )
          .catch((err) => {
            logger.warn({ err, routeKey }, 'Idempotency persist failed');
          });
      }
      return originalJson(body);
    };

    next();
  };
}
