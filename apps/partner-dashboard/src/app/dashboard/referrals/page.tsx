'use client';

import { useState } from 'react';
import ReferralTable from '@/components/referral-table';
import GenerateReferral from '@/components/generate-referral';
import { PlusIcon } from '@heroicons/react/24/outline';
import type { Referral, ReferralStatus } from '@/lib/types';

// Mock data
const mockReferrals: Referral[] = [
  {
    id: '1',
    partnerId: 'p1',
    code: 'HK-ABCD-1234',
    referredEmail: 'john@example.com',
    referredUserId: 'u1',
    status: 'converted',
    convertedAt: '2025-03-15T10:30:00Z',
    createdAt: '2025-03-01T08:00:00Z',
  },
  {
    id: '2',
    partnerId: 'p1',
    code: 'HK-EFGH-5678',
    referredEmail: 'sarah@example.com',
    status: 'pending',
    createdAt: '2025-03-10T14:00:00Z',
  },
  {
    id: '3',
    partnerId: 'p1',
    code: 'HK-IJKL-9012',
    referredEmail: 'mike@example.com',
    status: 'expired',
    createdAt: '2025-01-05T09:00:00Z',
  },
  {
    id: '4',
    partnerId: 'p1',
    code: 'HK-MNOP-3456',
    referredEmail: 'emma@example.com',
    referredUserId: 'u4',
    status: 'converted',
    convertedAt: '2025-03-20T16:45:00Z',
    createdAt: '2025-03-12T11:00:00Z',
  },
  {
    id: '5',
    partnerId: 'p1',
    code: 'HK-QRST-7890',
    status: 'pending',
    createdAt: '2025-03-22T07:30:00Z',
  },
  {
    id: '6',
    partnerId: 'p1',
    code: 'HK-UVWX-2345',
    referredEmail: 'alex@example.com',
    status: 'pending',
    createdAt: '2025-03-25T13:15:00Z',
  },
  {
    id: '7',
    partnerId: 'p1',
    code: 'HK-YZAB-6789',
    referredEmail: 'lisa@example.com',
    status: 'expired',
    createdAt: '2025-02-10T10:00:00Z',
  },
  {
    id: '8',
    partnerId: 'p1',
    code: 'HK-CDEF-0123',
    referredEmail: 'tom@example.com',
    referredUserId: 'u8',
    status: 'converted',
    convertedAt: '2025-03-28T09:20:00Z',
    createdAt: '2025-03-18T15:00:00Z',
  },
];

const filterTabs: { label: string; value: ReferralStatus | 'all' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Pending', value: 'pending' },
  { label: 'Converted', value: 'converted' },
  { label: 'Expired', value: 'expired' },
];

export default function ReferralsPage() {
  const [activeFilter, setActiveFilter] = useState<ReferralStatus | 'all'>('all');
  const [showGenerateModal, setShowGenerateModal] = useState(false);

  const filteredReferrals =
    activeFilter === 'all'
      ? mockReferrals
      : mockReferrals.filter((r) => r.status === activeFilter);

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
                ? mockReferrals.length
                : mockReferrals.filter((r) => r.status === tab.value).length})
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
        onClose={() => setShowGenerateModal(false)}
      />
    </div>
  );
}
