'use client';

import { useState, useEffect } from 'react';
import { updatePartnerProfile } from './actions';
import { apiClient } from '@/lib/api';

export default function SettingsPage() {
  const [companyName, setCompanyName] = useState('');
  const [partnerType, setPartnerType] = useState('realtor');
  const [phone, setPhone] = useState('');
  const [serviceAreas, setServiceAreas] = useState('');
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadProfile();
  }, []);

  async function loadProfile() {
    try {
      const result = await apiClient('/api/v1/partners/me');
      const data = result.data as any;

      if (data) {
        setCompanyName(data.company_name || '');
        setPartnerType(data.partner_type || 'realtor');
        setPhone(data.phone || '');
        setServiceAreas('');
      }
    } catch (err) {
      console.error('Error loading profile:', err);
    } finally {
      setInitialLoading(false);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccess(false);

    const formData = new FormData();
    formData.set('companyName', companyName);
    formData.set('partnerType', partnerType);
    formData.set('phone', phone);
    formData.set('serviceAreas', serviceAreas);

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
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-haven-primary"></div>
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

      {/* Profile Form */}
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

          <div className="pt-2">
            <button type="submit" disabled={loading} className="btn-primary">
              {loading ? (
                <span className="inline-flex items-center gap-2">
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
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
