export default function ReferralsLoading() {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="h-8 w-32 bg-haven-surface rounded-lg animate-pulse" />
          <div className="h-4 w-56 bg-haven-surface rounded-lg animate-pulse mt-2" />
        </div>
        <div className="h-10 w-40 bg-haven-surface rounded-lg animate-pulse" />
      </div>

      {/* Filter tabs skeleton */}
      <div className="flex gap-2">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-9 w-24 bg-haven-surface rounded-lg animate-pulse" />
        ))}
      </div>

      {/* Table skeleton */}
      <div className="card animate-pulse">
        <div className="space-y-4">
          <div className="h-10 bg-haven-elevated rounded-lg" />
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="h-12 bg-haven-elevated rounded-lg" />
          ))}
        </div>
      </div>
    </div>
  );
}
