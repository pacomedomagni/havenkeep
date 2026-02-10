'use client';

import { useState } from 'react';
import OnboardingSteps from '@/components/onboarding-steps';
import { createPartnerProfile } from './actions';

export default function OnboardingPage() {
  const [step, setStep] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Step 1 fields
  const [companyName, setCompanyName] = useState('');
  const [partnerType, setPartnerType] = useState('realtor');

  // Step 2 fields
  const [licenseNumber, setLicenseNumber] = useState('');
  const [serviceAreas, setServiceAreas] = useState('');

  async function handleSubmit() {
    setLoading(true);
    setError(null);

    const formData = new FormData();
    formData.set('companyName', companyName);
    formData.set('partnerType', partnerType);
    formData.set('licenseNumber', licenseNumber);
    formData.set('serviceAreas', serviceAreas);

    const result = await createPartnerProfile(formData);
    if (result?.error) {
      setError(result.error);
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-haven-bg px-4">
      <div className="w-full max-w-lg">
        {/* Logo */}
        <div className="text-center mb-6">
          <div className="inline-flex items-center justify-center w-14 h-14 bg-haven-primary/20 rounded-xl mb-4">
            <svg
              className="w-8 h-8 text-haven-primary"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
              />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-white">Set up your partner profile</h1>
          <p className="text-haven-text-secondary text-sm mt-1">
            Tell us about your business to get started
          </p>
        </div>

        <OnboardingSteps currentStep={step} totalSteps={2} />

        <div className="card">
          {error && (
            <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error mb-4">
              {error}
            </div>
          )}

          {step === 1 && (
            <div className="space-y-4">
              <h2 className="text-lg font-semibold text-white mb-4">Company Information</h2>

              <div>
                <label htmlFor="companyName" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
                  Company name
                </label>
                <input
                  id="companyName"
                  type="text"
                  required
                  value={companyName}
                  onChange={(e) => setCompanyName(e.target.value)}
                  className="input-field"
                  placeholder="Your company or business name"
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

              <button
                type="button"
                onClick={() => {
                  if (!companyName.trim()) {
                    setError('Company name is required');
                    return;
                  }
                  setError(null);
                  setStep(2);
                }}
                className="btn-primary w-full mt-2"
              >
                Continue
              </button>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4">
              <h2 className="text-lg font-semibold text-white mb-4">Business Details</h2>

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
                  placeholder="e.g., RE-12345678"
                />
              </div>

              <div>
                <label htmlFor="serviceAreas" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
                  Service areas
                </label>
                <input
                  id="serviceAreas"
                  type="text"
                  required
                  value={serviceAreas}
                  onChange={(e) => setServiceAreas(e.target.value)}
                  className="input-field"
                  placeholder="e.g., Austin, Dallas, Houston (comma-separated)"
                />
                <p className="text-xs text-haven-text-tertiary mt-1">
                  Separate multiple areas with commas
                </p>
              </div>

              <div className="flex gap-3 mt-2">
                <button
                  type="button"
                  onClick={() => setStep(1)}
                  className="btn-secondary flex-1"
                >
                  Back
                </button>
                <button
                  type="button"
                  onClick={handleSubmit}
                  disabled={loading || !serviceAreas.trim()}
                  className="btn-primary flex-1"
                >
                  {loading ? (
                    <span className="inline-flex items-center gap-2">
                      <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                      </svg>
                      Creating...
                    </span>
                  ) : (
                    'Complete setup'
                  )}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
