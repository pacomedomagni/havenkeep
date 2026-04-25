import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { logger, requestContext, RequestContext } from '../utils/logger';

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
  const requestId = (req.get('x-request-id') as string) || crypto.randomUUID();
  req.headers['x-request-id'] = requestId;
  res.setHeader('x-request-id', requestId);

  const ctx: RequestContext = { requestId, ip: req.ip };

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
    logger.info(
      {
        method: req.method,
        path: req.path,
        statusCode: res.statusCode,
        durationMs: duration,
        userAgent: ua && ua.length > UA_MAX ? `${ua.slice(0, UA_MAX)}…` : ua,
        ip: req.ip,
      },
      'Request completed',
    );
  });

  // Run the rest of the request inside the AsyncLocalStorage store so any
  // logger.* call from a downstream handler/service picks up the requestId.
  requestContext.run(ctx, () => next());
}
