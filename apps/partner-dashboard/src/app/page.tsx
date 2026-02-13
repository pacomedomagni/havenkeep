import { redirect } from 'next/navigation';

// Root page — middleware handles the redirect to /dashboard or /login.
// This is a fallback in case middleware is bypassed.
export default function Home() {
  redirect('/login');
}
