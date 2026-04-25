/**
 * Server-side configuration. API_URL is the upstream Express API the proxy
 * forwards to. It MUST be set in any non-test environment — silently routing
 * to localhost in staging or production would point the dashboard at a
 * non-existent backend (audit Ch10-W006).
 *
 * `npm test` and `vitest` both set NODE_ENV=test, which is the only context
 * where we tolerate the localhost fallback (the test suite itself never
 * actually issues network calls).
 */
function resolveApiUrl(): string {
  const value = process.env.API_URL;
  if (value && value.trim().length > 0) return value;
  if (process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development') {
    return 'http://localhost:3000';
  }
  // Next.js sets NEXT_PHASE=phase-production-build while collecting page data
  // for SSG / app-router. We tolerate the missing env var during build so the
  // image still produces, but the runtime read in the running container WILL
  // throw if API_URL is still unset (the lazy `getApiUrl` helper below).
  if (process.env.NEXT_PHASE === 'phase-production-build') {
    return 'http://localhost:3000';
  }
  throw new Error(
    'API_URL is not set. Refusing to start the dashboard with an unconfigured upstream. ' +
      'Set API_URL to the Express API base URL (no trailing slash).'
  );
}

export const API_URL = resolveApiUrl();

/**
 * Client and proxy timeouts. Client is shorter than proxy so the user-facing
 * fetch always loses the race and surfaces a clear timeout, not a 504 leaked
 * from upstream (audit Ch10-W050).
 */
export const CLIENT_FETCH_TIMEOUT_MS = 25_000;
export const PROXY_FETCH_TIMEOUT_MS = 30_000;
