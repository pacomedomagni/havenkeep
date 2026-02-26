'use client';

import { useState, useEffect, useCallback } from 'react';
import ConversionFunnel from '@/components/charts/conversion-funnel';
import EarningsChart from '@/components/charts/earnings-chart';
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

interface EarningsHistoryEntry {
  month: string;
  earnings: number;
}

export default function AnalyticsPage() {
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [earningsHistory, setEarningsHistory] = useState<EarningsHistoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  const fetchAnalytics = useCallback(async () => {
    try {
      setError(null);
      setLoading(true);

      // Build query string for date range
      const params = new URLSearchParams();
      if (startDate) params.set('startDate', startDate);
      if (endDate) params.set('endDate', endDate);
      const qs = params.toString();
      const analyticsUrl = `/api/v1/partners/analytics${qs ? `?${qs}` : ''}`;

      const [analyticsRes, earningsRes] = await Promise.all([
        apiClient<AnalyticsData>(analyticsUrl),
        apiClient<EarningsHistoryEntry[]>('/api/v1/partners/earnings-history'),
      ]);

      if (analyticsRes.success && analyticsRes.data) {
        setAnalytics(analyticsRes.data);
      }
      if (earningsRes.success && earningsRes.data) {
        setEarningsHistory(earningsRes.data);
      }
    } catch (err) {
      setError('Failed to load analytics data.');
      console.error('Error fetching analytics:', err);
    } finally {
      setLoading(false);
    }
  }, [startDate, endDate]);

  useEffect(() => {
    fetchAnalytics();
  }, [fetchAnalytics]);

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
      <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white">Analytics</h1>
          <p className="text-haven-text-secondary text-sm mt-1">
            Deep dive into your referral performance and earnings
          </p>
        </div>

        {/* Date Range Filters */}
        <div className="flex items-center gap-3">
          <div>
            <label htmlFor="startDate" className="block text-xs text-haven-text-secondary mb-1">
              Start date
            </label>
            <input
              id="startDate"
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="input-field text-sm"
            />
          </div>
          <div>
            <label htmlFor="endDate" className="block text-xs text-haven-text-secondary mb-1">
              End date
            </label>
            <input
              id="endDate"
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="input-field text-sm"
            />
          </div>
          {(startDate || endDate) && (
            <button
              onClick={() => {
                setStartDate('');
                setEndDate('');
              }}
              className="text-xs text-haven-text-secondary hover:text-white mt-4"
            >
              Clear
            </button>
          )}
        </div>
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

        {/* Earnings Chart */}
        <div className="card lg:col-span-2">
          <h2 className="text-lg font-semibold text-white mb-4">Earnings Over Time</h2>
          <p className="text-sm text-haven-text-secondary mb-4">
            Monthly earnings for the last 12 months
          </p>
          <EarningsChart data={earningsHistory} />
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
