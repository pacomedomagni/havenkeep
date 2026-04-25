'use client'

import { useRouter, useSearchParams, usePathname } from 'next/navigation'
import { ChevronLeftIcon, ChevronRightIcon } from '@heroicons/react/24/outline'

interface PaginationProps {
  page: number
  totalPages: number
  total: number
}

/**
 * Pagination links preserve the entire current querystring (audit Ch10-W056).
 * Switching pages while a status / search filter is active no longer drops
 * the filter on the floor.
 */
export default function Pagination({ page, totalPages, total }: PaginationProps) {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()

  if (totalPages <= 1) return null

  function goToPage(newPage: number) {
    if (newPage < 1 || newPage > totalPages) return
    const params = new URLSearchParams(searchParams?.toString() ?? '')
    params.set('page', String(newPage))
    router.push(`${pathname}?${params.toString()}`)
  }

  return (
    <nav
      className="flex items-center justify-between border-t border-haven-border px-4 py-3 sm:px-6 mt-4"
      aria-label="Pagination"
    >
      <div className="text-sm text-haven-text-secondary">{total} total results</div>
      <div className="flex items-center gap-2">
        <button
          onClick={() => goToPage(page - 1)}
          disabled={page <= 1}
          className="inline-flex items-center rounded-md border border-haven-border bg-haven-surface px-3 py-2 text-sm font-medium text-haven-text-secondary hover:bg-haven-elevated disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <ChevronLeftIcon className="h-4 w-4 mr-1" aria-hidden="true" />
          Previous
        </button>
        <span className="text-sm text-haven-text-secondary" aria-live="polite">
          Page {page} of {totalPages}
        </span>
        <button
          onClick={() => goToPage(page + 1)}
          disabled={page >= totalPages}
          className="inline-flex items-center rounded-md border border-haven-border bg-haven-surface px-3 py-2 text-sm font-medium text-haven-text-secondary hover:bg-haven-elevated disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Next
          <ChevronRightIcon className="h-4 w-4 ml-1" aria-hidden="true" />
        </button>
      </div>
    </nav>
  )
}
