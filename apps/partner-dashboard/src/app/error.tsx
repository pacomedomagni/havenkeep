'use client';

import { useEffect } from 'react';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  // Log to console only — never render `error.message` (audit Ch10-W046, W059).
  useEffect(() => {
    // eslint-disable-next-line no-console
    console.error('App error:', { name: error.name, digest: error.digest });
  }, [error]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-haven-background">
      <div className="text-center max-w-md mx-auto p-8">
        <div className="w-16 h-16 bg-haven-error/10 rounded-full flex items-center justify-center mx-auto mb-6">
          <svg className="w-8 h-8 text-haven-error" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        </div>
        <h2 className="text-xl font-bold text-white mb-2">Something went wrong</h2>
        <p className="text-haven-text-secondary mb-6">
          We could not load this page. Please try again, or refresh if the problem persists.
        </p>
        <button
          onClick={reset}
          className="btn-primary"
        >
          Try Again
        </button>
      </div>
    </div>
  );
}
