'use client';

import { useState, useEffect } from 'react';
import ReferralTable from '@/components/referral-table';
import GenerateReferral from '@/components/generate-referral';
import { PlusIcon } from '@heroicons/react/24/outline';
import type { Referral, ReferralStatus } from '@/lib/types';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || '';

const filterTabs: { label: string; value: ReferralStatus | 'all' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Pending', value: 'pending' },
  { label: 'Converted', value: 'converted' },
  { label: 'Expired', value: 'expired' },
];

export default function ReferralsPage() {
  const [referrals, setReferrals] = useState<Referral[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeFilter, setActiveFilter] = useState<ReferralStatus | 'all'>('all');
  const [showGenerateModal, setShowGenerateModal] = useState(false);

  useEffect(() => {
    fetchReferrals();
  }, []);

  const fetchReferrals = async () => {
    try {
      setError(null);
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/v1/partners/gifts`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      const data = await response.json();
      if (data.success) {
        // Map gifts to referral format for display
        const mapped: Referral[] = (data.data || []).map((gift: any) => ({
          id: gift.id,
          partnerId: gift.partner_id,
          code: gift.activation_code || gift.id.substring(0, 12).toUpperCase(),
          referredEmail: gift.homebuyer_email,
          referredUserId: gift.activated_user_id,
          status: gift.is_activated
            ? 'converted'
            : new Date(gift.expires_at) < new Date()
            ? 'expired'
            : 'pending',
          convertedAt: gift.activated_at,
          createdAt: gift.created_at,
        }));
        setReferrals(mapped);
      }
    } catch (err) {
      setError('Failed to load referrals. Please try again.');
      console.error('Error fetching referrals:', err);
    } finally {
      setLoading(false);
    }
  };

  const filteredReferrals =
    activeFilter === 'all'
      ? referrals
      : referrals.filter((r) => r.status === activeFilter);

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
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Referrals</h1>
          <p className="text-haven-text-secondary text-sm mt-1">
            Manage and track your referral codes
          </p>
        </div>
        <button
          onClick={() => setShowGenerateModal(true)}
          className="btn-primary inline-flex items-center gap-2"
        >
          <PlusIcon className="w-4 h-4" />
          Generate Code
        </button>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400 text-sm">
          {error}
          <button onClick={fetchReferrals} className="ml-2 underline">
            Retry
          </button>
        </div>
      )}

      {/* Filter tabs */}
      <div className="flex gap-2">
        {filterTabs.map((tab) => (
          <button
            key={tab.value}
            onClick={() => setActiveFilter(tab.value)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors duration-200 ${
              activeFilter === tab.value
                ? 'bg-haven-primary text-white'
                : 'bg-haven-surface text-haven-text-secondary hover:bg-haven-elevated hover:text-white border border-haven-border'
            }`}
          >
            {tab.label}
            <span className="ml-1.5 text-xs opacity-70">
              ({tab.value === 'all'
                ? referrals.length
                : referrals.filter((r) => r.status === tab.value).length})
            </span>
          </button>
        ))}
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <ReferralTable referrals={filteredReferrals} />
      </div>

      {/* Generate Referral Modal */}
      <GenerateReferral
        isOpen={showGenerateModal}
        onClose={() => {
          setShowGenerateModal(false);
          fetchReferrals();
        }}
      />
    </div>
  );
}
