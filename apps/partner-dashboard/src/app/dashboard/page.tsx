'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import {
  GiftIcon,
  CheckCircleIcon,
  ClockIcon,
  CurrencyDollarIcon,
} from '@heroicons/react/24/outline';
import { apiClient } from '@/lib/api';

interface Analytics {
  total_gifts: number;
  activated_gifts: number;
  pending_gifts: number;
  activation_rate: number;
  total_commissions: number;
  pending_commissions: number;
  paid_commissions: number;
  recent_activity: any[];
}

export default function DashboardPage() {
  const [analytics, setAnalytics] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchAnalytics();
  }, []);

  const fetchAnalytics = async () => {
    try {
      setError(null);
      const data = await apiClient<Analytics>('/api/v1/partners/analytics');
      if (data.success && data.data) {
        setAnalytics(data.data);
      }
    } catch (err) {
      setError('Failed to load dashboard data.');
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
        <h1 className="text-2xl font-bold text-white">Partner Dashboard</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Welcome back. Here&apos;s an overview of your partner activity.
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

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Total Gifts</span>
            <GiftIcon className="w-6 h-6 text-haven-primary" />
          </div>
          <div className="text-2xl font-bold text-white">{analytics?.total_gifts || 0}</div>
          <Link href="/dashboard/gifts" className="text-sm text-haven-primary hover:text-haven-primary/80 mt-2 inline-block">
            View all
          </Link>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Activated Gifts</span>
            <CheckCircleIcon className="w-6 h-6 text-haven-active" />
          </div>
          <div className="text-2xl font-bold text-white">{analytics?.activated_gifts || 0}</div>
          <div className="text-sm text-haven-active mt-2">
            {analytics?.activation_rate || 0}% activation rate
          </div>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Pending Commissions</span>
            <ClockIcon className="w-6 h-6 text-haven-warning" />
          </div>
          <div className="text-2xl font-bold text-haven-warning">
            {formatCurrency(analytics?.pending_commissions || 0)}
          </div>
          <Link href="/dashboard/commissions" className="text-sm text-haven-primary hover:text-haven-primary/80 mt-2 inline-block">
            View details
          </Link>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Total Earned</span>
            <CurrencyDollarIcon className="w-6 h-6 text-haven-active" />
          </div>
          <div className="text-2xl font-bold text-haven-active">
            {formatCurrency(analytics?.total_commissions || 0)}
          </div>
          <div className="text-sm text-haven-text-tertiary mt-2">
            {formatCurrency(analytics?.paid_commissions || 0)} paid
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-4">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Link
            href="/dashboard/gifts"
            className="flex items-center gap-3 p-4 border border-haven-border rounded-lg hover:border-haven-primary hover:bg-haven-elevated transition-colors"
          >
            <GiftIcon className="w-6 h-6 text-haven-primary" />
            <div>
              <div className="font-medium text-white">Create New Gift</div>
              <div className="text-sm text-haven-text-tertiary">Send gift to a homebuyer</div>
            </div>
          </Link>

          <Link
            href="/dashboard/analytics"
            className="flex items-center gap-3 p-4 border border-haven-border rounded-lg hover:border-haven-primary hover:bg-haven-elevated transition-colors"
          >
            <CheckCircleIcon className="w-6 h-6 text-haven-active" />
            <div>
              <div className="font-medium text-white">View Analytics</div>
              <div className="text-sm text-haven-text-tertiary">Track your performance</div>
            </div>
          </Link>

          <Link
            href="/dashboard/settings"
            className="flex items-center gap-3 p-4 border border-haven-border rounded-lg hover:border-haven-primary hover:bg-haven-elevated transition-colors"
          >
            <CurrencyDollarIcon className="w-6 h-6 text-haven-primary" />
            <div>
              <div className="font-medium text-white">Update Settings</div>
              <div className="text-sm text-haven-text-tertiary">Customize your profile</div>
            </div>
          </Link>
        </div>
      </div>

      {/* Recent Activity */}
      {analytics?.recent_activity && analytics.recent_activity.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Recent Activity</h2>
          <div className="space-y-4">
            {analytics.recent_activity.slice(0, 5).map((activity: any, index: number) => (
              <div key={index} className="flex items-start gap-3 pb-4 border-b border-haven-border last:border-0 last:pb-0">
                <div className="flex-shrink-0 w-2 h-2 bg-haven-primary rounded-full mt-2"></div>
                <div className="flex-1">
                  <div className="text-sm text-white">{activity.homebuyer_name}</div>
                  <div className="text-xs text-haven-text-tertiary">
                    {activity.is_activated ? 'Activated gift' : 'Gift created'} •{' '}
                    {new Date(activity.created_at).toLocaleDateString()}
                  </div>
                </div>
                <div className="text-sm font-medium text-white">
                  {formatCurrency(activity.amount_charged)}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
