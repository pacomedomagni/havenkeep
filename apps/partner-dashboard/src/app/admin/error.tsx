'use client'

import { useEffect } from 'react'

/**
 * Error boundary for the entire /admin segment (audit Ch10-W058).
 *
 * Internal error.message strings (DB driver text, stack-tail snippets, etc.)
 * are NOT rendered — the user gets a generic message and a reset button
 * (Ch10-W046, W059). The full error is logged to the console for the dev tools.
 */
export default function AdminError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    if (typeof console !== 'undefined') {
      // eslint-disable-next-line no-console
      console.error('Admin segment error', { name: error.name, digest: error.digest })
    }
  }, [error])

  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="card max-w-md text-center">
        <div className="mb-4 inline-flex h-12 w-12 items-center justify-center rounded-full bg-haven-error/15 text-haven-error">
          <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3m0 4h.01M4.93 4.93l14.14 14.14" />
          </svg>
        </div>
        <h2 className="text-lg font-semibold text-white mb-2">Something went wrong</h2>
        <p className="text-sm text-haven-text-secondary mb-6">
          We could not load this page. Please try again, or refresh if the problem persists.
        </p>
        <button onClick={reset} className="btn-primary">
          Try again
        </button>
      </div>
    </div>
  )
}
