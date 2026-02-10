'use client';

import { useState } from 'react';
import type { Referral, ReferralStatus } from '@/lib/types';

interface ReferralTableProps {
  referrals: Referral[];
}

type SortField = 'code' | 'status' | 'createdAt' | 'convertedAt';
type SortDirection = 'asc' | 'desc';

function StatusBadge({ status }: { status: ReferralStatus }) {
  const badgeClass =
    status === 'converted'
      ? 'badge-converted'
      : status === 'pending'
      ? 'badge-pending'
      : 'badge-expired';

  return <span className={badgeClass}>{status.charAt(0).toUpperCase() + status.slice(1)}</span>;
}

export default function ReferralTable({ referrals }: ReferralTableProps) {
  const [sortField, setSortField] = useState<SortField>('createdAt');
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');

  function handleSort(field: SortField) {
    if (field === sortField) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('desc');
    }
  }

  const sorted = [...referrals].sort((a, b) => {
    const aVal = a[sortField] ?? '';
    const bVal = b[sortField] ?? '';
    const cmp = aVal > bVal ? 1 : aVal < bVal ? -1 : 0;
    return sortDirection === 'asc' ? cmp : -cmp;
  });

  const SortIcon = ({ field }: { field: SortField }) => (
    <span className="ml-1 text-haven-text-tertiary">
      {sortField === field ? (sortDirection === 'asc' ? '\u2191' : '\u2193') : '\u2195'}
    </span>
  );

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead>
          <tr className="border-b border-haven-border">
            <th
              className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider cursor-pointer hover:text-haven-text-secondary"
              onClick={() => handleSort('code')}
            >
              Code <SortIcon field="code" />
            </th>
            <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
              Referred Email
            </th>
            <th
              className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider cursor-pointer hover:text-haven-text-secondary"
              onClick={() => handleSort('status')}
            >
              Status <SortIcon field="status" />
            </th>
            <th
              className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider cursor-pointer hover:text-haven-text-secondary"
              onClick={() => handleSort('createdAt')}
            >
              Created <SortIcon field="createdAt" />
            </th>
            <th
              className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider cursor-pointer hover:text-haven-text-secondary"
              onClick={() => handleSort('convertedAt')}
            >
              Converted At <SortIcon field="convertedAt" />
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-haven-border">
          {sorted.map((referral) => (
            <tr key={referral.id} className="hover:bg-haven-elevated/50 transition-colors">
              <td className="py-3 px-4 text-sm font-mono text-haven-primary">
                {referral.code}
              </td>
              <td className="py-3 px-4 text-sm text-haven-text-secondary">
                {referral.referredEmail || '\u2014'}
              </td>
              <td className="py-3 px-4">
                <StatusBadge status={referral.status} />
              </td>
              <td className="py-3 px-4 text-sm text-haven-text-secondary">
                {new Date(referral.createdAt).toLocaleDateString()}
              </td>
              <td className="py-3 px-4 text-sm text-haven-text-secondary">
                {referral.convertedAt
                  ? new Date(referral.convertedAt).toLocaleDateString()
                  : '\u2014'}
              </td>
            </tr>
          ))}
          {sorted.length === 0 && (
            <tr>
              <td colSpan={5} className="py-8 text-center text-haven-text-tertiary">
                No referrals found
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
