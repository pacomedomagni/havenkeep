import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import { serverApiClient } from '@/lib/auth'
import { UsersIcon, CubeIcon, CurrencyDollarIcon, ChartBarIcon } from '@heroicons/react/24/outline'

async function getAdminStats() {
  try {
    const { stats } = await serverApiClient<{ stats: any }>('/api/v1/admin/stats/full')
    return stats
  } catch {
    return {
      total_users: 0,
      premium_users: 0,
      total_items: 0,
      items_last_24h: 0,
      signups_last_24h: 0,
      signups_last_7d: 0,
      signups_last_30d: 0,
      total_value_protected: 0,
      dau: 0,
      wau: 0,
      mau: 0,
    }
  }
}

async function getRecentUsers() {
  try {
    const { users } = await serverApiClient<{ users: any[] }>('/api/v1/admin/users?page=1&limit=5')
    return users || []
  } catch {
    return []
  }
}

export default async function DashboardPage() {
  const [stats, recentUsers] = await Promise.all([
    getAdminStats(),
    getRecentUsers(),
  ])

  const premiumPercentage = Number(stats.total_users) > 0
    ? ((Number(stats.premium_users) / Number(stats.total_users)) * 100).toFixed(1)
    : '0.0'

  return (
    <>
      <Header
        title="Dashboard"
        subtitle="Overview of your HavenKeep platform"
      />

      <div className="p-8">
        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <StatsCard
            title="Total Users"
            value={Number(stats.total_users).toLocaleString()}
            change={{
              value: `${stats.signups_last_7d} this week`,
              positive: Number(stats.signups_last_7d) > 0,
            }}
            icon={<UsersIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Premium Users"
            value={Number(stats.premium_users).toLocaleString()}
            change={{
              value: `${premiumPercentage}% conversion`,
              positive: parseFloat(premiumPercentage) > 10,
            }}
            icon={<CurrencyDollarIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Total Items"
            value={Number(stats.total_items).toLocaleString()}
            change={{
              value: `${stats.items_last_24h} today`,
              positive: Number(stats.items_last_24h) > 0,
            }}
            icon={<CubeIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Daily Active Users"
            value={Number(stats.dau).toLocaleString()}
            change={{
              value: `${stats.wau} weekly`,
              positive: Number(stats.dau) > 0,
            }}
            icon={<ChartBarIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>

        {/* Value Protected */}
        <div className="bg-gradient-to-r from-haven-primary to-purple-600 rounded-lg p-6 mb-8 text-white">
          <h3 className="text-lg font-medium mb-2">Total Value Protected</h3>
          <p className="text-4xl font-bold">
            ${Number(stats.total_value_protected).toLocaleString()}
          </p>
          <p className="text-white/70 mt-2">
            Across {Number(stats.total_items).toLocaleString()} items for {Number(stats.total_users).toLocaleString()} users
          </p>
        </div>

        {/* Recent Activity */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Recent Users */}
          <div className="card p-0">
            <div className="px-6 py-4 border-b border-haven-border">
              <h3 className="text-lg font-semibold text-white">Recent Signups</h3>
            </div>
            <div className="divide-y divide-haven-border">
              {recentUsers.length === 0 ? (
                <div className="px-6 py-8 text-center text-haven-text-tertiary">
                  No users yet
                </div>
              ) : (
                recentUsers.map((user: any) => (
                  <div key={user.id} className="px-6 py-4 hover:bg-haven-elevated/50 transition-colors">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-medium text-white">{user.full_name}</p>
                        <p className="text-sm text-haven-text-secondary">{user.email}</p>
                      </div>
                      <div className="text-right">
                        <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                          user.plan === 'premium'
                            ? 'bg-haven-primary/20 text-haven-primary'
                            : 'bg-haven-elevated text-haven-text-secondary'
                        }`}>
                          {user.plan}
                        </span>
                        <p className="text-xs text-haven-text-tertiary mt-1">
                          {new Date(user.created_at).toLocaleDateString()}
                        </p>
                      </div>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* Quick Stats */}
          <div className="card p-0">
            <div className="px-6 py-4 border-b border-haven-border">
              <h3 className="text-lg font-semibold text-white">Activity Summary</h3>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex items-center justify-between">
                <span className="text-haven-text-secondary">Signups (24h)</span>
                <span className="text-2xl font-bold text-white">{stats.signups_last_24h}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-haven-text-secondary">Signups (7d)</span>
                <span className="text-2xl font-bold text-white">{stats.signups_last_7d}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-haven-text-secondary">Signups (30d)</span>
                <span className="text-2xl font-bold text-white">{stats.signups_last_30d}</span>
              </div>
              <div className="pt-4 border-t border-haven-border">
                <div className="flex items-center justify-between">
                  <span className="text-haven-text-secondary">Monthly Active Users</span>
                  <span className="text-2xl font-bold text-haven-primary">{stats.mau}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}
