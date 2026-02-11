import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import SignupsChart from '@/components/SignupsChart'
import ItemsChart from '@/components/ItemsChart'
import { createServerSupabaseClient } from '@/lib/supabase-server'
import { UsersIcon, CubeIcon, ChartBarIcon } from '@heroicons/react/24/outline'

async function getAnalyticsData() {
  const supabase = await createServerSupabaseClient()

  const [statsResult, signupsResult, itemsResult] = await Promise.all([
    supabase.from('admin_stats').select('*').single(),
    supabase.from('admin_daily_signups').select('*'),
    supabase.from('admin_daily_items').select('*'),
  ])

  return {
    stats: statsResult.data || {
      total_users: 0,
      premium_users: 0,
      total_items: 0,
      signups_last_7d: 0,
      signups_last_30d: 0,
      dau: 0,
      wau: 0,
      mau: 0,
    },
    signups: signupsResult.data || [],
    items: itemsResult.data || [],
  }
}

export default async function AnalyticsPage() {
  const { stats, signups, items } = await getAnalyticsData()

  const growthRate = stats.signups_last_7d > 0 && stats.signups_last_30d > 0
    ? ((stats.signups_last_7d / (stats.signups_last_30d / 4)) * 100 - 100).toFixed(1)
    : '0.0'

  const avgItemsPerUser = stats.total_users > 0
    ? (stats.total_items / stats.total_users).toFixed(1)
    : '0.0'

  return (
    <>
      <Header
        title="Analytics"
        subtitle="Platform metrics and insights"
      />

      <div className="p-8">
        {/* Key Metrics */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <StatsCard
            title="User Growth Rate"
            value={`${growthRate}%`}
            change={{
              value: `${stats.signups_last_7d} this week`,
              positive: parseFloat(growthRate) > 0,
            }}
            icon={<UsersIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Avg Items Per User"
            value={avgItemsPerUser}
            icon={<CubeIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Active Users (DAU/MAU)"
            value={`${stats.dau}/${stats.mau}`}
            change={{
              value: `${stats.wau} weekly`,
              positive: stats.dau > 0,
            }}
            icon={<ChartBarIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>

        {/* Charts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <SignupsChart data={signups} />
          <ItemsChart data={items} />
        </div>

        {/* Additional Metrics */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Retention Metrics</h3>
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <span className="text-haven-text-secondary">Daily Active Users</span>
                <span className="text-2xl font-bold text-white">{stats.dau}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-haven-text-secondary">Weekly Active Users</span>
                <span className="text-2xl font-bold text-white">{stats.wau}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-haven-text-secondary">Monthly Active Users</span>
                <span className="text-2xl font-bold text-white">{stats.mau}</span>
              </div>
              <div className="pt-4 border-t border-haven-border">
                <div className="flex justify-between items-center">
                  <span className="text-haven-text-secondary">DAU/MAU Ratio</span>
                  <span className="text-2xl font-bold text-haven-primary">
                    {stats.mau > 0 ? ((stats.dau / stats.mau) * 100).toFixed(1) : '0.0'}%
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Conversion Metrics</h3>
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <span className="text-haven-text-secondary">Total Users</span>
                <span className="text-2xl font-bold text-white">{stats.total_users}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-haven-text-secondary">Premium Users</span>
                <span className="text-2xl font-bold text-white">{stats.premium_users}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-haven-text-secondary">Free Users</span>
                <span className="text-2xl font-bold text-white">
                  {stats.total_users - stats.premium_users}
                </span>
              </div>
              <div className="pt-4 border-t border-haven-border">
                <div className="flex justify-between items-center">
                  <span className="text-haven-text-secondary">Conversion Rate</span>
                  <span className="text-2xl font-bold text-haven-primary">
                    {stats.total_users > 0
                      ? ((stats.premium_users / stats.total_users) * 100).toFixed(1)
                      : '0.0'}%
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}
