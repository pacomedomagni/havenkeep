import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import PartnerActions from '@/components/partner-actions'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import { GiftIcon, UserGroupIcon, CurrencyDollarIcon } from '@heroicons/react/24/outline'

async function getPartner(id: string) {
  try {
    const { partner } = await serverApiClient<{ partner: any }>(`/api/v1/admin/partners/${id}`)
    return partner
  } catch {
    return null
  }
}

export default async function PartnerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  await requireAdmin()

  const { id } = await params
  const partner = await getPartner(id)

  if (!partner) {
    return (
      <>
        <Header title="Partner Not Found" subtitle="The requested partner could not be found" />
        <div className="p-8">
          <div className="card text-center py-12">
            <p className="text-haven-text-secondary">This partner does not exist or has been removed.</p>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <Header
        title={partner.company_name || 'Partner Details'}
        subtitle={`Partner ID: ${partner.id}`}
      />

      <div className="p-8">
        {/* Partner Info Card */}
        <div className="card mb-8">
          <h3 className="text-lg font-semibold text-white mb-4">Partner Information</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Company Name
              </label>
              <p className="text-white">{partner.company_name || '-'}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Partner Type
              </label>
              <p className="text-white">{partner.partner_type || '-'}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Email
              </label>
              <p className="text-white">{partner.email || '-'}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Phone
              </label>
              <p className="text-white">{partner.phone || '-'}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                License Number
              </label>
              <p className="text-white font-mono text-sm">{partner.license_number || '-'}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Service Areas
              </label>
              <p className="text-white">
                {Array.isArray(partner.service_areas)
                  ? partner.service_areas.join(', ')
                  : partner.service_areas || '-'}
              </p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Referral Code
              </label>
              <p className="text-white font-mono text-sm">{partner.referral_code || '-'}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                Registered
              </label>
              <p className="text-white">
                {partner.created_at
                  ? new Date(partner.created_at).toLocaleDateString('en-US', {
                      year: 'numeric',
                      month: 'long',
                      day: 'numeric',
                    })
                  : '-'}
              </p>
            </div>
          </div>
        </div>

        {/* Status & Stripe */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Status</h3>
            <div className="flex items-center gap-3">
              <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-semibold ${
                partner.is_active
                  ? 'bg-green-500/20 text-green-400'
                  : 'bg-yellow-500/20 text-yellow-400'
              }`}>
                {partner.is_active ? 'active' : 'pending'}
              </span>
            </div>
            {!partner.is_active && (
              <div className="mt-4">
                <PartnerActions partnerId={partner.id} />
              </div>
            )}
          </div>

          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Stripe Integration</h3>
            <div className="flex items-center gap-3">
              {partner.stripe_account_id ? (
                <>
                  <span className="inline-flex h-3 w-3 rounded-full bg-green-400" />
                  <span className="text-white">Connected</span>
                  <span className="text-haven-text-tertiary text-sm font-mono ml-2">
                    {partner.stripe_account_id}
                  </span>
                </>
              ) : (
                <>
                  <span className="inline-flex h-3 w-3 rounded-full bg-haven-text-tertiary" />
                  <span className="text-haven-text-secondary">Not connected</span>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <StatsCard
            title="Total Gifts"
            value={Number(partner.gift_count || 0).toLocaleString()}
            icon={<GiftIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Total Referrals"
            value={Number(partner.referral_count || 0).toLocaleString()}
            icon={<UserGroupIcon className="h-6 w-6 text-haven-primary" />}
          />

          <StatsCard
            title="Total Commissions"
            value={`$${Number(partner.total_paid_amount || 0).toLocaleString()}`}
            icon={<CurrencyDollarIcon className="h-6 w-6 text-haven-primary" />}
          />
        </div>
      </div>
    </>
  )
}
