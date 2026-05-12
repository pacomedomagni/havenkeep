'use client';

import { useRef, useState } from 'react';
import { recoverPartnerProfile } from './actions';

/**
 * Single-screen recovery: account exists, partner row doesn't. One submit
 * creates the partner row and the action redirects to /dashboard.
 *
 * `submitGuard` ref makes the submit single-flight so a double-click can't
 * create two partner rows — also covered server-side by the
 * 'user is already registered as a partner' check, but defense-in-depth.
 */
export default function RecoverProfileClient() {
  const submitGuard = useRef(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [companyName, setCompanyName] = useState('');
  const [partnerType, setPartnerType] = useState('realtor');

  async function handleSubmit() {
    if (submitGuard.current) return;
    submitGuard.current = true;
    setLoading(true);
    setError(null);

    try {
      if (!companyName.trim()) {
        setError('Company or business name is required');
        return;
      }

      const formData = new FormData();
      formData.set('companyName', companyName.trim());
      formData.set('partnerType', partnerType);

      const result = await recoverPartnerProfile(formData);
      if (result?.error) {
        setError(result.error);
      }
    } finally {
      setLoading(false);
      submitGuard.current = false;
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-haven-bg px-4">
      <div className="w-full max-w-lg">
        <div className="text-center mb-6">
          <h1 className="text-2xl font-bold text-white">Finish setting up</h1>
          <p className="text-haven-text-secondary text-sm mt-2">
            Your account is created — we just need a couple of details before
            you can send gifts.
          </p>
        </div>

        <div className="card">
          {error && (
            <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error mb-4">
              {error}
            </div>
          )}

          <div className="space-y-4">
            <div>
              <label htmlFor="companyName" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
                Company or your name
              </label>
              <input
                id="companyName"
                type="text"
                required
                value={companyName}
                onChange={(e) => setCompanyName(e.target.value)}
                className="input-field"
                placeholder="e.g. Domagni Real Estate"
              />
              <p className="text-xs text-haven-text-tertiary mt-1">
                Shown on every gift email to homebuyers.
              </p>
            </div>

            <div>
              <label htmlFor="partnerType" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
                What do you do?
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

            <button
              type="button"
              onClick={handleSubmit}
              disabled={loading || !companyName.trim()}
              className="btn-primary w-full mt-2"
              aria-busy={loading}
            >
              {loading ? (
                <span className="inline-flex items-center gap-2">
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" aria-hidden="true">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  Setting up...
                </span>
              ) : (
                'Continue to dashboard'
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
