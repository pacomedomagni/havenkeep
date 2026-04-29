import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { logger, requestContext, RequestContext } from '../utils/logger';
import { getIpAddress } from '../utils/ip-address';

// Routes that fire many times a second from k8s/Caddy probes — logging them
// at info level both inflates Loki costs and pushes useful logs out of the
// shorter-retention cheap tier. Skip with a `trace` line in dev so they're
// still visible if needed (audit Ch11-I022).
const QUIET_PATHS = new Set(['/health', '/live', '/ready']);

// Cap user-agent length so a 30-KB browser-fingerprinting UA can't blow up
// log line cardinality (Ch11-I021).
const UA_MAX = 200;

export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const start = Date.now();

  // Generate or use existing request id for correlation. Both req and res
  // carry it; the AsyncLocalStorage store carries it through every nested
  // log call without manual plumbing.
  //
  // S-LO-04: cap + regex-restrict client-supplied request ids so a hostile
  // header can't bloat logs or smuggle weird payloads into pino metadata.
  const REQUEST_ID_RE = /^[A-Za-z0-9._-]{1,64}$/;
  const incoming = req.get('x-request-id');
  const requestId =
    incoming && REQUEST_ID_RE.test(incoming) ? incoming : crypto.randomUUID();
  req.headers['x-request-id'] = requestId;
  res.setHeader('x-request-id', requestId);

  // 4.11: use the same XFF-trimming helper as the audit service. Express
  // `req.ip` reflects the *first* trusted hop per `app.set('trust proxy', N)`,
  // which can disagree with the audit log when our trust-hop policy changes
  // and `app.set` isn't updated in lockstep. Single source of truth.
  const ip = getIpAddress(req);
  const ctx: RequestContext = { requestId, ip };

  res.on('finish', () => {
    const duration = Date.now() - start;

    // Pick up userId at finish time — the auth middleware may have populated
    // it after this middleware ran (Ch11-I020).
    if (req.user?.id && !ctx.userId) ctx.userId = req.user.id;

    if (QUIET_PATHS.has(req.path)) {
      logger.trace(
        { method: req.method, path: req.path, statusCode: res.statusCode, durationMs: duration },
        'Health probe',
      );
      return;
    }

    const ua = req.get('user-agent');
    // 3.7: bucket request lines by how slow they were so a tail of the
    // log isn't drowned in fast 200s. Anything past 5s is loud (logger.warn,
    // pages on the dashboards we ship in 3.13). Anything past 1s is
    // tagged `slow: true` at info level so we can grep for it. Below
    // that, plain info.
    const meta = {
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      durationMs: duration,
      userAgent: ua && ua.length > UA_MAX ? `${ua.slice(0, UA_MAX)}…` : ua,
      ip,
    } as const;
    if (duration >= 5000) {
      logger.warn({ ...meta, slow: true }, 'Slow request (>5s)');
    } else if (duration >= 1000) {
      logger.info({ ...meta, slow: true }, 'Slow request (>1s)');
    } else {
      logger.info(meta, 'Request completed');
    }
  });

  // Run the rest of the request inside the AsyncLocalStorage store so any
  // logger.* call from a downstream handler/service picks up the requestId.
  requestContext.run(ctx, () => next());
}
