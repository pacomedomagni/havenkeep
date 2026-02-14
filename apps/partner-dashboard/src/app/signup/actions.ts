'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { setAuthCookies } from '@/lib/auth';

const API_URL = process.env.API_URL || 'http://localhost:3000';

export async function signUp(formData: FormData) {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const confirmPassword = formData.get('confirmPassword') as string;
  const fullName = formData.get('fullName') as string;

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { error: 'Please enter a valid email address' };
  }

  if (password !== confirmPassword) {
    return { error: 'Passwords do not match' };
  }

  if (password.length < 8) {
    return { error: 'Password must be at least 8 characters with uppercase, lowercase, number, and special character' };
  }

  try {
    const response = await fetch(`${API_URL}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, fullName: fullName || email.split('@')[0] }),
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      return { error: data.error || data.message || 'Registration failed' };
    }

    const data = await response.json();

    const cookieStore = await cookies();
    setAuthCookies(data.accessToken, data.refreshToken, cookieStore);
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  redirect('/onboarding');
}
