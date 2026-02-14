'use client';

import { useState, useEffect } from 'react';
import ConversionFunnel from '@/components/charts/conversion-funnel';
import { apiClient } from '@/lib/api';

interface AnalyticsData {
  total_gifts: number;
  activated_gifts: number;
  pending_gifts: number;
  activation_rate: number;
  total_commissions: number;
  pending_commissions: number;
  paid_commissions: number;
  recent_activity: any[];
}

export default function AnalyticsPage() {
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
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

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(amount);
  };

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
          <ConversionFunnel data={analytics ? [
            { stage: 'Total Gifts', count: analytics.total_gifts, color: '#6C63FF' },
            { stage: 'Pending', count: analytics.pending_gifts, color: '#BB86FC' },
            { stage: 'Activated', count: analytics.activated_gifts, color: '#4CAF50' },
          ] : undefined} />
        </div>

        {/* Commissions Breakdown */}
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Commissions Breakdown</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Your commission earnings summary
          </p>
          <div className="space-y-4">
            <div className="flex items-center justify-between p-4 border border-haven-border rounded-lg">
              <span className="text-haven-text-secondary">Total Earned</span>
              <span className="text-lg font-bold text-white">
                {formatCurrency(analytics?.total_commissions || 0)}
              </span>
            </div>
            <div className="flex items-center justify-between p-4 border border-haven-border rounded-lg">
              <span className="text-haven-text-secondary">Paid Out</span>
              <span className="text-lg font-bold text-haven-active">
                {formatCurrency(analytics?.paid_commissions || 0)}
              </span>
            </div>
            <div className="flex items-center justify-between p-4 border border-haven-border rounded-lg">
              <span className="text-haven-text-secondary">Pending</span>
              <span className="text-lg font-bold text-haven-warning">
                {formatCurrency(analytics?.pending_commissions || 0)}
              </span>
            </div>
          </div>
        </div>

        {/* Activation Rate */}
        <div className="card lg:col-span-2">
          <h2 className="text-lg font-semibold text-white mb-4">Performance Summary</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Key metrics for your partner activity
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="text-center p-4 border border-haven-border rounded-lg">
              <div className="text-3xl font-bold text-haven-primary">{analytics?.total_gifts || 0}</div>
              <div className="text-sm text-haven-text-secondary mt-1">Total Gifts Sent</div>
            </div>
            <div className="text-center p-4 border border-haven-border rounded-lg">
              <div className="text-3xl font-bold text-haven-active">{analytics?.activated_gifts || 0}</div>
              <div className="text-sm text-haven-text-secondary mt-1">Gifts Activated</div>
            </div>
            <div className="text-center p-4 border border-haven-border rounded-lg">
              <div className="text-3xl font-bold text-haven-warning">{analytics?.activation_rate || 0}%</div>
              <div className="text-sm text-haven-text-secondary mt-1">Activation Rate</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
