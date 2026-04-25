'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { updatePartnerProfile } from './actions';
import { apiClient, ApiError } from '@/lib/api';
import { isSafeLogoUrl } from '@/lib/utils';

const STRIPE_HOSTS = new Set([
  'stripe.com',
  'connect.stripe.com',
  'dashboard.stripe.com',
  'checkout.stripe.com',
]);

export default function SettingsPage() {
  const router = useRouter();
  const inflight = useRef<AbortController | null>(null);

  const [companyName, setCompanyName] = useState('');
  const [partnerType, setPartnerType] = useState('realtor');
  const [phone, setPhone] = useState('');
  const [serviceAreas, setServiceAreas] = useState('');
  const [brandColor, setBrandColor] = useState('#6C63FF');
  const [logoUrl, setLogoUrl] = useState('');
  const [licenseNumber, setLicenseNumber] = useState('');
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [success, setSuccess] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Stripe Connect state
  const [stripeConnected, setStripeConnected] = useState(false);
  const [stripeOnboarded, setStripeOnboarded] = useState(false);
  const [stripeLoading, setStripeLoading] = useState(false);
  const [stripeError, setStripeError] = useState<string | null>(null);

  useEffect(() => {
    bootstrap();
    const refetch = () => {
      void loadStripeStatus();
    };
    window.addEventListener('focus', refetch);
    return () => {
      window.removeEventListener('focus', refetch);
      inflight.current?.abort();
      inflight.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /**
   * Audit Ch10-W033: load profile + stripe in parallel via allSettled so a
   * 5xx on one doesn't blank the entire page. Each result has its own UI
   * surface for the failure.
   *
   * Audit Ch10-W034: a 401 on profile fetch (the user's session has expired)
   * is forwarded to /login rather than rendered as a generic error.
   */
  async function bootstrap() {
    inflight.current?.abort();
    const controller = new AbortController();
    inflight.current = controller;
    const [profileResult, stripeResult] = await Promise.allSettled([
      loadProfileInner(),
      loadStripeStatusInner(),
    ]);
    if (controller.signal.aborted) return;

    if (profileResult.status === 'rejected') {
      const reason = profileResult.reason;
      if (reason instanceof ApiError && reason.status === 401) {
        router.push('/login');
        return;
      }
      setProfileError(
        reason instanceof ApiError
          ? reason.message
          : 'Could not load your partner profile. Refresh to try again.'
      );
    }
    if (stripeResult.status === 'rejected') {
      const reason = stripeResult.reason;
      if (reason instanceof ApiError && reason.status === 401) {
        router.push('/login');
        return;
      }
      setStripeError(
        reason instanceof ApiError
          ? reason.message
          : 'Could not load Stripe connection status.'
      );
    }
    setInitialLoading(false);
  }

  async function loadProfile() {
    try {
      await loadProfileInner();
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        router.push('/login');
        return;
      }
      setProfileError(
        err instanceof ApiError
          ? err.message
          : 'Could not load your partner profile. Refresh to try again.'
      );
    }
  }

  async function loadProfileInner() {
    const result = await apiClient('/api/v1/partners/me');
    const data = result.data as Record<string, unknown> | undefined;
    if (data) {
      setCompanyName((data.company_name as string) || '');
      setPartnerType((data.partner_type as string) || 'realtor');
      setPhone((data.phone as string) || '');
      setServiceAreas(
        Array.isArray(data.service_areas) ? (data.service_areas as string[]).join(', ') : ''
      );
      setBrandColor((data.brand_color as string) || '#6C63FF');
      setLogoUrl((data.logo_url as string) || '');
      setLicenseNumber((data.license_number as string) || '');
    }
  }

  async function loadStripeStatus() {
    try {
      await loadStripeStatusInner();
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        router.push('/login');
        return;
      }
      // Soft failure — leave the existing state alone.
    }
  }

  async function loadStripeStatusInner() {
    const result = await apiClient('/api/v1/partners/stripe-connect/status');
    const data = result.data as { connected?: boolean; onboarded?: boolean } | undefined;
    if (data) {
      setStripeConnected(!!data.connected);
      setStripeOnboarded(!!data.onboarded);
    }
  }

  async function handleStripeConnect() {
    setStripeLoading(true);
    setStripeError(null);
    try {
      const result = await apiClient('/api/v1/partners/stripe-connect/onboard', {
        method: 'POST',
      });
      const data = result.data as { url?: string } | undefined;
      const target = data?.url;
      if (!target) {
        setStripeError('The server did not return a Stripe URL. Please try again.');
        return;
      }
      // Audit Ch10-W022: validate that the URL is HTTPS *and* that its host
      // is on a small allowlist of Stripe-owned hostnames. The previous
      // `endsWith('.stripe.com')` check matched `stripe.com.attacker.com`.
      let parsed: URL;
      try {
        parsed = new URL(target);
      } catch {
        setStripeError('The server returned a malformed Stripe URL.');
        return;
      }
      if (parsed.protocol !== 'https:' || !STRIPE_HOSTS.has(parsed.hostname)) {
        setStripeError('Received an invalid onboarding URL. Please try again.');
        return;
      }
      window.location.href = parsed.toString();
    } catch (err) {
      setStripeError(
        err instanceof ApiError ? err.message : 'Failed to start Stripe onboarding'
      );
    } finally {
      setStripeLoading(false);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccess(false);

    if (!companyName.trim()) {
      setError('Company name is required.');
      setLoading(false);
      return;
    }

    if (logoUrl && !isSafeLogoUrl(logoUrl)) {
      // Audit Ch10-W024: reject the logo URL on the way in rather than
      // rendering an unsafe `<img src>` later.
      setError('Logo URL must be an http or https URL.');
      setLoading(false);
      return;
    }

    const formData = new FormData();
    formData.set('companyName', companyName.trim());
    formData.set('partnerType', partnerType);
    formData.set('phone', phone);
    formData.set('serviceAreas', serviceAreas);
    formData.set('brandColor', brandColor);
    formData.set('logoUrl', logoUrl);
    formData.set('licenseNumber', licenseNumber);

    const result = await updatePartnerProfile(formData);
    if (result?.error) {
      setError(result.error);
    } else {
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
    }
    setLoading(false);
  }

  if (initialLoading) {
    return (
      <div className="flex items-center justify-center h-64" aria-busy="true">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-haven-primary" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-2xl">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Settings</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Manage your partner profile
        </p>
      </div>

      {profileError && (
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error flex items-center justify-between">
          <span>{profileError}</span>
          <button
            type="button"
            className="underline ml-3"
            onClick={() => {
              setProfileError(null);
              void loadProfile();
            }}
          >
            Retry
          </button>
        </div>
      )}

      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-6">Partner Profile</h2>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
              {error}
            </div>
          )}

          {success && (
            <div className="bg-haven-active/10 border border-haven-active/30 rounded-lg px-4 py-3 text-sm text-haven-active">
              Profile updated successfully
            </div>
          )}

          <div>
            <label htmlFor="companyName" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Company name
            </label>
            <input
              id="companyName"
              type="text"
              value={companyName}
              onChange={(e) => setCompanyName(e.target.value)}
              className="input-field"
              required
            />
          </div>

          <div>
            <label htmlFor="partnerType" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Partner type
            </label>
            <select
              id="partnerType"
              value={partnerType}
              onChange={(e) => setPartnerType(e.target.value)}
              className="input-field"
            >
              <option value="realtor">Realtor</option>
              <option value="builder">Builder</option>
              <option value="contractor">Contractor</option>
              <option value="property_manager">Property Manager</option>
              <option value="other">Other</option>
            </select>
          </div>

          <div>
            <label htmlFor="phone" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Phone number <span className="text-haven-text-tertiary">(optional)</span>
            </label>
            <input
              id="phone"
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              className="input-field"
              placeholder="(555) 123-4567"
            />
          </div>

          <div>
            <label htmlFor="licenseNumber" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              License number <span className="text-haven-text-tertiary">(optional)</span>
            </label>
            <input
              id="licenseNumber"
              type="text"
              value={licenseNumber}
              onChange={(e) => setLicenseNumber(e.target.value)}
              className="input-field"
              placeholder="e.g. DRE#01234567"
              maxLength={100}
            />
          </div>

          <div>
            <label htmlFor="serviceAreas" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Service areas
            </label>
            <input
              id="serviceAreas"
              type="text"
              value={serviceAreas}
              onChange={(e) => setServiceAreas(e.target.value)}
              className="input-field"
              required
            />
            <p className="text-xs text-haven-text-tertiary mt-1">
              Separate multiple areas with commas
            </p>
          </div>

          <div>
            <label htmlFor="brandColor" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Brand Color
            </label>
            <div className="flex items-center gap-3">
              <input
                id="brandColor"
                type="color"
                value={brandColor}
                onChange={(e) => setBrandColor(e.target.value)}
                className="h-10 w-12 rounded border border-haven-border cursor-pointer bg-transparent p-0.5"
              />
              <input
                type="text"
                value={brandColor}
                onChange={(e) => setBrandColor(e.target.value)}
                className="input-field flex-1"
                placeholder="#6C63FF"
                pattern="^#[0-9A-Fa-f]{6}$"
                maxLength={7}
                aria-label="Brand color hex"
              />
            </div>
            <p className="text-xs text-haven-text-tertiary mt-1">
              Used in gift emails and partner branding
            </p>
          </div>

          <div>
            <label htmlFor="logoUrl" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Logo URL <span className="text-haven-text-tertiary">(optional)</span>
            </label>
            <input
              id="logoUrl"
              type="url"
              value={logoUrl}
              onChange={(e) => setLogoUrl(e.target.value)}
              className="input-field"
              placeholder="https://example.com/logo.png"
            />
            <p className="text-xs text-haven-text-tertiary mt-1">
              Must be an https URL. Displayed in gift emails sent to homebuyers.
            </p>
          </div>

          <div className="pt-2">
            <button type="submit" disabled={loading} className="btn-primary" aria-busy={loading}>
              {loading ? (
                <span className="inline-flex items-center gap-2">
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" aria-hidden="true">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  Saving...
                </span>
              ) : (
                'Save changes'
              )}
            </button>
          </div>
        </form>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-6">Payments</h2>

        {stripeError && (
          <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error mb-4">
            {stripeError}
          </div>
        )}

        {stripeOnboarded ? (
          <div className="flex items-center gap-3">
            <span className="inline-flex items-center gap-1.5 rounded-full bg-haven-active/15 px-3 py-1 text-sm font-medium text-haven-active">
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} aria-hidden="true">
                <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
              </svg>
              Stripe Connected
            </span>
            <p className="text-sm text-haven-text-secondary">
              Your Stripe account is connected and ready to receive payouts.
            </p>
          </div>
        ) : stripeConnected ? (
          <div className="space-y-3">
            <div className="flex items-center gap-3">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-yellow-500/15 px-3 py-1 text-sm font-medium text-yellow-400">
                Onboarding Incomplete
              </span>
            </div>
            <p className="text-sm text-haven-text-secondary">
              Your Stripe account has been created but onboarding is not yet complete. Please finish setup to receive payouts.
            </p>
            <button
              onClick={handleStripeConnect}
              disabled={stripeLoading}
              className="btn-primary"
            >
              {stripeLoading ? 'Connecting…' : 'Continue Stripe Setup'}
            </button>
          </div>
        ) : (
          <div className="space-y-3">
            <p className="text-sm text-haven-text-secondary">
              Connect your Stripe account to receive commission payouts directly to your bank account.
            </p>
            <button
              onClick={handleStripeConnect}
              disabled={stripeLoading}
              className="btn-primary"
            >
              {stripeLoading ? 'Connecting…' : 'Connect Stripe Account'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
