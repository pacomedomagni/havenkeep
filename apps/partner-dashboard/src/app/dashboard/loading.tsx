export default function DashboardLoading() {
  return (
    <div className="space-y-8">
      {/* Header skeleton */}
      <div>
        <div className="h-8 w-48 bg-haven-surface rounded-lg animate-pulse" />
        <div className="h-4 w-72 bg-haven-surface rounded-lg animate-pulse mt-2" />
      </div>

      {/* KPI cards skeleton */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="card animate-pulse">
            <div className="h-10 w-10 bg-haven-elevated rounded-lg mb-4" />
            <div className="h-8 w-20 bg-haven-elevated rounded-lg mb-2" />
            <div className="h-4 w-28 bg-haven-elevated rounded-lg" />
          </div>
        ))}
      </div>

      {/* Chart skeleton */}
      <div className="card animate-pulse">
        <div className="h-6 w-40 bg-haven-elevated rounded-lg mb-4" />
        <div className="h-64 bg-haven-elevated rounded-lg" />
      </div>
    </div>
  );
}
