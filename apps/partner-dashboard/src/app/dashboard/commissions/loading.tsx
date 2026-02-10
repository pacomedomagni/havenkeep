export default function CommissionsLoading() {
  return (
    <div className="space-y-6">
      <div>
        <div className="h-8 w-40 bg-haven-surface rounded-lg animate-pulse" />
        <div className="h-4 w-64 bg-haven-surface rounded-lg animate-pulse mt-2" />
      </div>

      {/* Summary cards skeleton */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {Array.from({ length: 2 }).map((_, i) => (
          <div key={i} className="card animate-pulse">
            <div className="h-4 w-32 bg-haven-elevated rounded-lg mb-2" />
            <div className="h-8 w-24 bg-haven-elevated rounded-lg" />
          </div>
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
