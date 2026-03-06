import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import AdminCommissionTable from '@/components/admin-commission-table'
import Pagination from '@/components/Pagination'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { ClockIcon, CheckBadgeIcon, BanknotesIcon } from '@heroicons/react/24/outline'

async function getCommissions(page: number = 1) {
  try {
    const result = await serverApiClient<{ data: any[]; pagination: any }>(`/api/v1/admin/commissions?page=${page}&limit=20`)
    return { data: { commissions: result.data || [], pagination: result.pagination }, error: false }
  } catch {
    return { data: { commissions: [], pagination: null }, error: true }
  }
}

async function getCommissionStats() {
  try {
    const { data: stats } = await serverApiClient<{ data: any }>('/api/v1/admin/commissions/stats')
    return { data: stats || { total_pending_amount: 0, total_approved_amount: 0, total_paid_amount: 0 }, error: false }
  } catch {
    return { data: { total_pending_amount: 0, total_approved_amount: 0, total_paid_amount: 0 }, error: true }
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

  const [commissionsResult, statsResult] = await Promise.all([
    getCommissions(page),
    getCommissionStats(),
  ])

  const { commissions, pagination } = commissionsResult.data
  const stats = statsResult.data
  const fetchError = commissionsResult.error || statsResult.error

  return (
    <>
      <Header
        title="Commission Management"
        subtitle="Manage partner commissions"
      />

      <div className="p-8">
        {fetchError && (
          <div className="mb-6 rounded-lg border border-red-500/30 bg-red-500/10 p-4">
            <p className="text-sm text-red-400">
              Failed to load data from the API. The values shown below may be inaccurate.
            </p>
          </div>
        )}

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
