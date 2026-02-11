'use client';

import { useState, useEffect } from 'react';
import CommissionTable from '@/components/commission-table';
import { CurrencyDollarIcon, ClockIcon } from '@heroicons/react/24/outline';
import type { Commission, CommissionStatus } from '@/lib/types';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || '';

function formatDollar(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount);
}

export default function CommissionsPage() {
  const [commissions, setCommissions] = useState<Commission[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchCommissions();
  }, []);

  const fetchCommissions = async () => {
    try {
      setError(null);
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/v1/partners/commissions`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      const data = await response.json();
      if (data.success) {
        const mapped: Commission[] = (data.data || []).map((c: any) => ({
          id: c.id,
          partnerId: c.reference_name || c.partner_id,
          referralId: c.reference_type || c.type,
          amount: parseFloat(c.amount),
          status: c.status as CommissionStatus,
          paidAt: c.paid_at,
          createdAt: c.created_at,
        }));
        setCommissions(mapped);
      }
    } catch (err) {
      setError('Failed to load commissions. Please try again.');
      console.error('Error fetching commissions:', err);
    } finally {
      setLoading(false);
    }
  };

  const pendingTotal = commissions
    .filter((c) => c.status === 'pending')
    .reduce((sum, c) => sum + c.amount, 0);

  const paidTotal = commissions
    .filter((c) => c.status === 'paid')
    .reduce((sum, c) => sum + c.amount, 0);

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
        <h1 className="text-2xl font-bold text-white">Commissions</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Track your earnings from referral conversions
        </p>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400 text-sm">
          {error}
          <button onClick={fetchCommissions} className="ml-2 underline">
            Retry
          </button>
        </div>
      )}

      {/* Summary cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="card">
          <div className="flex items-center gap-3 mb-2">
            <ClockIcon className="w-5 h-5 text-haven-warning" />
            <span className="text-sm text-haven-text-secondary">Pending Commissions</span>
          </div>
          <p className="text-2xl font-bold text-haven-warning">{formatDollar(pendingTotal)}</p>
        </div>
        <div className="card">
          <div className="flex items-center gap-3 mb-2">
            <CurrencyDollarIcon className="w-5 h-5 text-haven-active" />
            <span className="text-sm text-haven-text-secondary">Total Paid</span>
          </div>
          <p className="text-2xl font-bold text-haven-active">{formatDollar(paidTotal)}</p>
        </div>
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <CommissionTable commissions={commissions} />
      </div>
    </div>
  );
}
