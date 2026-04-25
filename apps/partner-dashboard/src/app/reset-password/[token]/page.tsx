'use client';

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import AuthForm from '@/components/auth-form';
import { resetPassword } from '../actions';
import { validatePassword } from '@/lib/password-policy';

export default function ResetPasswordTokenPage() {
  const params = useParams();
  const token = typeof params?.token === 'string' ? params.token : '';

  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(formData: FormData) {
    setLoading(true);
    setError(null);

    const password = formData.get('password') as string;
    const confirmPassword = formData.get('confirmPassword') as string;

    if (password !== confirmPassword) {
      setError('Passwords do not match');
      setLoading(false);
      return;
    }

    const policy = validatePassword(password);
    if (!policy.ok) {
      setError(policy.reason || 'Password does not meet complexity rules');
      setLoading(false);
      return;
    }

    try {
      const result = await resetPassword(token, password);
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

  if (!token) {
    return (
      <AuthForm
        title="Invalid reset link"
        subtitle="This password reset link is invalid or has expired"
        footer={
          <p>
            <Link href="/forgot-password" className="text-haven-primary hover:underline">
              Request a new reset link
            </Link>
          </p>
        }
      >
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
          The reset link is missing a required token. Please request a new password reset.
        </div>
      </AuthForm>
    );
  }

  return (
    <AuthForm
      title="Set new password"
      subtitle="Enter your new password below"
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
        <div className="space-y-4">
          <div className="bg-green-500/10 border border-green-500/30 rounded-lg px-4 py-3 text-sm text-green-400">
            Your password has been reset successfully.
          </div>
          <Link href="/login" className="btn-primary w-full block text-center">
            Sign in with new password
          </Link>
        </div>
      ) : (
        <form action={handleSubmit} className="space-y-4">
          {error && (
            <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
              {error}
            </div>
          )}

          <div>
            <label htmlFor="password" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              New password
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              minLength={8}
              className="input-field"
              placeholder="At least 8 characters with uppercase, lowercase, number, special"
              autoComplete="new-password"
            />
          </div>

          <div>
            <label htmlFor="confirmPassword" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Confirm new password
            </label>
            <input
              id="confirmPassword"
              name="confirmPassword"
              type="password"
              required
              minLength={8}
              className="input-field"
              placeholder="Confirm your password"
              autoComplete="new-password"
            />
          </div>

          <button type="submit" disabled={loading} className="btn-primary w-full">
            {loading ? (
              <span className="inline-flex items-center gap-2">
                <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                Resetting password...
              </span>
            ) : (
              'Reset password'
            )}
          </button>
        </form>
      )}
    </AuthForm>
  );
}
