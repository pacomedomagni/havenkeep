'use server';

import { API_URL } from '@/lib/config';
import { fetchWithTimeout } from '@/lib/fetch';
import { validatePassword } from '@/lib/password-policy';

export async function resetPassword(
  token: string,
  newPassword: string
): Promise<{ error: string } | null> {
  if (!token) {
    return { error: 'Reset token is missing' };
  }

  const policy = validatePassword(newPassword);
  if (!policy.ok) {
    return { error: policy.reason || 'Password does not meet complexity rules' };
  }

  let response: Response;
  try {
    response = await fetchWithTimeout(`${API_URL}/api/v1/auth/reset-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, newPassword }),
    });
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  if (!response.ok) {
    // Drain so logs don't get surprised, then map to a generic message
    // (audit Ch10-W011).
    await response.json().catch(() => ({}));
    if (response.status === 400) {
      return { error: 'Invalid or expired reset token. Please request a new one.' };
    }
    if (response.status === 429) {
      return { error: 'Too many requests. Please try again later.' };
    }
    return { error: 'Failed to reset password. Please try again.' };
  }

  return null;
}
