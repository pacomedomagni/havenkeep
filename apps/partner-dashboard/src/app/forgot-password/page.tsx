'use client';

import { useState } from 'react';
import Link from 'next/link';
import AuthForm from '@/components/auth-form';
import { requestPasswordReset } from './actions';

export default function ForgotPasswordPage() {
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(formData: FormData) {
    setLoading(true);
    setError(null);

    try {
      const result = await requestPasswordReset(formData);
      if (result?.error) {
        setError(result.error);
      } else {
        setSuccess(true);
      }
    } catch {
      setError('An unexpected error occurred. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <AuthForm
      title="Reset your password"
      subtitle="Enter your email and we'll send you a reset link"
      footer={
        <p>
          Remember your password?{' '}
          <Link href="/login" className="text-haven-primary hover:underline">
            Sign in
          </Link>
        </p>
      }
    >
      {success ? (
        <div className="bg-green-500/10 border border-green-500/30 rounded-lg px-4 py-3 text-sm text-green-400">
          If an account exists with that email, a password reset link has been sent. Please check your inbox.
        </div>
      ) : (
        <form action={handleSubmit} className="space-y-4">
          {error && (
            <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
              {error}
            </div>
          )}

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

          <button type="submit" disabled={loading} className="btn-primary w-full">
            {loading ? (
              <span className="inline-flex items-center gap-2">
                <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                Sending reset link...
              </span>
            ) : (
              'Send reset link'
            )}
          </button>
        </form>
      )}
    </AuthForm>
  );
}
