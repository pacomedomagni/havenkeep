'use client';

import Link from 'next/link';
import { useFormState, useFormStatus } from 'react-dom';
import { verifyMfa } from '../actions';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full bg-primary-600 hover:bg-primary-700 text-white font-medium py-2 px-4 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed"
    >
      {pending ? 'Verifying...' : 'Verify code'}
    </button>
  );
}

export default function MfaChallengePage() {
  const [state, action] = useFormState(verifyMfa, null);

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary-50 to-primary-100">
      <div className="max-w-md w-full bg-white rounded-lg shadow-xl p-8">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold text-gray-900">Two-factor authentication</h1>
          <p className="text-gray-600 mt-2">
            Enter the 6-digit code from your authenticator app. Backup codes work too.
          </p>
        </div>

        <form action={action} className="space-y-6">
          {state?.error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
              {state.error}
            </div>
          )}

          <div>
            <label htmlFor="code" className="block text-sm font-medium text-gray-700 mb-2">
              Authentication code
            </label>
            <input
              id="code"
              name="code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              required
              autoFocus
              maxLength={64}
              className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent tracking-widest text-center text-lg"
              placeholder="123456"
            />
          </div>

          <SubmitButton />

          <p className="text-center text-sm text-gray-600">
            <Link href="/login" className="text-primary-500 hover:text-primary-400">
              Back to sign in
            </Link>
          </p>
        </form>
      </div>
    </div>
  );
}
