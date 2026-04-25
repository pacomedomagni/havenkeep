import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import PartnerTable from '@/components/partner-table'
import Pagination from '@/components/Pagination'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { UsersIcon, ClockIcon, CheckCircleIcon } from '@heroicons/react/24/outline'

async function getPartners(page: number = 1) {
  try {
    const result = await serverApiClient<{ data: any[]; pagination: any }>(`/api/v1/admin/partners?page=${page}&limit=20`)
    return { partners: result.data || [], pagination: result.pagination }
  } catch {
    return { partners: [], pagination: null }
  }
}

export default async function PartnersPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>
}) {
  await requireAdmin()
  const params = await searchParams
  const page = Math.max(1, parseInt(params.page || '1', 10))

  const { partners, pagination } = await getPartners(page)

  const totalPartners = partners.length
  const statusOf = (p: any): 'pending' | 'active' | 'rejected' => {
    if (p.status === 'pending' || p.status === 'active' || p.status === 'rejected') return p.status
    return p.is_active ? 'active' : 'pending'
  }
  const pendingPartners = partners.filter((p: any) => statusOf(p) === 'pending').length
  const activePartners = partners.filter((p: any) => statusOf(p) === 'active').length
  const rejectedPartners = partners.filter((p: any) => statusOf(p) === 'rejected').length

  return (
    <>
      <Header
        title="Partner Management"
        subtitle="Manage platform partners"
      />

      <div className="p-8">
        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <StatsCard
            title="Total Partners"
            value={totalPartners.toLocaleString()}
            icon={<UsersIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Pending Approval"
            value={pendingPartners.toLocaleString()}
            change={pendingPartners > 0 ? {
              value: `${pendingPartners} awaiting review`,
              positive: false,
            } : undefined}
            icon={<ClockIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Active Partners"
            value={activePartners.toLocaleString()}
            change={{
              value: `${totalPartners > 0 ? ((activePartners / totalPartners) * 100).toFixed(1) : '0.0'}% of total`,
              positive: activePartners > 0,
            }}
            icon={<CheckCircleIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>
        {rejectedPartners > 0 && (
          <p className="mb-4 text-sm text-haven-text-tertiary">
            {rejectedPartners} rejected partner{rejectedPartners === 1 ? '' : 's'} on this page.
          </p>
        )}

        <PartnerTable partners={partners} />
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
