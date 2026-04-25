import { AsyncLocalStorage } from 'async_hooks';
import pino from 'pino';
import { config } from '../config';

// AsyncLocalStorage threads request context (currently the request id)
// through every log line and DB call without manual plumbing. The middleware
// in src/middleware/requestLogger.ts populates `requestContext.run({...})`
// once per request; the mixin below copies the active store onto every log.
//
// (Audit Ch11-I017 / I059)
export interface RequestContext {
  requestId: string;
  userId?: string;
  ip?: string;
}

export const requestContext = new AsyncLocalStorage<RequestContext>();

// Pino redact paths cover every shape we know logs sensitive material.
// `remove: false` keeps the key in the log so reviewers can see *that* a
// sensitive field flowed, just not its value.
const REDACT_PATHS = [
  // request headers
  'req.headers.authorization',
  'req.headers.cookie',
  'req.headers["x-csrf-token"]',
  'req.headers["x-api-key"]',
  'req.headers["stripe-signature"]',
  'res.headers["set-cookie"]',
  // request body
  'req.body.password',
  'req.body.password_hash',
  'req.body.passwordHash',
  'req.body.token',
  'req.body.refresh_token',
  'req.body.refreshToken',
  'req.body.access_token',
  'req.body.accessToken',
  'req.body.id_token',
  'req.body.idToken',
  'req.body.code',
  'req.body.activation_code',
  'req.body.activationCode',
  'req.body.image',
  'req.body.api_key',
  'req.body.apiKey',
  'req.body.stripe_secret_key',
  // arbitrary nested objects (pino glob)
  '*.password',
  '*.password_hash',
  '*.passwordHash',
  '*.token',
  '*.refresh_token',
  '*.refreshToken',
  '*.access_token',
  '*.accessToken',
  '*.id_token',
  '*.idToken',
  '*.activation_code',
  '*.activationCode',
  '*.api_key',
  '*.apiKey',
  '*.stripe_secret_key',
  '*.stripeSecretKey',
];

const isProd = config.env === 'production';

export const logger = pino({
  level: isProd ? 'info' : 'debug',
  redact: { paths: REDACT_PATHS, censor: '[REDACTED]' },
  // Audit Ch11-I057: pid + hostname on every prod line are line-noise that
  // Loki indexes for nothing. Keep them in dev where they're handy for
  // reproducing local issues across nodemon restarts.
  base: isProd
    ? { service: 'havenkeep-api', environment: config.env }
    : { service: 'havenkeep-api', environment: config.env, pid: process.pid, hostname: undefined },
  // Pretty in dev, JSON in prod (Loki/Promtail).
  transport: !isProd ? {
    target: 'pino-pretty',
    options: { colorize: true, translateTime: 'SYS:standard', ignore: 'pid,hostname' },
  } : undefined,
  formatters: isProd ? {
    level: (label) => ({ level: label }),
  } : undefined,
  // Audit Ch11-I017 / I059: every log line picks up the active request
  // context (request id + user id when bound by the middleware).
  mixin() {
    const ctx = requestContext.getStore();
    if (!ctx) return {};
    return {
      requestId: ctx.requestId,
      ...(ctx.userId ? { userId: ctx.userId } : {}),
    };
  },
});

/**
 * Fatal logger for the uncaughtException / unhandledRejection paths.  Pino's
 * `final` helper exists to synchronise the async transport before exit, but
 * the typings vary between minor versions and we don't want a type-level
 * change to break shutdown. We grab the symbol off pino at runtime and fall
 * back to the regular logger if it's missing — a missing log line on a
 * crashing process is acceptable; a typecheck failure that blocks deploy is
 * not. (Ch11-I058)
 */
const pinoAny: any = pino;
export const fatalLogger: pino.Logger =
  typeof pinoAny.final === 'function'
    ? (pinoAny.final(logger, (err: Error, finalLoggerInstance: pino.Logger, evt?: string) => {
        finalLoggerInstance.fatal({ err, event: evt }, 'Fatal: process is exiting');
      }) as pino.Logger)
    : logger;
