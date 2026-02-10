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
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <p className="text-sm font-medium text-gray-600">{title}</p>
          <p className="text-3xl font-bold text-gray-900 mt-2">{value}</p>
          {change && (
            <p className="text-sm mt-2">
              <span
                className={`font-medium ${
                  change.positive ? 'text-green-600' : 'text-red-600'
                }`}
              >
                {change.positive ? '↑' : '↓'} {change.value}
              </span>
              <span className="text-gray-600 ml-1">vs last period</span>
            </p>
          )}
        </div>
        {icon && (
          <div className="ml-4 p-3 bg-primary-50 rounded-lg">
            {icon}
          </div>
        )}
      </div>
    </div>
  )
}
