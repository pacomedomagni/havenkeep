'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import {
  setAuthCookies,
  setMfaTokenCookie,
  readMfaTokenCookie,
  clearMfaTokenCookie,
} from '@/lib/auth';
import { decodeJwtPayload, looksLikeJwt } from '@/lib/jwt';
import { isValidEmail, normalizeEmail } from '@/lib/email-policy';
import { API_URL } from '@/lib/config';
import { fetchWithTimeout } from '@/lib/fetch';

const GENERIC_LOGIN_ERROR = 'The email or password is incorrect.';

export async function signIn(
  _prevState: { error: string } | null,
  formData: FormData
): Promise<{ error: string }> {
  const rawEmail = (formData.get('email') ?? '').toString();
  const password = (formData.get('password') ?? '').toString();

  if (!rawEmail || !password) {
    return { error: 'Email and password are required' };
  }
  if (!isValidEmail(rawEmail)) {
    // Same generic failure regardless of whether the email shape is valid —
    // tells an attacker nothing about which field tripped (Ch10-W015).
    return { error: GENERIC_LOGIN_ERROR };
  }
  const email = normalizeEmail(rawEmail);

  let destination = '/dashboard';

  let response: Response;
  try {
    response = await fetchWithTimeout(`${API_URL}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  if (!response.ok) {
    // Generic for everything in [400..499] except rate-limit (Ch10-W011, W015).
    // Drain the body so logs aren't surprised by it but never surface upstream
    // text to the user.
    await response.json().catch(() => ({}));
    if (response.status === 429) {
      return { error: 'Too many sign-in attempts. Please try again later.' };
    }
    if (response.status >= 500) {
      // 5xx must surface as an error, not silently fall through (Ch10-W017).
      return { error: 'The service is temporarily unavailable. Please try again.' };
    }
    return { error: GENERIC_LOGIN_ERROR };
  }

  // H-A7: API wraps every success in { success, data: { accessToken, ... } }
  // (apps/api/src/utils/response.ts sendSuccess). Reading data.accessToken
  // off the parsed body landed on body.accessToken (undefined), so every
  // login collapsed into GENERIC_LOGIN_ERROR. Unwrap body.data first.
  const body = await response.json().catch(() => null);
  const data = body?.data;

  // C0-27: partners / admins with TOTP enrolled get an MFA challenge
  // instead of a session. Stash the challenge token in an httpOnly
  // cookie and bounce to /login/mfa, where the user enters the code.
  if (data?.mfa_required === true) {
    if (typeof data.mfa_token !== 'string' || !looksLikeJwt(data.mfa_token)) {
      return { error: GENERIC_LOGIN_ERROR };
    }
    const cookieStore = await cookies();
    setMfaTokenCookie(data.mfa_token, cookieStore);
    redirect('/login/mfa');
  }

  if (!data || typeof data.accessToken !== 'string' || !looksLikeJwt(data.accessToken)) {
    return { error: GENERIC_LOGIN_ERROR };
  }
  if (!data.user?.is_admin && !data.user?.is_partner) {
    return { error: 'Access restricted to partners and administrators' };
  }

  const cookieStore = await cookies();
  setAuthCookies(data.accessToken, data.refreshToken, cookieStore);

  const payload = decodeJwtPayload(data.accessToken);
  if (payload?.isAdmin === true) destination = '/admin';

  redirect(destination);
}

// C0-27: second-factor handoff. Consumes the mfa_token cookie set by
// signIn, posts it + the user-supplied code to /auth/mfa/challenge,
// then on success stores real auth cookies and redirects to the
// dashboard. On any failure the cookie is left in place (it has its
// own 5-min TTL) so the user can retry the code without re-typing
// their password.
export async function verifyMfa(
  _prevState: { error: string } | null,
  formData: FormData,
): Promise<{ error: string }> {
  const code = (formData.get('code') ?? '').toString().trim();
  if (!code) {
    return { error: 'Enter your authentication code.' };
  }

  const cookieStore = await cookies();
  const mfaToken = readMfaTokenCookie(cookieStore);
  if (!mfaToken) {
    // Cookie missing / expired — punt back to /login.
    redirect('/login');
  }

  let response: Response;
  try {
    response = await fetchWithTimeout(`${API_URL}/api/v1/auth/mfa/challenge`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mfa_token: mfaToken, code }),
    });
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  if (!response.ok) {
    await response.json().catch(() => ({}));
    if (response.status === 429) {
      return { error: 'Too many attempts. Please wait and try again.' };
    }
    if (response.status === 401) {
      // Challenge token expired — push back to /login. Clear the
      // dead cookie so the user gets a clean restart.
      clearMfaTokenCookie(cookieStore);
      redirect('/login');
    }
    return { error: 'That code is not valid. Please try again.' };
  }

  const body = await response.json().catch(() => null);
  const data = body?.data;
  if (!data || typeof data.accessToken !== 'string' || !looksLikeJwt(data.accessToken)) {
    return { error: 'That code is not valid. Please try again.' };
  }
  if (!data.user?.is_admin && !data.user?.is_partner) {
    clearMfaTokenCookie(cookieStore);
    return { error: 'Access restricted to partners and administrators' };
  }

  setAuthCookies(data.accessToken, data.refreshToken, cookieStore);
  clearMfaTokenCookie(cookieStore);

  const payload = decodeJwtPayload(data.accessToken);
  redirect(payload?.isAdmin === true ? '/admin' : '/dashboard');
}
