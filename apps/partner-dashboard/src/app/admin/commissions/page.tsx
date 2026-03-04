import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import AdminCommissionTable from '@/components/admin-commission-table'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { ClockIcon, CheckBadgeIcon, BanknotesIcon } from '@heroicons/react/24/outline'

async function getCommissions() {
  try {
    const { commissions } = await serverApiClient<{ commissions: any[] }>('/api/v1/admin/commissions?limit=100')
    return commissions || []
  } catch {
    return []
  }
}

async function getCommissionStats() {
  try {
    const stats = await serverApiClient<any>('/api/v1/admin/commissions/stats')
    return stats || { total_pending_amount: 0, total_approved_amount: 0, total_paid_amount: 0 }
  } catch {
    return { total_pending_amount: 0, total_approved_amount: 0, total_paid_amount: 0 }
  }
}

export default async function CommissionsPage() {
  await requireAdmin()

  const [commissions, stats] = await Promise.all([
    getCommissions(),
    getCommissionStats(),
  ])

  return (
    <>
      <Header
        title="Commission Management"
        subtitle="Manage partner commissions"
      />

      <div className="p-8">
        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <StatsCard
            title="Pending Amount"
            value={`$${Number(stats.total_pending_amount || 0).toLocaleString()}`}
            icon={<ClockIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Approved Amount"
            value={`$${Number(stats.total_approved_amount || 0).toLocaleString()}`}
            icon={<CheckBadgeIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Paid Amount"
            value={`$${Number(stats.total_paid_amount || 0).toLocaleString()}`}
            icon={<BanknotesIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>

        <AdminCommissionTable commissions={commissions} />
      </div>
    </>
  )
}
