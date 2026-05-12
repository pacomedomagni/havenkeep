import { redirect } from 'next/navigation';
import { requireAuth, serverApiClient, ApiError } from '@/lib/auth';
import RecoverProfileClient from './client';

/**
 * Recovery surface for users who completed signup (have an account + tokens)
 * but the second-leg `/partners/register` call failed, leaving them
 * authenticated with no partner row. Middleware routes them here when
 * `is_partner=false && is_admin=false` and the pathname isn't already
 * `/recover-profile` (so we don't loop).
 *
 * If the user actually already has a partner row, we redirect them straight
 * to /dashboard — middleware's role-check cache is up to 30s stale, so a
 * race between "the partner row was just created by another tab" and
 * "middleware still sees no partner" must resolve here, not by trapping the
 * user on this page.
 */
async function hasPartnerProfile(): Promise<boolean> {
  try {
    const result = await serverApiClient<{ data: unknown }>('/api/v1/partners/me');
    return !!result.data;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return false;
    return false;
  }
}

export default async function RecoverProfilePage() {
  await requireAuth();
  if (await hasPartnerProfile()) {
    redirect('/dashboard');
  }
  return <RecoverProfileClient />;
}
