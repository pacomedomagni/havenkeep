interface StatsCardProps {
  title: string
  value: string | number
  change?: {
    value: string
    positive: boolean
  }
  icon?: React.ReactNode
}

export default function StatsCard({ title, value, change, icon }: StatsCardProps) {
  return (
    <div className="card">
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <p className="text-sm font-medium text-haven-text-secondary">{title}</p>
          <p className="text-3xl font-bold text-white mt-2">{value}</p>
          {change && (
            <p className="text-sm mt-2">
              <span
                className={`font-medium ${
                  change.positive ? 'text-haven-active' : 'text-haven-error'
                }`}
              >
                {change.positive ? '↑' : '↓'} {change.value}
              </span>
              <span className="text-haven-text-tertiary ml-1">vs last period</span>
            </p>
          )}
        </div>
        {icon && (
          <div className="ml-4 p-3 bg-haven-primary/10 rounded-lg">
            {icon}
          </div>
        )}
      </div>
    </div>
  )
}
