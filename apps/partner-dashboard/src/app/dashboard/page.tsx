'use client';

import { useState, useEffect, useRef } from 'react';
import Link from 'next/link';
import {
  GiftIcon,
  CheckCircleIcon,
  ClockIcon,
  CurrencyDollarIcon,
} from '@heroicons/react/24/outline';
import { apiClient, ApiError } from '@/lib/api';
import { formatCurrency } from '@/lib/utils';

/**
 * Money fields are DECIMAL on the wire — we keep them as strings/numbers
 * without parseFloat so cents do not drift on large totals (audit Ch10-W036).
 * `formatCurrency` already accepts string input.
 */
interface Analytics {
  total_gifts: number;
  activated_gifts: number;
  pending_gifts: number;
  activation_rate: number;
  total_commissions: number | string;
  pending_commissions: number | string;
  paid_commissions: number | string;
  recent_activity: RecentActivity[];
}

interface RecentActivity {
  name?: string | null;
  status?: string | null;
  created_at?: string | null;
}

function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString();
}

export default function DashboardPage() {
  const [analytics, setAnalytics] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // Track the in-flight controller so unmount aborts pending requests
  // (audit Ch10-W025).
  const inflight = useRef<AbortController | null>(null);

  useEffect(() => {
    fetchAnalytics();
    return () => {
      inflight.current?.abort();
      inflight.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function fetchAnalytics() {
    inflight.current?.abort();
    const controller = new AbortController();
    inflight.current = controller;
    setError(null);
    try {
      const data = await apiClient<Analytics>('/api/v1/partners/analytics');
      if (controller.signal.aborted) return;
      if (data.success && data.data) {
        setAnalytics(data.data);
      }
    } catch (err) {
      if (controller.signal.aborted) return;
      const message =
        err instanceof ApiError ? err.message : 'Failed to load dashboard data.';
      setError(message);
    } finally {
      if (!controller.signal.aborted) setLoading(false);
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64" aria-busy="true">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-haven-primary" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Partner Dashboard</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Welcome back. Here&apos;s an overview of your partner activity.
        </p>
      </div>

      {error && (
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg p-4 text-haven-error text-sm">
          {error}
          <button onClick={fetchAnalytics} className="ml-2 underline">
            Retry
          </button>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Total Gifts</span>
            <GiftIcon className="w-6 h-6 text-haven-primary" aria-hidden="true" />
          </div>
          <div className="text-2xl font-bold text-white">{analytics?.total_gifts ?? 0}</div>
          <Link href="/dashboard/gifts" className="text-sm text-haven-primary hover:text-haven-primary/80 mt-2 inline-block">
            View all
          </Link>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Activated Gifts</span>
            <CheckCircleIcon className="w-6 h-6 text-haven-active" aria-hidden="true" />
          </div>
          <div className="text-2xl font-bold text-white">{analytics?.activated_gifts ?? 0}</div>
          <div className="text-sm text-haven-active mt-2">
            {analytics?.activation_rate ?? 0}% activation rate
          </div>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Pending Commissions</span>
            <ClockIcon className="w-6 h-6 text-haven-warning" aria-hidden="true" />
          </div>
          <div className="text-2xl font-bold text-haven-warning">
            {formatCurrency(analytics?.pending_commissions ?? 0)}
          </div>
          <Link href="/dashboard/commissions" className="text-sm text-haven-primary hover:text-haven-primary/80 mt-2 inline-block">
            View details
          </Link>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-haven-text-secondary">Total Earned</span>
            <CurrencyDollarIcon className="w-6 h-6 text-haven-active" aria-hidden="true" />
          </div>
          <div className="text-2xl font-bold text-haven-active">
            {formatCurrency(analytics?.total_commissions ?? 0)}
          </div>
          <div className="text-sm text-haven-text-tertiary mt-2">
            {formatCurrency(analytics?.paid_commissions ?? 0)} paid
          </div>
        </div>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-4">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Link
            href="/dashboard/gifts"
            className="flex items-center gap-3 p-4 border border-haven-border rounded-lg hover:border-haven-primary hover:bg-haven-elevated transition-colors"
          >
            <GiftIcon className="w-6 h-6 text-haven-primary" aria-hidden="true" />
            <div>
              <div className="font-medium text-white">Create New Gift</div>
              <div className="text-sm text-haven-text-tertiary">Send gift to a homebuyer</div>
            </div>
          </Link>

          <Link
            href="/dashboard/analytics"
            className="flex items-center gap-3 p-4 border border-haven-border rounded-lg hover:border-haven-primary hover:bg-haven-elevated transition-colors"
          >
            <CheckCircleIcon className="w-6 h-6 text-haven-active" aria-hidden="true" />
            <div>
              <div className="font-medium text-white">View Analytics</div>
              <div className="text-sm text-haven-text-tertiary">Track your performance</div>
            </div>
          </Link>

          <Link
            href="/dashboard/settings"
            className="flex items-center gap-3 p-4 border border-haven-border rounded-lg hover:border-haven-primary hover:bg-haven-elevated transition-colors"
          >
            <CurrencyDollarIcon className="w-6 h-6 text-haven-primary" aria-hidden="true" />
            <div>
              <div className="font-medium text-white">Update Settings</div>
              <div className="text-sm text-haven-text-tertiary">Customize your profile</div>
            </div>
          </Link>
        </div>
      </div>

      {analytics?.recent_activity && analytics.recent_activity.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-white mb-4">Recent Activity</h2>
          <ul className="space-y-4">
            {analytics.recent_activity.slice(0, 5).map((activity, index) => (
              <li
                key={`${activity.created_at ?? 'noDate'}-${index}`}
                className="flex items-start gap-3 pb-4 border-b border-haven-border last:border-0 last:pb-0"
              >
                <div className="flex-shrink-0 w-2 h-2 bg-haven-primary rounded-full mt-2" aria-hidden="true" />
                <div className="flex-1">
                  <div className="text-sm text-white">{activity.name || 'Gift'}</div>
                  <div className="text-xs text-haven-text-tertiary">
                    {activity.status === 'activated' ? 'Activated gift' : 'Gift created'} •{' '}
                    {formatDate(activity.created_at)}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
