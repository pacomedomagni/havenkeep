/**
 * Skeleton fallback for /admin/* server components (audit Ch10-W057).
 * Matches the shape of the dashboard `loading.tsx` so layout shift between
 * skeleton and rendered content is minimal.
 */
export default function AdminLoading() {
  return (
    <div className="flex h-full flex-col gap-6 p-8" aria-busy="true" aria-live="polite">
      <div className="h-8 w-64 animate-pulse rounded bg-haven-elevated" />
      <div className="h-4 w-96 animate-pulse rounded bg-haven-elevated/70" />
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mt-2">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="h-28 animate-pulse rounded-lg bg-haven-surface border border-haven-border" />
        ))}
      </div>
      <div className="h-72 animate-pulse rounded-lg bg-haven-surface border border-haven-border" />
    </div>
  )
}
