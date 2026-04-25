'use client';

import { useEffect } from 'react';

/**
 * Dashboard error boundary. `error.message` is intentionally NOT rendered to
 * the user — internal errors leak DB driver text, stack-trace tails, and
 * (per audit Ch10-W046, W059) sometimes JWT fragments. Logged to console for
 * the dev tools, replaced with a generic message in the UI.
 */
export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // eslint-disable-next-line no-console
    console.error('Dashboard error:', { name: error.name, digest: error.digest });
  }, [error]);

  return (
    <div className="flex items-center justify-center min-h-[400px]">
      <div className="card max-w-md w-full text-center">
        <div className="w-12 h-12 bg-haven-error/20 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-6 h-6 text-haven-error" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        </div>
        <h2 className="text-lg font-semibold text-white mb-2">Something went wrong</h2>
        <p className="text-sm text-haven-text-secondary mb-6">
          We could not load this page. Please try again, or refresh if the problem persists.
        </p>
        <button onClick={reset} className="btn-primary px-6 py-2">
          Try again
        </button>
      </div>
    </div>
  );
}
