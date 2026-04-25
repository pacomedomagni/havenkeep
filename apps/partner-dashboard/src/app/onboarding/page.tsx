import { redirect } from 'next/navigation';
import { ApiError, requireAuth, serverApiClient } from '@/lib/auth';
import OnboardingClient from './client';

/**
 * Server-side gate (audit Ch10-W014). Anyone who already has a partner row
 * is forwarded to /dashboard rather than offered the onboarding form again.
 * The previous behavior allowed an onboarded partner to overwrite their
 * profile by re-running step 1.
 */
async function hasPartnerProfile(): Promise<boolean> {
  try {
    const result = await serverApiClient<{ data: unknown }>('/api/v1/partners/me');
    return !!result.data;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return false;
    // On 5xx / network failure: render the form rather than bouncing back to
    // /dashboard (which would also fail upstream).
    return false;
  }
}

export default async function OnboardingPage() {
  const user = await requireAuth();
  if (!user.isPartner && !user.isAdmin) {
    redirect('/unauthorized');
  }
  if (user.isPartner && (await hasPartnerProfile())) {
    redirect('/dashboard');
  }
  return <OnboardingClient />;
}
