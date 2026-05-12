import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import AuditLogTable from '@/components/audit-log-table'
import Pagination from '@/components/Pagination'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import type { AuditLogEntry, AdminAuditStats, PaginationMeta } from '@/lib/api-types'
import { ShieldCheckIcon, ExclamationTriangleIcon, InformationCircleIcon } from '@heroicons/react/24/outline'

interface AuditPageStats {
  total: number;
  by_severity: { info: number; warning: number; error: number; critical: number };
  failed_actions: number;
}

async function getAuditLogs(page: number = 1) {
  try {
    const result = await serverApiClient<{ data: AuditLogEntry[]; meta?: { pagination?: PaginationMeta } }>(`/api/v1/audit/logs?page=${page}&limit=50`)
    return { data: { logs: result.data || [], pagination: result.meta?.pagination ?? null }, error: false }
  } catch {
    return { data: { logs: [] as AuditLogEntry[], pagination: null }, error: true }
  }
}

async function getAuditStats() {
  try {
    const { data: stats } = await serverApiClient<{ data: AdminAuditStats & AuditPageStats }>('/api/v1/audit/stats')
    return { data: stats || { total: 0, by_severity: { info: 0, warning: 0, error: 0, critical: 0 }, failed_actions: 0 }, error: false }
  } catch {
    return { data: { total: 0, by_severity: { info: 0, warning: 0, error: 0, critical: 0 }, failed_actions: 0 } as AuditPageStats, error: true }
  }
}

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>
}) {
  await requireAdmin()
  const params = await searchParams
  const page = Math.max(1, parseInt(params.page || '1', 10))

  const [logsResult, statsResult] = await Promise.all([
    getAuditLogs(page),
    getAuditStats(),
  ])

  const { logs, pagination } = logsResult.data
  const stats = statsResult.data
  const fetchError = logsResult.error || statsResult.error

  return (
    <>
      <Header
        title="Audit Logs"
        subtitle="System activity and security events"
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
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <StatsCard
            title="Total Events"
            value={Number(stats.total || 0).toLocaleString()}
            icon={<InformationCircleIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Warnings"
            value={Number(stats.by_severity?.warning || 0).toLocaleString()}
            change={Number(stats.by_severity?.warning) > 0 ? {
              value: 'requires attention',
              positive: false,
            } : undefined}
            icon={<ExclamationTriangleIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Errors"
            value={Number(stats.by_severity?.error || 0).toLocaleString()}
            change={Number(stats.by_severity?.error) > 0 ? {
              value: 'needs investigation',
              positive: false,
            } : undefined}
            icon={<ExclamationTriangleIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Critical Events"
            value={Number(stats.by_severity?.critical || 0).toLocaleString()}
            change={Number(stats.by_severity?.critical) > 0 ? {
              value: 'immediate action needed',
              positive: false,
            } : undefined}
            icon={<ShieldCheckIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>

        <AuditLogTable initialLogs={logs} />
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
