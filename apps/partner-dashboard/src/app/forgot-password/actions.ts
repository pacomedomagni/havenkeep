'use server';

import { API_URL } from '@/lib/config';
import { fetchWithTimeout } from '@/lib/fetch';

export async function requestPasswordReset(
  formData: FormData
): Promise<{ error: string } | null> {
  const email = formData.get('email') as string;

  if (!email) {
    return { error: 'Email is required' };
  }

  try {
    const response = await fetchWithTimeout(`${API_URL}/api/v1/auth/forgot-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      // Don't reveal whether the email exists — return success regardless
      // unless it's a validation error
      if (response.status === 400) {
        return { error: data.error || data.message || 'Please enter a valid email address' };
      }
      if (response.status === 429) {
        return { error: 'Too many requests. Please try again later.' };
      }
    }

    // Always return success to prevent email enumeration
    return null;
  } catch {
    return { error: 'Unable to connect to the server' };
  }
}
