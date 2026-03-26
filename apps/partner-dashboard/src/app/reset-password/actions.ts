'use server';

import { API_URL } from '@/lib/config';

export async function resetPassword(
  token: string,
  newPassword: string
): Promise<{ error: string } | null> {
  if (!token) {
    return { error: 'Reset token is missing' };
  }

  if (!newPassword || newPassword.length < 8) {
    return { error: 'Password must be at least 8 characters' };
  }

  try {
    const response = await fetch(`${API_URL}/api/v1/auth/reset-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, newPassword }),
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      if (response.status === 400) {
        return { error: data.error || data.message || 'Invalid or expired reset token. Please request a new one.' };
      }
      if (response.status === 429) {
        return { error: 'Too many requests. Please try again later.' };
      }
      return { error: data.error || data.message || 'Failed to reset password. Please try again.' };
    }

    return null;
  } catch {
    return { error: 'Unable to connect to the server' };
  }
}
