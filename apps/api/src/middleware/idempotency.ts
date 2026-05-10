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
//   2. If absent, pass through (unless required=true → 400).
//   3. Otherwise: claim a slot atomically (H3) via INSERT ... ON CONFLICT
//      DO NOTHING RETURNING. Winner runs the handler; loser polls the row
//      for the cached response (or returns 409 on body-hash mismatch).
//   4. After the handler responds, the winner UPDATEs the slot with the
//      response. Subsequent same-key requests get the cached reply.
//
// Hash input (H4 + H5): method, original URL (path + query string), and a
// canonical (sorted-key) JSON serialization of the body. Without the
// method/URL the same key could replay a response for resource A against
// a request for resource B. Without canonical body keys the same logical
// body with different key order would miss the cache.

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

// H3: how long a polling loser waits for the executor to fill in the
// cached response before giving up. The handlers we cover with
// idempotency() complete in well under 10s; if the executor crashes
// the loser surfaces 503 so the client can retry with the SAME key
// (the next attempt won't find a still-claimed row).
const POLL_TIMEOUT_MS = 10_000;
const POLL_INTERVAL_MS = 100;

// H3: a claim older than this is treated as orphaned (the executor
// pod restarted before filling in the response). The next caller
// re-claims after the placeholder is deleted.
const STALE_CLAIM_MS = 60_000;

/**
 * H4: produce a stable JSON string regardless of object-key order so
 * `{a:1, b:2}` and `{b:2, a:1}` hash identically. Skips arrays-as-is
 * (order is meaningful there). NaN/Infinity round-trip as null per
 * standard JSON; that's fine here because we hash for equality, not
 * for round-trip fidelity.
 */
function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(obj).sort()) {
      out[key] = canonicalize(obj[key]);
    }
    return out;
  }
  return value;
}

function hashRequest(method: string, originalUrl: string, body: unknown): string {
  // H5: method + URL (path + query) folded into the digest. Otherwise
  // a key reused across DELETE /items/A and DELETE /items/B (same body)
  // would replay the wrong cached response on the second call.
  const payload = JSON.stringify({
    method,
    url: originalUrl,
    body: canonicalize(body ?? null),
  });
  return crypto.createHash('sha256').update(payload).digest('hex');
}

async function pollForCachedResponse(
  userId: string,
  routeKey: string,
  idempotencyKey: string,
): Promise<{ status: number; body: unknown } | null> {
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const result = await pool.query<{
      response_status: number | null;
      response_json: unknown | null;
      claimed_at: Date | null;
    }>(
      `SELECT response_status, response_json, claimed_at
         FROM request_idempotency
        WHERE user_id = $1 AND route_key = $2 AND idempotency_key = $3
          AND expires_at > NOW()`,
      [userId, routeKey, idempotencyKey],
    );
    if (result.rows.length === 0) return null; // claim vanished — retry
    const row = result.rows[0];
    if (row.response_status !== null && row.response_json !== null) {
      return { status: row.response_status, body: row.response_json };
    }
    // Executor died before filling the row in. Punt the polling caller
    // so they don't spin forever on a stuck claim.
    if (row.claimed_at && Date.now() - row.claimed_at.getTime() > STALE_CLAIM_MS) {
      return null;
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
  return null;
}

/**
 * @param routeKey  Namespace under which (user_id, key) lives.
 * @param opts.ttlSeconds  How long a successful response is cached for replay.
 * @param opts.required  When true, refuse requests that omit
 *   `Idempotency-Key`. The default (false) lets the client opt in. Set
 *   true on money-moving endpoints (gift create, payouts) where a
 *   silent retry without a key would charge twice on a double-click.
 */
export function idempotency(
  routeKey: string,
  opts: { ttlSeconds?: number; required?: boolean } = {},
) {
  const ttlSeconds = opts.ttlSeconds ?? DEFAULT_TTL_SECONDS;
  const required = opts.required ?? false;
  return async function idempotencyMiddleware(
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    const userId = (req as any).user?.id as string | undefined;
    const headerVal = req.headers['idempotency-key'] || req.headers['Idempotency-Key'];
    const idempotencyKey = Array.isArray(headerVal) ? headerVal[0] : headerVal;

    if (required && !idempotencyKey) {
      next(
        new AppError(
          'Idempotency-Key header is required for this endpoint',
          400,
          'VALIDATION_ERROR',
        ),
      );
      return;
    }

    if (!userId || !idempotencyKey) {
      next();
      return;
    }

    const requestHash = hashRequest(req.method, req.originalUrl, req.body);

    // H3: claim the slot atomically. The first concurrent caller wins;
    // the loser polls. RETURNING tells us whether we won.
    let won = false;
    try {
      const claim = await pool.query(
        `INSERT INTO request_idempotency
            (user_id, route_key, idempotency_key, request_hash,
             claimed_at, expires_at)
          VALUES ($1, $2, $3, $4, NOW(),
                  NOW() + ($5::int * INTERVAL '1 second'))
          ON CONFLICT (user_id, route_key, idempotency_key) DO NOTHING
          RETURNING request_hash`,
        [userId, routeKey, idempotencyKey, requestHash, ttlSeconds],
      );
      won = claim.rows.length > 0;
    } catch (err) {
      logger.warn({ err, routeKey }, 'Idempotency claim INSERT failed; continuing without replay');
      next();
      return;
    }

    if (!won) {
      // Someone else got there first. Re-check whether their body
      // matches ours — if not, 409. Otherwise wait for them to finish
      // and replay their cached response.
      try {
        const prior = await pool.query<{
          request_hash: string;
          response_status: number | null;
          response_json: unknown | null;
        }>(
          `SELECT request_hash, response_status, response_json
             FROM request_idempotency
            WHERE user_id = $1 AND route_key = $2 AND idempotency_key = $3
              AND expires_at > NOW()`,
          [userId, routeKey, idempotencyKey],
        );
        if (prior.rows.length === 0) {
          // Claim expired between INSERT and SELECT. Pass through —
          // worst case the next call re-runs.
          next();
          return;
        }
        const row = prior.rows[0];
        if (row.request_hash !== requestHash) {
          next(new AppError('Idempotency-Key reused with a different request body', 409));
          return;
        }
        if (row.response_status !== null && row.response_json !== null) {
          res.status(row.response_status).json(row.response_json);
          return;
        }
        // In-flight — poll briefly.
        const cached = await pollForCachedResponse(userId, routeKey, idempotencyKey);
        if (cached) {
          res.status(cached.status).json(cached.body);
          return;
        }
        // Executor never filled in the slot in time. Surface a retryable
        // error so the client can re-send (a fresh attempt with the
        // same key will be the new executor).
        next(
          new AppError(
            'Concurrent request did not complete in time; please retry',
            503,
            'UNHEALTHY',
          ),
        );
        return;
      } catch (err) {
        if (err instanceof AppError) {
          next(err);
          return;
        }
        logger.warn({ err, routeKey }, 'Idempotency poll failed; continuing without replay');
        next();
        return;
      }
    }

    // Winner — wrap res.json to fill the placeholder with the response.
    const originalJson = res.json.bind(res);
    let persisted = false;
    res.json = function (body: any): Response {
      const status = res.statusCode || 200;
      if (!persisted && status >= 200 && status < 300) {
        persisted = true;
        let serialized: string | null = null;
        try {
          serialized = JSON.stringify(body);
        } catch (err) {
          logger.warn(
            { err, routeKey },
            'Idempotency serialize failed (circular ref or unsupported type); skipping persist',
          );
        }
        if (serialized !== null && serialized.length > MAX_RESPONSE_BYTES) {
          logger.warn(
            { routeKey, bytes: serialized.length, cap: MAX_RESPONSE_BYTES },
            'Idempotency response too large; dropping claim row so a future request can re-execute',
          );
          // Drop the placeholder so future replays don't return a half-
          // baked status with no body.
          pool
            .query(
              `DELETE FROM request_idempotency
                WHERE user_id = $1 AND route_key = $2 AND idempotency_key = $3`,
              [userId, routeKey, idempotencyKey],
            )
            .catch((err) =>
              logger.warn({ err, routeKey }, 'Idempotency claim cleanup failed'),
            );
        } else if (serialized !== null) {
          pool
            .query(
              `UPDATE request_idempotency
                  SET response_status = $4,
                      response_json   = $5::jsonb
                WHERE user_id = $1 AND route_key = $2 AND idempotency_key = $3`,
              [userId, routeKey, idempotencyKey, status, serialized],
            )
            .catch((err) => {
              logger.warn({ err, routeKey }, 'Idempotency persist failed');
            });
        }
      }
      return originalJson(body);
    };

    // H3: if the handler throws / responds with a non-2xx, the claim
    // placeholder must be cleared so the same key can be retried.
    // res.on('finish') fires after headers + body are flushed for any
    // status code; we delete the claim if no response was persisted
    // (i.e. either error path or 4xx/5xx without a body).
    res.on('finish', () => {
      if (!persisted) {
        pool
          .query(
            `DELETE FROM request_idempotency
              WHERE user_id = $1 AND route_key = $2 AND idempotency_key = $3
                AND response_status IS NULL`,
            [userId, routeKey, idempotencyKey],
          )
          .catch((err) =>
            logger.warn({ err, routeKey }, 'Idempotency claim cleanup-on-error failed'),
          );
      }
    });

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
