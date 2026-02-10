import KpiCard from '@/components/kpi-card';
import ReferralChart from '@/components/charts/referral-chart';
import {
  UserGroupIcon,
  UserIcon,
  ClockIcon,
  CurrencyDollarIcon,
} from '@heroicons/react/24/outline';

export default function DashboardPage() {
  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Dashboard</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Welcome back. Here&apos;s an overview of your partner activity.
        </p>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <KpiCard
          icon={UserGroupIcon}
          value="127"
          label="Total Referrals"
          trend={{ value: 12.5, isPositive: true }}
        />
        <KpiCard
          icon={UserIcon}
          value="84"
          label="Active Users"
          trend={{ value: 8.2, isPositive: true }}
        />
        <KpiCard
          icon={ClockIcon}
          value="$1,240"
          label="Pending Commissions"
          trend={{ value: 3.1, isPositive: true }}
        />
        <KpiCard
          icon={CurrencyDollarIcon}
          value="$8,430"
          label="Total Earned"
          trend={{ value: 15.3, isPositive: true }}
        />
      </div>

      {/* Referral Trend Chart */}
      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-4">Referral Trends</h2>
        <ReferralChart />
      </div>
    </div>
  );
}
