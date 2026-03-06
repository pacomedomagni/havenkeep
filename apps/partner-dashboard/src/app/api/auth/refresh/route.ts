import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE, setAuthCookies } from '@/lib/auth';
import { API_URL } from '@/lib/config';

export async function POST() {
  const cookieStore = await cookies();
  const refreshToken = cookieStore.get(REFRESH_TOKEN_COOKIE)?.value;

  if (!refreshToken) {
    return NextResponse.json({ error: 'No refresh token' }, { status: 401 });
  }

  try {
    const response = await fetch(`${API_URL}/api/v1/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken }),
    });

    if (!response.ok) {
      return NextResponse.json({ error: 'Refresh failed' }, { status: 401 });
    }

    const data = await response.json();

    if (!data.accessToken) {
      return NextResponse.json({ error: 'Invalid refresh response' }, { status: 401 });
    }

    setAuthCookies(data.accessToken, data.refreshToken ?? refreshToken, cookieStore);

    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Refresh failed' }, { status: 500 });
  }
}
