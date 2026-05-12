'use client';

import { useState } from 'react';
import Link from 'next/link';
import AuthForm from '@/components/auth-form';
import { signUp } from './actions';

export default function SignUpPage() {
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(formData: FormData) {
    setLoading(true);
    setError(null);

    try {
      const result = await signUp(formData);
      if (result?.error) {
        setError(result.error);
        setLoading(false);
      }
    } catch (err: any) {
      // signUp uses redirect() on success which throws NEXT_REDIRECT
      if (err?.digest?.startsWith('NEXT_REDIRECT')) {
        return;
      }
      setError(err?.message || 'An unexpected error occurred. Please try again.');
      setLoading(false);
    }
  }

  return (
    <AuthForm
      title="Create your account"
      subtitle="Join the HavenKeep partner program"
      footer={
        <p>
          Already have an account?{' '}
          <Link href="/login" className="text-haven-primary hover:underline">
            Sign in
          </Link>
        </p>
      }
    >
      <form action={handleSubmit} className="space-y-4">
        {error && (
          <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
            {error}
          </div>
        )}

        <div>
          <label htmlFor="fullName" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
            Full name
          </label>
          <input
            id="fullName"
            name="fullName"
            type="text"
            required
            className="input-field"
            placeholder="Jane Smith"
          />
        </div>

        <div>
          <label htmlFor="companyName" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
            Company or business name
          </label>
          <input
            id="companyName"
            name="companyName"
            type="text"
            required
            className="input-field"
            placeholder="e.g. Domagni Real Estate"
          />
          <p className="text-xs text-haven-text-tertiary mt-1">
            Shown on the gift email to homebuyers.
          </p>
        </div>

        <div>
          <label htmlFor="partnerType" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
            What do you do?
          </label>
          <select
            id="partnerType"
            name="partnerType"
            defaultValue="realtor"
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
          <label htmlFor="email" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
            Email
          </label>
          <input
            id="email"
            name="email"
            type="email"
            required
            className="input-field"
            placeholder="you@company.com"
          />
        </div>

        <div>
          <label htmlFor="password" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
            Password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            required
            minLength={8}
            className="input-field"
            placeholder="At least 8 characters"
          />
        </div>

        <div>
          <label htmlFor="confirmPassword" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
            Confirm password
          </label>
          <input
            id="confirmPassword"
            name="confirmPassword"
            type="password"
            required
            minLength={8}
            className="input-field"
            placeholder="Confirm your password"
          />
        </div>

        <button type="submit" disabled={loading} className="btn-primary w-full">
          {loading ? (
            <span className="inline-flex items-center gap-2">
              <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
              Creating account...
            </span>
          ) : (
            'Create account'
          )}
        </button>
      </form>
    </AuthForm>
  );
}
