'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { setAuthCookies } from '@/lib/auth';
import { API_URL } from '@/lib/config';
import { fetchWithTimeout } from '@/lib/fetch';
import { isValidEmail, normalizeEmail } from '@/lib/email-policy';
import { validatePassword } from '@/lib/password-policy';

export async function signUp(formData: FormData) {
  const rawEmail = (formData.get('email') ?? '').toString();
  const password = (formData.get('password') ?? '').toString();
  const confirmPassword = (formData.get('confirmPassword') ?? '').toString();
  const fullName = (formData.get('fullName') ?? '').toString().trim();

  if (!isValidEmail(rawEmail)) {
    return { error: 'Please enter a valid email address' };
  }
  const email = normalizeEmail(rawEmail);

  if (!fullName || fullName.length < 2) {
    return { error: 'Full name is required' };
  }

  if (password !== confirmPassword) {
    return { error: 'Passwords do not match' };
  }

  // Mirrors the backend rule (Ch10-W018, W012): the dashboard cannot accept a
  // weaker password than signup permits.
  const policy = validatePassword(password);
  if (!policy.ok) {
    return { error: policy.reason || 'Password does not meet complexity rules' };
  }

  let response: Response;
  try {
    response = await fetchWithTimeout(`${API_URL}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, fullName }),
    });
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  if (!response.ok) {
    // Generic failure for any non-2xx (Ch10-W011): we do not echo upstream
    // messages back to the browser.
    if (response.status === 409) return { error: 'An account with that email already exists.' };
    if (response.status === 429) return { error: 'Too many requests. Please try again later.' };
    if (response.status >= 500) return { error: 'The service is temporarily unavailable. Please try again.' };
    return { error: 'We could not create your account. Please review your details and try again.' };
  }

  const data = await response.json().catch(() => null);
  if (!data?.accessToken || !data?.refreshToken) {
    return { error: 'We could not create your account. Please try again.' };
  }

  const cookieStore = await cookies();
  setAuthCookies(data.accessToken, data.refreshToken, cookieStore);

  redirect('/onboarding');
}
