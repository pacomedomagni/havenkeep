import { PROXY_FETCH_TIMEOUT_MS } from './config';

/**
 * fetch with an AbortController-driven timeout. Used by every server action
 * that talks to the upstream API so a stalled backend can't hang the page
 * indefinitely (audit Ch10-W007, W050).
 *
 * The cleared timeout fires regardless of whether fetch resolved or rejected.
 */
export async function fetchWithTimeout(
  url: string,
  init: Omit<RequestInit, 'signal'> = {},
  timeoutMs = PROXY_FETCH_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}
