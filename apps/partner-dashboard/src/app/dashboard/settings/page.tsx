'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { updatePartnerProfile } from './actions';
import { apiClient, ApiError } from '@/lib/api';
import { isSafeLogoUrl } from '@/lib/utils';

export default function SettingsPage() {
  const router = useRouter();
  const inflight = useRef<AbortController | null>(null);

  const [companyName, setCompanyName] = useState('');
  const [partnerType, setPartnerType] = useState('realtor');
  const [phone, setPhone] = useState('');
  const [serviceAreas, setServiceAreas] = useState('');
  const [brandColor, setBrandColor] = useState('#6C63FF');
  const [logoUrl, setLogoUrl] = useState('');
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [success, setSuccess] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void loadProfile();
    return () => {
      inflight.current?.abort();
      inflight.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function loadProfile() {
    inflight.current?.abort();
    const controller = new AbortController();
    inflight.current = controller;
    setProfileError(null);
    try {
      const result = await apiClient('/api/v1/partners/me');
      if (controller.signal.aborted) return;
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
      }
    } catch (err) {
      if (controller.signal.aborted) return;
      if (err instanceof ApiError && err.status === 401) {
        router.push('/login');
        return;
      }
      setProfileError(
        err instanceof ApiError
          ? err.message
          : 'Could not load your partner profile. Refresh to try again.'
      );
    } finally {
      if (!controller.signal.aborted) setInitialLoading(false);
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
      <div>
        <h1 className="text-2xl font-bold text-white">Settings</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Customize how your gift emails look to homebuyers.
        </p>
      </div>

      {profileError && (
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error flex items-center justify-between">
          <span>{profileError}</span>
          <button type="button" className="underline ml-3" onClick={() => void loadProfile()}>
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
            <label htmlFor="serviceAreas" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Service areas <span className="text-haven-text-tertiary">(optional)</span>
            </label>
            <input
              id="serviceAreas"
              type="text"
              value={serviceAreas}
              onChange={(e) => setServiceAreas(e.target.value)}
              className="input-field"
              placeholder="e.g. Austin, Round Rock"
            />
            <p className="text-xs text-haven-text-tertiary mt-1">
              Separate multiple areas with commas
            </p>
          </div>

          <div>
            <label htmlFor="brandColor" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Brand color
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
            <p className="text-xs text-haven-text-tertiary mt-1">Shown in gift emails</p>
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
    </div>
  );
}
