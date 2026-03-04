import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import AuditLogTable from '@/components/audit-log-table'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { ShieldCheckIcon, ExclamationTriangleIcon, InformationCircleIcon } from '@heroicons/react/24/outline'

async function getAuditLogs() {
  try {
    const { logs } = await serverApiClient<{ logs: any[] }>('/api/v1/audit/logs?limit=50')
    return logs || []
  } catch {
    return []
  }
}

async function getAuditStats() {
  try {
    const { stats } = await serverApiClient<{ stats: any }>('/api/v1/audit/stats')
    return stats || { total: 0, by_severity: { info: 0, warning: 0, error: 0, critical: 0 }, failed_actions: 0 }
  } catch {
    return { total: 0, by_severity: { info: 0, warning: 0, error: 0, critical: 0 }, failed_actions: 0 }
  }
}

export default async function AuditPage() {
  await requireAdmin()

  const [logs, stats] = await Promise.all([
    getAuditLogs(),
    getAuditStats(),
  ])

  return (
    <>
      <Header
        title="Audit Logs"
        subtitle="System activity and security events"
      />

      <div className="p-8">
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
      </div>
    </>
  )
}
