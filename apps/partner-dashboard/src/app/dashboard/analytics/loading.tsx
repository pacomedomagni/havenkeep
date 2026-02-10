export default function AnalyticsLoading() {
  return (
    <div className="space-y-6">
      <div>
        <div className="h-8 w-32 bg-haven-surface rounded-lg animate-pulse" />
        <div className="h-4 w-56 bg-haven-surface rounded-lg animate-pulse mt-2" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className={`card animate-pulse ${i === 2 ? 'lg:col-span-2' : ''}`}>
            <div className="h-6 w-40 bg-haven-elevated rounded-lg mb-4" />
            <div className="h-72 bg-haven-elevated rounded-lg" />
          </div>
        ))}
      </div>
    </div>
  );
}
