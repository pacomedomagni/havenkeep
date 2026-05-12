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
type ProfileCheck =
  | { kind: 'has-profile' }
  | { kind: 'no-profile' }
  | { kind: 'transient-error' };

async function checkPartnerProfile(): Promise<ProfileCheck> {
  try {
    const result = await serverApiClient<{ data: unknown }>('/api/v1/partners/me');
    return result.data ? { kind: 'has-profile' } : { kind: 'no-profile' };
  } catch (err) {
    // 404 is the expected "no partner row yet" answer — this user needs
    // the recovery form. Audit M1 (2nd pass): every other status (5xx,
    // network blip) is a TRANSIENT failure, not a confirmation that no
    // row exists. Don't render the form blind; surface a retry surface
    // instead — otherwise the user submits, hits 409, gets stuck.
    if (err instanceof ApiError && err.status === 404) {
      return { kind: 'no-profile' };
    }
    return { kind: 'transient-error' };
  }
}

export default async function RecoverProfilePage() {
  await requireAuth();
  const check = await checkPartnerProfile();
  if (check.kind === 'has-profile') {
    redirect('/dashboard');
  }
  if (check.kind === 'transient-error') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-haven-bg px-4">
        <div className="w-full max-w-md text-center">
          <h1 className="text-2xl font-bold text-white mb-3">We&apos;re having trouble</h1>
          <p className="text-haven-text-secondary mb-6">
            Couldn&apos;t confirm your profile state. The service may be briefly
            unavailable. Refresh this page in a moment.
          </p>
          <a
            href="/recover-profile"
            className="btn-primary inline-block"
          >
            Try again
          </a>
        </div>
      </div>
    );
  }
  return <RecoverProfileClient />;
}
