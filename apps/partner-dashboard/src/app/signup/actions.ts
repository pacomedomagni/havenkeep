'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { setAuthCookies } from '@/lib/auth';
import { API_URL } from '@/lib/config';
import { fetchWithTimeout } from '@/lib/fetch';
import { isValidEmail, normalizeEmail } from '@/lib/email-policy';
import { validatePassword } from '@/lib/password-policy';
import type { PartnerType } from '@/lib/types';

const VALID_PARTNER_TYPES: readonly PartnerType[] = [
  'realtor',
  'builder',
  'contractor',
  'property_manager',
  'other',
];

export async function signUp(formData: FormData) {
  const rawEmail = (formData.get('email') ?? '').toString();
  const password = (formData.get('password') ?? '').toString();
  const confirmPassword = (formData.get('confirmPassword') ?? '').toString();
  const fullName = (formData.get('fullName') ?? '').toString().trim();
  const companyName = (formData.get('companyName') ?? '').toString().trim();
  const partnerTypeRaw = (formData.get('partnerType') ?? 'realtor').toString();

  if (!isValidEmail(rawEmail)) {
    return { error: 'Please enter a valid email address' };
  }
  const email = normalizeEmail(rawEmail);

  if (!fullName || fullName.length < 2) {
    return { error: 'Full name is required' };
  }

  if (!companyName) {
    return { error: 'Company or business name is required' };
  }

  const partnerType: PartnerType = VALID_PARTNER_TYPES.includes(partnerTypeRaw as PartnerType)
    ? (partnerTypeRaw as PartnerType)
    : 'realtor';

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

  // H-A7: API wraps responses in { success, data: { ... } }; unwrap before
  // reading the tokens.
  const body = await response.json().catch(() => null);
  const data = body?.data;
  if (!data?.accessToken || !data?.refreshToken) {
    return { error: 'We could not create your account. Please try again.' };
  }

  const cookieStore = await cookies();
  setAuthCookies(data.accessToken, data.refreshToken, cookieStore);

  // Register the partner profile in the same submit. The user is now
  // authenticated; we forward the access token explicitly because cookies
  // aren't yet on the outbound request at this point in the action.
  //
  // If this leg fails (network blip, validator drift, 5xx), the account
  // still exists with valid tokens — they just don't have a partner row.
  // Send them to /recover-profile, which is gated to authenticated-no-role
  // users by middleware. From there a single submit creates the partner
  // row and they land on /dashboard.
  let partnerProfileCreated = false;
  try {
    const partnerResp = await fetchWithTimeout(`${API_URL}/api/v1/partners/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${data.accessToken}`,
      },
      body: JSON.stringify({
        company_name: companyName,
        partner_type: partnerType,
      }),
    });
    // 201 created OR 409 "already registered" both leave a usable row.
    partnerProfileCreated = partnerResp.ok || partnerResp.status === 409;
  } catch {
    partnerProfileCreated = false;
  }

  redirect(partnerProfileCreated ? '/dashboard' : '/recover-profile');
}
