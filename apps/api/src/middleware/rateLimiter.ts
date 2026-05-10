import rateLimit from 'express-rate-limit';
import type { createClient } from 'redis';
import { config } from '../config';
import { logger } from '../utils/logger';
import { getRedisClient as getSharedRedisClient } from '../utils/redis';

// 4.12: exact-path set of probe routes the rate limiter must NEVER
// throttle. Mirrors `QUIET_PATHS` in requestLogger.ts. Add new probes
// here only — `startsWith` would over-match a future `/healthcheck`.
const PROBE_PATHS = new Set(['/health', '/live', '/ready']);

// Reuse the shared Redis client (Ch11-I060). The rate limiter used to open
// its own connection that diverged from token-blacklist + the user cache;
// every Redis hiccup hit one client and not the others, producing
// hard-to-triage flakiness.
async function getRedisClient(): Promise<ReturnType<typeof createClient>> {
  return getSharedRedisClient();
}

// Custom Redis store for rate limiting
class RedisStore {
  private prefix: string;
  private client: ReturnType<typeof createClient>;
  private windowMs: number;

  constructor(client: ReturnType<typeof createClient>, windowMs: number, prefix = 'rl:') {
    this.client = client;
    this.windowMs = windowMs;
    this.prefix = prefix;
  }

  // Lua script that atomically: removes expired entries, adds the current
  // request, counts the remaining entries, and sets the key TTL.  This avoids
  // the race condition inherent in separate ZRANGEBYSCORE + ZADD calls.
  private static readonly LUA_INCREMENT = `
    local key = KEYS[1]
    local now = tonumber(ARGV[1])
    local windowStart = tonumber(ARGV[2])
    local ttl = tonumber(ARGV[3])

    redis.call('ZREMRANGEBYSCORE', key, 0, windowStart)
    redis.call('ZADD', key, now, tostring(now) .. ':' .. tostring(math.random(1000000)))
    local count = redis.call('ZCARD', key)
    redis.call('EXPIRE', key, ttl)
    return count
  `;

  async increment(key: string): Promise<{ totalHits: number; resetTime: Date }> {
    const redisKey = this.prefix + key;
    const now = Date.now();
    const windowStart = now - this.windowMs;
    const ttlSeconds = Math.ceil(this.windowMs / 1000);

    // Execute the sliding-window rate-limit logic atomically in a single
    // Lua script to prevent race conditions under concurrent requests.
    const totalHits = await this.client.eval(RedisStore.LUA_INCREMENT, {
      keys: [redisKey],
      arguments: [String(now), String(windowStart), String(ttlSeconds)],
    }) as number;

    const resetTime = new Date(now + this.windowMs);

    return { totalHits, resetTime };
  }

  async decrement(key: string): Promise<void> {
    // express-rate-limit ≥7 calls decrement when a request handler later
    // marks itself as not-counting (e.g. failed auth shouldn't pull from
    // the limit budget). Pop one element from the sliding window so the
    // count drops by 1; ZREMRANGEBYRANK with stop=0 removes the oldest.
    const redisKey = this.prefix + key;
    await this.client.zRemRangeByRank(redisKey, 0, 0);
  }

  async resetKey(key: string): Promise<void> {
    const redisKey = this.prefix + key;
    await this.client.del(redisKey);
  }
}

// Initialize rate limiter with Redis in production and staging.
// Audit Ch11-I089: the previous "fall back to memory if Redis unavailable"
// path silently shrunk the production rate limit to a per-instance count,
// which under multi-instance deploys means a 100/min limit becomes 100*N/min.
// Production now FAILS startup if Redis is required and unavailable.
const initializeRateLimiter = async () => {
  const isProduction = config.env === 'production' || config.env === 'staging';
  if (!isProduction) {
    return createMemoryRateLimiter();
  }
  try {
    const client = await getRedisClient();
    const store = new RedisStore(client, config.rateLimit.windowMs);

    return rateLimit({
      windowMs: config.rateLimit.windowMs,
      max: config.rateLimit.max,
      message: 'Too many requests from this IP, please try again later.',
      standardHeaders: true,
      legacyHeaders: false,
      handler: (req, res) => {
        logger.warn({
          ip: req.ip,
          path: req.path,
          userAgent: req.get('user-agent'),
        }, 'Rate limit exceeded');

        res.status(429).json({
          error: 'Too many requests',
          message: 'Please try again later',
          retryAfter: Math.ceil(config.rateLimit.windowMs / 1000),
        });
      },
      skip: (req) => {
        // 3.9: webhook routes (Stripe, RevenueCat) are mounted before this
        // limiter today, so they don't currently hit it — but a future
        // re-order would silently start dropping webhook deliveries to
        // 429 (Stripe retries for 3 days). Belt-and-braces skip so the
        // limiter is order-independent.
        if (req.path.startsWith('/api/v1/webhooks/')) return true;
        // 4.12: exact match on the health probes. The previous
        // `startsWith` also bypassed e.g. `/healthcheck` or
        // `/ready-set-go` if a future route ever shipped under those
        // prefixes. The /health and /ready details routes are
        // mounted under the same router but are explicitly listed
        // here when introduced.
        return PROBE_PATHS.has(req.path);
      },
      store: store as any,
    });
  } catch (error) {
    // No silent memory fallback in production — surface the failure so the
    // pod fails health and the load balancer keeps its old healthy targets.
    logger.fatal({ error }, 'Redis required for rate limiting in production but unavailable');
    throw error;
  }
};

function createMemoryRateLimiter() {
  return rateLimit({
    windowMs: config.rateLimit.windowMs,
    // 10x multiplier: in development, hot-reloading and manual testing tools
    // (e.g. Postman, cURL loops) generate many more requests than real users.
    // The higher limit avoids false rate-limit blocks during local development
    // while still exercising the rate-limiting code path.
    max: config.rateLimit.max * 10,
    message: 'Too many requests from this IP, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    skip: (req) => {
      if (req.path.startsWith('/api/v1/webhooks/')) return true;
      // 4.12: exact-path match (see Redis variant above).
      return PROBE_PATHS.has(req.path);
    },
  });
}

// Export the initializer — must be awaited in index.ts
export { initializeRateLimiter };

// S-CR-03: per-endpoint rate limiters previously read `sharedRedisClient`
// once at module-load time and bound the resulting `store` permanently.
// Because module load happens BEFORE `initializeEndpointRedis()` resolves,
// every "specific" limiter ran against express-rate-limit's default
// in-memory store — i.e. per-instance, not distributed. In a multi-replica
// deploy a 10/15min auth limit becomes 10*N/15min.
//
// Fix: lazy-build each limiter on first request. By then Redis is up
// (initializeRateLimiter() runs at app boot before any route is mounted)
// and we get a Redis-backed store. Single-flight per limiter so we don't
// build N stores under burst.
let sharedRedisClient: ReturnType<typeof createClient> | null = null;

function createEndpointRateLimiter(options: {
  bucket: string; // 1.5: explicit Redis-key namespace, NOT derived from
                  // a free-text message. Pre-1.5 the prefix was the
                  // first 10 chars of `message`, which collided distinct
                  // limiters: `auth` + `activation` shared "Too many a";
                  // `passwordReset/Change/verifyPremium` shared "Too
                  // many p". Sharing meant the strictest cap governed
                  // all + an attacker could exhaust password-reset for
                  // a victim by spamming verify-premium.
  windowMs: number;
  max: number;
  message: string;
  skipSuccessfulRequests?: boolean;
  // S-C5: optional per-user keying for authenticated routes where the
  // attacker's IP is irrelevant (they're holding a valid bearer). Falls
  // back to req.ip when req.user.id is absent (auth flows themselves).
  keyGenerator?: (req: import('express').Request) => string;
}): import('express').RequestHandler {
  // Resolved on the first request after Redis is available. Cached
  // forever after that — express-rate-limit's RedisStore is safe to
  // reuse across requests.
  let resolved: import('express').RequestHandler | null = null;

  const build = (): import('express').RequestHandler => {
    const store = sharedRedisClient
      ? new RedisStore(sharedRedisClient, options.windowMs, `rl:${options.bucket}:`)
      : undefined;
    return rateLimit({
      windowMs: options.windowMs,
      max: options.max,
      message: options.message,
      ...(options.skipSuccessfulRequests !== undefined
        ? { skipSuccessfulRequests: options.skipSuccessfulRequests }
        : {}),
      ...(options.keyGenerator ? { keyGenerator: options.keyGenerator } : {}),
      standardHeaders: true,
      legacyHeaders: false,
      ...(store ? { store: store as any } : {}),
    });
  };

  return (req, res, next) => {
    // Build the real limiter on first call. If Redis is up by then
    // (the normal case in production after initializeEndpointRedis
    // resolves), we get a Redis-backed store. If not, we fall back to
    // in-memory and the warning was already logged at boot.
    if (!resolved) {
      resolved = build();
    }
    return resolved(req, res, next);
  };
}

// Initialize the shared Redis client for endpoint-specific limiters.
// Called from start() in index.ts, AFTER waitForDatabase has resolved.
//
// Audit Ch11-I089b: previously this was invoked at module-load time
// (top-level), which started a redis connect in parallel with the rest
// of the boot path. On a slow first-DB-probe (the api boots before the
// DB readiness window passes), node's event loop was starved enough
// that the redis socket timed out at 24s and the rate limiter init
// crashed startup. Pull it inside start() so DB-readiness completes
// first; the redis connect now finishes in <300ms.
export async function initializeEndpointRedis() {
  if (config.env !== 'development' && config.env !== 'test') {
    try {
      sharedRedisClient = await getRedisClient();
      logger.info('Endpoint rate limiters bound to shared Redis');
    } catch (error) {
      // H8: fail-closed. The prior shape logged + swallowed and let the
      // per-endpoint limiters fall back to in-memory — which on a
      // multi-replica deploy silently multiplied every effective budget
      // by the replica count (login limit 10/15min → 30/15min on 3
      // replicas). Mirror initializeRateLimiter()'s behavior and crash
      // the process so the LB keeps healthy targets.
      logger.fatal({ err: error }, 'Redis required for endpoint rate limiters; refusing to start');
      throw error;
    }
  }
}

/**
 * Close the rate-limiter's reference to Redis. The shared Redis client owns
 * the actual socket close (utils/redis.ts → closeRedisClient); this function
 * only clears the module-level reference to it.
 */
export async function closeRateLimiterRedis(): Promise<void> {
  sharedRedisClient = null;
}

// Specific rate limiters for sensitive endpoints
export const authRateLimiter = createEndpointRateLimiter({
  bucket: 'auth',
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many attempts, please try again later.',
});

// H9: per-account login limiter. The IP limiter at `authRateLimiter`
// caps 10/15min per IP — a botnet across 1000 IPs trivially defeats it
// against a single targeted account. Layer a per-email limit on top so
// credential-stuffing one account is rate-limited regardless of source
// IP. Mount BOTH on /auth/login; either trip returns generic 429.
//
// 20/15min per email: high enough that a user fat-fingering their
// password isn't blocked, low enough that an attacker can't run a
// 100-IP password-list against one account in under a working day.
export const loginPerEmailRateLimiter = createEndpointRateLimiter({
  bucket: 'loginEmail',
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: 'Too many sign-in attempts for this account, please try again later.',
  // The /auth/login body schema lowercases `email`; fall back to ip
  // when body is missing/malformed (validate() runs AFTER rate limiters
  // because we want to throttle parse-failure floods too).
  keyGenerator: (req) => {
    const email = req.body?.email;
    if (typeof email === 'string' && email.length > 0) {
      return `email:${email.toLowerCase()}`;
    }
    return `ip:${req.ip ?? 'unknown'}`;
  },
});

// Refresh rate limiter: 10 requests per 15 minutes.
// This is intentionally generous since mobile apps may refresh tokens frequently.
// Consider reducing if abuse is detected.
export const refreshRateLimiter = createEndpointRateLimiter({
  bucket: 'refresh',
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many token refresh attempts, please try again later.',
  skipSuccessfulRequests: false, // Count all attempts for brute-force protection
});

export const uploadRateLimiter = createEndpointRateLimiter({
  bucket: 'upload',
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'Too many uploads, please try again later.',
});

export const passwordResetRateLimiter = createEndpointRateLimiter({
  bucket: 'pwReset',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many password reset attempts, please try again later.',
});

export const activationCodeRateLimiter = createEndpointRateLimiter({
  bucket: 'activation',
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many activation code attempts, please try again later.',
});

// BE-12: Rate limiter for premium verification endpoint
// Limits to 5 requests per 15 minutes to prevent abuse of RevenueCat API calls
export const verifyPremiumRateLimiter = createEndpointRateLimiter({
  bucket: 'verifyPremium',
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: 'Too many premium verification attempts, please try again later.',
});

// Rate limiter for password change endpoint
// 5 attempts per hour to prevent brute-force current password guessing
export const passwordChangeRateLimiter = createEndpointRateLimiter({
  bucket: 'pwChange',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many password change attempts, please try again later.',
});

// Rate limiter for write endpoints (POST, PUT, DELETE)
// 30 requests per 15 minutes to prevent abuse of data-mutating operations
export const writeRateLimiter = createEndpointRateLimiter({
  bucket: 'write',
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30,
  message: 'Too many write requests, please try again later.',
});

// Gift email resend limiter: 3 resends per hour per IP
export const giftResendRateLimiter = createEndpointRateLimiter({
  bucket: 'giftResend',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many gift email resend attempts, please try again later.',
});

// Receipt scan limiter: 10 per minute per IP
export const receiptScanRateLimiter = createEndpointRateLimiter({
  bucket: 'receiptScan',
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'Too many receipt scan requests, please try again later.',
});

// Items list limiter (Ch02-F065): cheap to call but expensive to scale; cap
// at 60 reads/minute per IP. Burst-friendly for normal app use, blocks
// scrapers.
export const itemsListRateLimiter = createEndpointRateLimiter({
  bucket: 'itemsList',
  windowMs: 60 * 1000, // 1 minute
  max: 60,
  message: 'Too many list requests, please try again later.',
});

// CSV export limiter (Ch02-F066): exports stream the entire item table; cap
// to 5 per hour per IP to prevent unbounded server work.
export const csvExportRateLimiter = createEndpointRateLimiter({
  bucket: 'csvExport',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many CSV exports, please try again later.',
});

// Newsletter subscription limiter: 5 per hour per IP
export const newsletterRateLimiter = createEndpointRateLimiter({
  bucket: 'newsletter',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many subscription attempts, please try again later.',
});

// Contact form limiter: 3 per hour per IP
export const contactRateLimiter = createEndpointRateLimiter({
  bucket: 'contact',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many contact submissions, please try again later.',
});

// Generic read limiter (Ch04-F009/F089): per-IP cap on cheap GET endpoints
// that fan out big joins (warranty-claims list, audit/logs, etc.). 120/min
// matches the busy mobile-app scrolling pattern; anything above is scraping.
export const readRateLimiter = createEndpointRateLimiter({
  bucket: 'read',
  windowMs: 60 * 1000, // 1 minute
  max: 120,
  message: 'Too many read requests, please slow down.',
});

// S-C5: per-user limiter for /me/change-email. The endpoint sends a
// SendGrid mail to whatever address the authenticated caller supplies —
// at the prior 30/15min writeRateLimiter (per-IP), an attacker holding
// one valid bearer token could rotate victim addresses and burn ~120
// branded HavenKeep emails/hour at any chosen recipient. Per-user 3/hour
// closes the user-side; the per-recipient guard inside the route handler
// (Redis 24h dedupe keyed on hash(newEmail)) closes the recipient side.
export const changeEmailRateLimiter = createEndpointRateLimiter({
  bucket: 'changeEmail',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many email-change requests. Please try again in an hour.',
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
});

// S-C6: per-user limiter for POST /email-scanner/scan. The endpoint hits
// Google's / Microsoft's OAuth token endpoint server-side and pulls mail.
// One compromised premium account at the prior unbounded rate could
// drain HavenKeep's per-app provider quotas, taking the scanner offline
// for everyone. 5/hour is generous for legitimate scanning patterns.
export const emailScannerScanRateLimiter = createEndpointRateLimiter({
  bucket: 'emailScannerScan',
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many email-scanner runs. Please wait an hour before retrying.',
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
});

// S-C6 sibling: per-user limiter for the email-scanner mutation actions
// (cancel, approve, reject, delete-integration). Higher cap (these are
// cheap and user-facing) but still per-user-scoped so attackers can't
// burn through queues from one bearer.
export const emailScannerWriteRateLimiter = createEndpointRateLimiter({
  bucket: 'emailScannerWrite',
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: 'Too many email-scanner actions. Please slow down.',
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
});
