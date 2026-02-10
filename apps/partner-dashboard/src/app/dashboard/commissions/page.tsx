'use client';

import CommissionTable from '@/components/commission-table';
import { CurrencyDollarIcon, ClockIcon } from '@heroicons/react/24/outline';
import type { Commission } from '@/lib/types';

// Mock data
const mockCommissions: Commission[] = [
  {
    id: 'c1',
    partnerId: 'john@example.com',
    referralId: 'HK-ABCD-1234',
    amount: 25.0,
    status: 'paid',
    paidAt: '2025-03-20T10:00:00Z',
    createdAt: '2025-03-15T10:30:00Z',
  },
  {
    id: 'c2',
    partnerId: 'emma@example.com',
    referralId: 'HK-MNOP-3456',
    amount: 25.0,
    status: 'paid',
    paidAt: '2025-03-25T14:00:00Z',
    createdAt: '2025-03-20T16:45:00Z',
  },
  {
    id: 'c3',
    partnerId: 'tom@example.com',
    referralId: 'HK-CDEF-0123',
    amount: 25.0,
    status: 'pending',
    createdAt: '2025-03-28T09:20:00Z',
  },
  {
    id: 'c4',
    partnerId: 'kate@example.com',
    referralId: 'HK-GHIJ-4567',
    amount: 50.0,
    status: 'pending',
    createdAt: '2025-04-01T12:00:00Z',
  },
  {
    id: 'c5',
    partnerId: 'dave@example.com',
    referralId: 'HK-KLMN-8901',
    amount: 25.0,
    status: 'paid',
    paidAt: '2025-03-10T08:00:00Z',
    createdAt: '2025-03-05T15:30:00Z',
  },
  {
    id: 'c6',
    partnerId: 'nina@example.com',
    referralId: 'HK-OPQR-2345',
    amount: 25.0,
    status: 'cancelled',
    createdAt: '2025-02-20T11:00:00Z',
  },
  {
    id: 'c7',
    partnerId: 'chris@example.com',
    referralId: 'HK-STUV-6789',
    amount: 50.0,
    status: 'pending',
    createdAt: '2025-04-02T09:00:00Z',
  },
];

function formatDollar(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount);
}

export default function CommissionsPage() {
  const pendingTotal = mockCommissions
    .filter((c) => c.status === 'pending')
    .reduce((sum, c) => sum + c.amount, 0);

  const paidTotal = mockCommissions
    .filter((c) => c.status === 'paid')
    .reduce((sum, c) => sum + c.amount, 0);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Commissions</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Track your earnings from referral conversions
        </p>
      </div>

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
        <CommissionTable commissions={mockCommissions} />
      </div>
    </div>
  );
}
