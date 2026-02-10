import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import { createServerSupabaseClient } from '@/lib/supabase-server'
import { UsersIcon, CubeIcon, CurrencyDollarIcon, ChartBarIcon } from '@heroicons/react/24/outline'

async function getAdminStats() {
  const supabase = await createServerSupabaseClient()
  
  const { data: stats } = await supabase
    .from('admin_stats')
    .select('*')
    .single()

  return stats || {
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

async function getRecentUsers() {
  const supabase = await createServerSupabaseClient()
  
  const { data: users } = await supabase
    .from('users')
    .select('id, email, full_name, created_at, plan')
    .order('created_at', { ascending: false })
    .limit(5)

  return users || []
}

export default async function DashboardPage() {
  const stats = await getAdminStats()
  const recentUsers = await getRecentUsers()

  const premiumPercentage = stats.total_users > 0 
    ? ((stats.premium_users / stats.total_users) * 100).toFixed(1)
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
            value={stats.total_users.toLocaleString()}
            change={{
              value: `${stats.signups_last_7d} this week`,
              positive: stats.signups_last_7d > 0,
            }}
            icon={<UsersIcon className="h-6 w-6 text-primary-600" />}
          />
          
          <StatsCard
            title="Premium Users"
            value={stats.premium_users.toLocaleString()}
            change={{
              value: `${premiumPercentage}% conversion`,
              positive: parseFloat(premiumPercentage) > 10,
            }}
            icon={<CurrencyDollarIcon className="h-6 w-6 text-primary-600" />}
          />
          
          <StatsCard
            title="Total Items"
            value={stats.total_items.toLocaleString()}
            change={{
              value: `${stats.items_last_24h} today`,
              positive: stats.items_last_24h > 0,
            }}
            icon={<CubeIcon className="h-6 w-6 text-primary-600" />}
          />
          
          <StatsCard
            title="Daily Active Users"
            value={stats.dau.toLocaleString()}
            change={{
              value: `${stats.wau} weekly`,
              positive: stats.dau > 0,
            }}
            icon={<ChartBarIcon className="h-6 w-6 text-primary-600" />}
          />
        </div>

        {/* Value Protected */}
        <div className="bg-gradient-to-r from-primary-500 to-primary-700 rounded-lg shadow p-6 mb-8 text-white">
          <h3 className="text-lg font-medium mb-2">Total Value Protected</h3>
          <p className="text-4xl font-bold">
            ${Number(stats.total_value_protected).toLocaleString()}
          </p>
          <p className="text-primary-100 mt-2">
            Across {stats.total_items.toLocaleString()} items for {stats.total_users.toLocaleString()} users
          </p>
        </div>

        {/* Recent Activity */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Recent Users */}
          <div className="bg-white rounded-lg shadow">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Recent Signups</h3>
            </div>
            <div className="divide-y divide-gray-200">
              {recentUsers.length === 0 ? (
                <div className="px-6 py-8 text-center text-gray-500">
                  No users yet
                </div>
              ) : (
                recentUsers.map((user) => (
                  <div key={user.id} className="px-6 py-4 hover:bg-gray-50">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-medium text-gray-900">{user.full_name}</p>
                        <p className="text-sm text-gray-600">{user.email}</p>
                      </div>
                      <div className="text-right">
                        <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                          user.plan === 'premium' 
                            ? 'bg-primary-100 text-primary-800' 
                            : 'bg-gray-100 text-gray-800'
                        }`}>
                          {user.plan}
                        </span>
                        <p className="text-xs text-gray-500 mt-1">
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
          <div className="bg-white rounded-lg shadow">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Activity Summary</h3>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex items-center justify-between">
                <span className="text-gray-600">Signups (24h)</span>
                <span className="text-2xl font-bold text-gray-900">{stats.signups_last_24h}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-600">Signups (7d)</span>
                <span className="text-2xl font-bold text-gray-900">{stats.signups_last_7d}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-600">Signups (30d)</span>
                <span className="text-2xl font-bold text-gray-900">{stats.signups_last_30d}</span>
              </div>
              <div className="pt-4 border-t border-gray-200">
                <div className="flex items-center justify-between">
                  <span className="text-gray-600">Monthly Active Users</span>
                  <span className="text-2xl font-bold text-primary-600">{stats.mau}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}
