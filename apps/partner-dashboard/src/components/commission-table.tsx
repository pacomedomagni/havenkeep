'use client';

import type { Commission, CommissionStatus } from '@/lib/types';

interface CommissionTableProps {
  commissions: Commission[];
}

function StatusBadge({ status }: { status: CommissionStatus }) {
  const badgeClass =
    status === 'paid'
      ? 'badge-paid'
      : status === 'pending'
      ? 'badge-pending'
      : 'badge-cancelled';

  return <span className={badgeClass}>{status.charAt(0).toUpperCase() + status.slice(1)}</span>;
}

function formatDollar(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount);
}

export default function CommissionTable({ commissions }: CommissionTableProps) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead>
          <tr className="border-b border-haven-border">
            <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
              Referral Code
            </th>
            <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
              User
            </th>
            <th className="text-right py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
              Amount
            </th>
            <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
              Status
            </th>
            <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
              Date
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-haven-border">
          {commissions.map((commission) => (
            <tr key={commission.id} className="hover:bg-haven-elevated/50 transition-colors">
              <td className="py-3 px-4 text-sm font-mono text-haven-primary">
                {commission.referralId}
              </td>
              <td className="py-3 px-4 text-sm text-haven-text-secondary">
                {commission.partnerId}
              </td>
              <td className="py-3 px-4 text-sm text-white font-medium text-right">
                {formatDollar(commission.amount)}
              </td>
              <td className="py-3 px-4">
                <StatusBadge status={commission.status} />
              </td>
              <td className="py-3 px-4 text-sm text-haven-text-secondary">
                {new Date(commission.createdAt).toLocaleDateString()}
              </td>
            </tr>
          ))}
          {commissions.length === 0 && (
            <tr>
              <td colSpan={5} className="py-8 text-center text-haven-text-tertiary">
                No commissions found
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
