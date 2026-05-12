import Header from '@/components/Header'
import StatsCard from '@/components/StatsCard'
import { serverApiClient, requireAdmin } from '@/lib/auth'
import type { AdminPartnerDetail } from '@/lib/api-types'
import { GiftIcon, UserGroupIcon } from '@heroicons/react/24/outline'

async function getPartner(id: string) {
  try {
    const { data: partner } = await serverApiClient<{ data: AdminPartnerDetail }>(`/api/v1/admin/partners/${id}`)
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

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
        </div>
      </div>
    </>
  )
}
