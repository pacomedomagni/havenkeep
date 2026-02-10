import ConversionFunnel from '@/components/charts/conversion-funnel';
import EarningsChart from '@/components/charts/earnings-chart';
import TopReferrals from '@/components/charts/top-referrals';

export default function AnalyticsPage() {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Analytics</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Deep dive into your referral performance and earnings
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Conversion Funnel */}
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Conversion Funnel</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Track how referrals convert through each stage
          </p>
          <ConversionFunnel />
        </div>

        {/* Monthly Earnings */}
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Monthly Earnings</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Your commission earnings over the past 12 months
          </p>
          <EarningsChart />
        </div>

        {/* Top Referral Codes */}
        <div className="card lg:col-span-2">
          <h2 className="text-lg font-semibold text-white mb-4">Top Performing Referral Codes</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Your most successful referral codes by number of conversions
          </p>
          <TopReferrals />
        </div>
      </div>
    </div>
  );
}
