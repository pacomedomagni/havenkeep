'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { setAuthCookies } from '@/lib/auth';

export async function signIn(formData: FormData) {
  const API_URL = process.env.API_URL || 'http://localhost:3000';
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;

  if (!email || !password) {
    return { error: 'Email and password are required' };
  }

  try {
    const response = await fetch(`${API_URL}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      return { error: data.error || data.message || 'Invalid credentials' };
    }

    const data = await response.json();

    // Reject users who are neither admin nor partner
    if (!data.user?.is_admin && !data.user?.is_partner) {
      return { error: 'Access restricted to partners and administrators' };
    }

    const cookieStore = await cookies();
    setAuthCookies(data.accessToken, data.refreshToken, cookieStore);
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  redirect('/dashboard');
}
