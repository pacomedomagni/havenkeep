'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import {
  GiftIcon,
  CheckCircleIcon,
  ClockIcon,
  CurrencyDollarIcon,
} from '@heroicons/react/24/outline';

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

  useEffect(() => {
    fetchAnalytics();
  }, []);

  const fetchAnalytics = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch('/api/v1/partners/analytics', {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      const data = await response.json();
      if (data.success) {
        setAnalytics(data.data);
      }
    } catch (error) {
      console.error('Error fetching analytics:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
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
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Partner Dashboard</h1>
        <p className="text-gray-600 mt-1">
          Welcome back. Here&apos;s an overview of your partner activity.
        </p>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-white rounded-lg shadow-sm p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-gray-600">Total Gifts</span>
            <GiftIcon className="w-8 h-8 text-blue-600" />
          </div>
          <div className="text-3xl font-bold text-gray-900">{analytics?.total_gifts || 0}</div>
          <Link href="/dashboard/gifts" className="text-sm text-blue-600 hover:text-blue-800 mt-2 inline-block">
            View all →
          </Link>
        </div>

        <div className="bg-white rounded-lg shadow-sm p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-gray-600">Activated Gifts</span>
            <CheckCircleIcon className="w-8 h-8 text-green-600" />
          </div>
          <div className="text-3xl font-bold text-gray-900">{analytics?.activated_gifts || 0}</div>
          <div className="text-sm text-green-600 mt-2">
            {analytics?.activation_rate || 0}% activation rate
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-sm p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-gray-600">Pending Commissions</span>
            <ClockIcon className="w-8 h-8 text-yellow-600" />
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {formatCurrency(analytics?.pending_commissions || 0)}
          </div>
          <Link href="/dashboard/partner-commissions" className="text-sm text-blue-600 hover:text-blue-800 mt-2 inline-block">
            View details →
          </Link>
        </div>

        <div className="bg-white rounded-lg shadow-sm p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-gray-600">Total Earned</span>
            <CurrencyDollarIcon className="w-8 h-8 text-green-600" />
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {formatCurrency(analytics?.total_commissions || 0)}
          </div>
          <div className="text-sm text-gray-600 mt-2">
            {formatCurrency(analytics?.paid_commissions || 0)} paid
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="bg-white rounded-lg shadow-sm p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Link
            href="/dashboard/gifts"
            className="flex items-center gap-3 p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-colors"
          >
            <GiftIcon className="w-6 h-6 text-blue-600" />
            <div>
              <div className="font-medium text-gray-900">Create New Gift</div>
              <div className="text-sm text-gray-500">Send gift to a homebuyer</div>
            </div>
          </Link>

          <Link
            href="/dashboard/partner-analytics"
            className="flex items-center gap-3 p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-colors"
          >
            <CheckCircleIcon className="w-6 h-6 text-green-600" />
            <div>
              <div className="font-medium text-gray-900">View Analytics</div>
              <div className="text-sm text-gray-500">Track your performance</div>
            </div>
          </Link>

          <Link
            href="/dashboard/partner-settings"
            className="flex items-center gap-3 p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-colors"
          >
            <CurrencyDollarIcon className="w-6 h-6 text-purple-600" />
            <div>
              <div className="font-medium text-gray-900">Update Settings</div>
              <div className="text-sm text-gray-500">Customize your profile</div>
            </div>
          </Link>
        </div>
      </div>

      {/* Recent Activity */}
      {analytics?.recent_activity && analytics.recent_activity.length > 0 && (
        <div className="bg-white rounded-lg shadow-sm p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Recent Activity</h2>
          <div className="space-y-4">
            {analytics.recent_activity.slice(0, 5).map((activity: any, index: number) => (
              <div key={index} className="flex items-start gap-3 pb-4 border-b border-gray-100 last:border-0 last:pb-0">
                <div className="flex-shrink-0 w-2 h-2 bg-blue-600 rounded-full mt-2"></div>
                <div className="flex-1">
                  <div className="text-sm text-gray-900">{activity.homebuyer_name}</div>
                  <div className="text-xs text-gray-500">
                    {activity.is_activated ? 'Activated gift' : 'Gift created'} •{' '}
                    {new Date(activity.created_at).toLocaleDateString()}
                  </div>
                </div>
                <div className="text-sm font-medium text-gray-900">
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
