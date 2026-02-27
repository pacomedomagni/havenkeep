'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { setAuthCookies } from '@/lib/auth';

export async function signIn(
  _prevState: { error: string } | null,
  formData: FormData
): Promise<{ error: string }> {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;

  if (!email || !password) {
    return { error: 'Email and password are required' };
  }

  const API_URL = process.env.API_URL || 'http://localhost:3000';
  let destination = '/dashboard';

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

    if (!data.user?.is_admin && !data.user?.is_partner) {
      return { error: 'Access restricted to partners and administrators' };
    }

    const cookieStore = await cookies();
    setAuthCookies(data.accessToken, data.refreshToken, cookieStore);

    const payload = JSON.parse(
      Buffer.from(data.accessToken.split('.')[1], 'base64url').toString()
    );
    if (payload.isAdmin === true) destination = '/admin';
  } catch {
    return { error: 'Unable to connect to the server' };
  }

  redirect(destination);
}
