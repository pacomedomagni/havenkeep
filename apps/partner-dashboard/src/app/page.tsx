import { redirect } from 'next/navigation';
import { getTokens, isTokenExpired } from '@/lib/auth';

export default async function Home() {
  const tokens = await getTokens();

  if (tokens && !isTokenExpired(tokens.accessToken)) {
    redirect('/dashboard');
  } else {
    redirect('/login');
  }
}
