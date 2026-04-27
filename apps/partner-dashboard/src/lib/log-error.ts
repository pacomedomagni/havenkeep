// S3-E: tiny client-side error logger that strips stack traces and known
// sensitive keys before forwarding to console.error. Replaces direct
// `console.error('label', err)` calls so a thrown object that includes
// e.g. an Authorization header or a session cookie can't leak into
// browser devtools (or any analytics that mirrors them).

const SENSITIVE_KEYS = new Set([
  'authorization',
  'cookie',
  'set-cookie',
  'token',
  'access_token',
  'accesstoken',
  'refresh_token',
  'refreshtoken',
  'password',
  'csrf_token',
  'x-csrf-token',
]);

function sanitize(value: unknown, depth = 0): unknown {
  if (value == null) return value;
  if (depth > 4) return '[truncated]';
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  if (value instanceof Error) {
    return { name: value.name, message: value.message };
  }
  if (Array.isArray(value)) {
    return value.slice(0, 25).map((v) => sanitize(v, depth + 1));
  }
  if (typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (SENSITIVE_KEYS.has(k.toLowerCase())) {
        out[k] = '[redacted]';
        continue;
      }
      out[k] = sanitize(v, depth + 1);
    }
    return out;
  }
  return '[unserializable]';
}

export function logError(label: string, err: unknown): void {
  console.error(label, sanitize(err));
}
