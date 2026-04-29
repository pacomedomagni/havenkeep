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

// S-HI-04: cap the persisted response body. Most replay-eligible
// responses are small (a created-row JSON, a deleted-confirmation
// message); anything bigger is almost always a multi-row upload that
// the client can refetch from the canonical list endpoint. Capping
// here prevents an attacker who can hit any idempotency-protected
// route from filling the table with megabyte-sized rows.
const MAX_RESPONSE_BYTES = 32 * 1024;

// S-ME-11: per-route TTL override. Default 24h; sensitive routes
// (delete account, change password) can opt to a 5min replay window.
const DEFAULT_TTL_SECONDS = 24 * 60 * 60;

export function idempotency(routeKey: string, opts: { ttlSeconds?: number } = {}) {
  const ttlSeconds = opts.ttlSeconds ?? DEFAULT_TTL_SECONDS;
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
        // 3.18: serialize defensively. A handler that returns an object
        // with a circular ref (or a BigInt) would throw inside
        // `JSON.stringify` here and break the response — but the actual
        // response payload still goes out via `originalJson(body)` at
        // the bottom of this function. The persist is a best-effort
        // cache; a serialize failure logs + skips, the response stays
        // intact.
        let serialized: string | null = null;
        try {
          serialized = JSON.stringify(body);
        } catch (err) {
          logger.warn(
            { err, routeKey },
            'Idempotency serialize failed (circular ref or unsupported type); skipping persist',
          );
        }
        if (serialized !== null) {
          // S-HI-04: cap response body. Skip persisting if too large;
          // the client can always refetch from the canonical list
          // endpoint.
          if (serialized.length > MAX_RESPONSE_BYTES) {
            logger.warn(
              { routeKey, bytes: serialized.length, cap: MAX_RESPONSE_BYTES },
              'Idempotency response too large; skipping persist',
            );
          } else {
            // Fire-and-forget; failures must not block the response.
            pool
              .query(
                `INSERT INTO request_idempotency
                    (user_id, route_key, idempotency_key, request_hash,
                     response_status, response_json, expires_at)
                  VALUES ($1, $2, $3, $4, $5, $6, NOW() + ($7::int * INTERVAL '1 second'))
                  ON CONFLICT (user_id, route_key, idempotency_key) DO NOTHING`,
                [userId, routeKey, idempotencyKey, requestHash, status, serialized, ttlSeconds],
              )
              .catch((err) => {
                logger.warn({ err, routeKey }, 'Idempotency persist failed');
              });
          }
        }
      }
      return originalJson(body);
    };

    next();
  };
}

/**
 * S-HI-04: prune expired idempotency rows. Called from the daily cron.
 * The `idx_request_idempotency_expires` index already exists so the
 * delete is a quick range scan.
 */
export async function pruneExpiredIdempotencyRows(): Promise<number> {
  const result = await pool.query(
    `DELETE FROM request_idempotency WHERE expires_at < NOW()`,
  );
  return result.rowCount ?? 0;
}
