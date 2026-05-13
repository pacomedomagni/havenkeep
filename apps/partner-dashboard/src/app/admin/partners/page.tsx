import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import PartnerTable from '@/components/partner-table'
import Pagination from '@/components/Pagination'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import type { AdminPartnerListItem, PaginationMeta } from '@/lib/api-types'
import { UsersIcon, GiftIcon } from '@heroicons/react/24/outline'

async function getPartners(page: number = 1) {
  try {
    const result = await serverApiClient<{ data: AdminPartnerListItem[]; meta?: { pagination?: PaginationMeta } }>(`/api/v1/admin/partners?page=${page}&limit=20`)
    return { partners: result.data || [], pagination: result.meta?.pagination ?? null }
  } catch (err) {
    // Surface the upstream failure instead of silently rendering "0
    // partners" — the previous shape masked a 500 from the admin route
    // and made the dashboard look like the DB was empty.
    console.error('[admin/partners] failed to fetch /api/v1/admin/partners', err);
    return { partners: [] as AdminPartnerListItem[], pagination: null }
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

  // `partners.length` is the count for the current page (limit=20),
  // not the global total. The API's pagination meta carries the real
  // number — fall back to the page-local count only when meta is
  // missing (e.g. upstream errored).
  const totalPartners = pagination?.total ?? partners.length
  const totalGifts = partners.reduce((sum, p) => sum + (p.count_gifts ?? 0), 0)

  return (
    <>
      <Header
        title="Partners"
        subtitle="Everyone who's signed up to gift HavenKeep"
      />

      <div className="p-8">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <StatsCard
            title="Total Partners"
            value={totalPartners.toLocaleString()}
            icon={<UsersIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Gifts Sent (this page)"
            value={totalGifts.toLocaleString()}
            icon={<GiftIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>

        <PartnerTable partners={partners} />
        {pagination && pagination.total_pages != null && pagination.total != null && (
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
