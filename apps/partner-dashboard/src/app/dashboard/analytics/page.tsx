'use client';

import { useState, useEffect } from 'react';
import ConversionFunnel from '@/components/charts/conversion-funnel';
import EarningsChart from '@/components/charts/earnings-chart';
import TopReferrals from '@/components/charts/top-referrals';
import { apiClient } from '@/lib/api';

interface AnalyticsData {
  earnings_by_month?: { month: string; earnings: number }[];
  funnel?: { sent: number; opened: number; activated: number; converted: number };
  top_referrals?: { code: string; conversions: number; earnings: number }[];
}

export default function AnalyticsPage() {
  const [analytics, setAnalytics] = useState<AnalyticsData>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchAnalytics();
  }, []);

  const fetchAnalytics = async () => {
    try {
      setError(null);
      const data = await apiClient<AnalyticsData>('/api/v1/partners/analytics');
      if (data.success && data.data) {
        setAnalytics(data.data);
      }
    } catch (err) {
      setError('Failed to load analytics data.');
      console.error('Error fetching analytics:', err);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-haven-primary"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Analytics</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Deep dive into your referral performance and earnings
        </p>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg p-4 text-haven-error text-sm">
          {error}
          <button onClick={fetchAnalytics} className="ml-2 underline">
            Retry
          </button>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Conversion Funnel */}
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Conversion Funnel</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Track how referrals convert through each stage
          </p>
          <ConversionFunnel data={analytics.funnel ? [
            { stage: 'Gifts Sent', count: analytics.funnel.sent, color: '#6C63FF' },
            { stage: 'Opened', count: analytics.funnel.opened, color: '#BB86FC' },
            { stage: 'Activated', count: analytics.funnel.activated, color: '#4CAF50' },
            { stage: 'Converted', count: analytics.funnel.converted, color: '#FFC107' },
          ] : undefined} />
        </div>

        {/* Monthly Earnings */}
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Monthly Earnings</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Your commission earnings over the past 12 months
          </p>
          <EarningsChart data={analytics.earnings_by_month} />
        </div>

        {/* Top Referral Codes */}
        <div className="card lg:col-span-2">
          <h2 className="text-lg font-semibold text-white mb-4">Top Performing Referral Codes</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Your most successful referral codes by number of conversions
          </p>
          <TopReferrals data={analytics.top_referrals} />
        </div>
      </div>
    </div>
  );
}
