'use client'

interface PaginationProps {
  page: number
  totalPages: number
  onPageChange: (page: number) => void
}

export default function Pagination({ page, totalPages, onPageChange }: PaginationProps) {
  const getPageNumbers = (): (number | '...')[] => {
    const pages: (number | '...')[] = []

    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) {
        pages.push(i)
      }
      return pages
    }

    // Always show first page
    pages.push(1)

    if (page > 3) {
      pages.push('...')
    }

    // Show pages around the current page
    const start = Math.max(2, page - 1)
    const end = Math.min(totalPages - 1, page + 1)

    for (let i = start; i <= end; i++) {
      pages.push(i)
    }

    if (page < totalPages - 2) {
      pages.push('...')
    }

    // Always show last page
    pages.push(totalPages)

    return pages
  }

  if (totalPages <= 1) return null

  const pageNumbers = getPageNumbers()

  return (
    <div className="flex items-center justify-center gap-1">
      <button
        onClick={() => onPageChange(page - 1)}
        disabled={page <= 1}
        className="px-3 py-1.5 text-sm font-medium rounded-md transition
          bg-haven-surface border border-haven-border text-haven-text-secondary
          hover:text-white hover:bg-haven-surface/80
          disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-haven-surface disabled:hover:text-haven-text-secondary"
      >
        Prev
      </button>

      {pageNumbers.map((p, idx) =>
        p === '...' ? (
          <span
            key={`ellipsis-${idx}`}
            className="px-2 py-1.5 text-sm text-haven-text-secondary"
          >
            ...
          </span>
        ) : (
          <button
            key={p}
            onClick={() => onPageChange(p)}
            className={`px-3 py-1.5 text-sm font-medium rounded-md transition border
              ${
                p === page
                  ? 'bg-haven-primary text-white border-haven-primary'
                  : 'bg-haven-surface border-haven-border text-haven-text-secondary hover:text-white hover:bg-haven-surface/80'
              }
            `}
          >
            {p}
          </button>
        )
      )}

      <button
        onClick={() => onPageChange(page + 1)}
        disabled={page >= totalPages}
        className="px-3 py-1.5 text-sm font-medium rounded-md transition
          bg-haven-surface border border-haven-border text-haven-text-secondary
          hover:text-white hover:bg-haven-surface/80
          disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-haven-surface disabled:hover:text-haven-text-secondary"
      >
        Next
      </button>
    </div>
  )
}
