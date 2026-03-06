import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import AdminCommissionTable from '@/components/admin-commission-table'
import Pagination from '@/components/Pagination'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { ClockIcon, CheckBadgeIcon, BanknotesIcon } from '@heroicons/react/24/outline'

async function getCommissions(page: number = 1) {
  try {
    const result = await serverApiClient<{ data: any[]; pagination: any }>(`/api/v1/admin/commissions?page=${page}&limit=20`)
    return { commissions: result.data || [], pagination: result.pagination }
  } catch {
    return { commissions: [], pagination: null }
  }
}

async function getCommissionStats() {
  try {
    const { data: stats } = await serverApiClient<{ data: any }>('/api/v1/admin/commissions/stats')
    return stats || { total_pending_amount: 0, total_approved_amount: 0, total_paid_amount: 0 }
  } catch {
    return { total_pending_amount: 0, total_approved_amount: 0, total_paid_amount: 0 }
  }
}

export default async function CommissionsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>
}) {
  await requireAdmin()
  const params = await searchParams
  const page = Math.max(1, parseInt(params.page || '1', 10))

  const [{ commissions, pagination }, stats] = await Promise.all([
    getCommissions(page),
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
        {pagination && (
          <Pagination
            page={pagination.page}
            totalPages={pagination.total_pages}
            total={pagination.total}
          />
        )}
      </div>
    </>
  )
}
