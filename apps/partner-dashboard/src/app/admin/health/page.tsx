import Header from '@/components/Header'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { ServerIcon, CircleStackIcon, CpuChipIcon } from '@heroicons/react/24/outline'

interface ServiceHealth {
  status: string
  message?: string
}

interface HealthData {
  status: string
  uptime?: number
  environment?: string
  services?: {
    database?: ServiceHealth
    redis?: ServiceHealth
    minio?: ServiceHealth
  }
}

async function getHealthData(): Promise<HealthData | null> {
  try {
    const data = await serverApiClient<HealthData>('/health/detailed')
    return data
  } catch {
    return null
  }
}

function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)

  const parts: string[] = []
  if (days > 0) parts.push(`${days}d`)
  if (hours > 0) parts.push(`${hours}h`)
  if (minutes > 0) parts.push(`${minutes}m`)

  return parts.length > 0 ? parts.join(' ') : '< 1m'
}

function getOverallStatusColor(status: string): string {
  switch (status) {
    case 'healthy':
    case 'ok':
      return 'bg-green-500/20 border-green-500/30 text-green-400'
    case 'degraded':
      return 'bg-yellow-500/20 border-yellow-500/30 text-yellow-400'
    case 'unhealthy':
    case 'error':
      return 'bg-red-500/20 border-red-500/30 text-red-400'
    default:
      return 'bg-haven-elevated border-haven-border text-haven-text-secondary'
  }
}

function getServiceStatusDot(status: string): string {
  switch (status) {
    case 'healthy':
    case 'ok':
    case 'connected':
      return 'bg-green-400'
    case 'degraded':
      return 'bg-yellow-400'
    case 'unhealthy':
    case 'error':
    case 'disconnected':
      return 'bg-red-400'
    default:
      return 'bg-haven-text-tertiary'
  }
}

export default async function HealthPage() {
  await requireAdmin()

  const health = await getHealthData()

  if (!health) {
    return (
      <>
        <Header
          title="System Health"
          subtitle="Infrastructure status"
        />

        <div className="p-8">
          <div className="rounded-lg border bg-red-500/20 border-red-500/30 p-6 mb-8">
            <div className="flex items-center gap-3">
              <span className="inline-flex h-3 w-3 rounded-full bg-red-400 animate-pulse" />
              <h2 className="text-lg font-semibold text-red-400">Health Endpoint Unreachable</h2>
            </div>
            <p className="text-red-300/70 mt-2">
              Unable to connect to the health monitoring endpoint. The API server may be down or the endpoint may not be configured.
            </p>
          </div>
        </div>
      </>
    )
  }

  const services = [
    {
      name: 'Database',
      key: 'database',
      icon: <CircleStackIcon className="h-8 w-8" />,
      data: health.services?.database,
    },
    {
      name: 'Redis',
      key: 'redis',
      icon: <CpuChipIcon className="h-8 w-8" />,
      data: health.services?.redis,
    },
    {
      name: 'MinIO (File Storage)',
      key: 'minio',
      icon: <ServerIcon className="h-8 w-8" />,
      data: health.services?.minio,
    },
  ]

  return (
    <>
      <Header
        title="System Health"
        subtitle="Infrastructure status"
      />

      <div className="p-8">
        {/* Overall Status Banner */}
        <div className={`rounded-lg border p-6 mb-8 ${getOverallStatusColor(health.status)}`}>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <span className={`inline-flex h-3 w-3 rounded-full ${
                health.status === 'healthy' || health.status === 'ok'
                  ? 'bg-green-400'
                  : health.status === 'degraded'
                  ? 'bg-yellow-400 animate-pulse'
                  : 'bg-red-400 animate-pulse'
              }`} />
              <h2 className="text-lg font-semibold">
                {health.status === 'healthy' || health.status === 'ok'
                  ? 'All Systems Operational'
                  : health.status === 'degraded'
                  ? 'System Degraded'
                  : 'System Error'}
              </h2>
            </div>
            <div className="flex items-center gap-4">
              {health.uptime !== undefined && (
                <div className="text-right">
                  <p className="text-xs opacity-70">Uptime</p>
                  <p className="text-sm font-semibold">{formatUptime(health.uptime)}</p>
                </div>
              )}
              {health.environment && (
                <span className="px-3 py-1 text-xs font-medium rounded-full bg-white/10">
                  {health.environment}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Service Cards Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {services.map((service) => {
            const serviceData = service.data
            const status = serviceData?.status || 'unknown'

            return (
              <div key={service.key} className="card">
                <div className="flex items-start justify-between mb-4">
                  <div className="text-haven-primary">
                    {service.icon}
                  </div>
                  <span className={`inline-flex h-3 w-3 rounded-full ${getServiceStatusDot(status)}`} />
                </div>

                <h3 className="text-lg font-semibold text-white mb-1">{service.name}</h3>

                <div className="flex items-center gap-2 mb-3">
                  <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                    status === 'healthy' || status === 'ok' || status === 'connected'
                      ? 'bg-green-500/20 text-green-400'
                      : status === 'degraded'
                      ? 'bg-yellow-500/20 text-yellow-400'
                      : status === 'unhealthy' || status === 'error' || status === 'disconnected'
                      ? 'bg-red-500/20 text-red-400'
                      : 'bg-haven-elevated text-haven-text-secondary'
                  }`}>
                    {status}
                  </span>
                </div>

                {serviceData?.message && (
                  <p className="text-sm text-haven-text-secondary">
                    {serviceData.message}
                  </p>
                )}

                {!serviceData && (
                  <p className="text-sm text-haven-text-tertiary">
                    No data available
                  </p>
                )}
              </div>
            )
          })}
        </div>
      </div>
    </>
  )
}
