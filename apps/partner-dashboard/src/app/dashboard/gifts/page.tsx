'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { apiClient } from '@/lib/api';

interface Gift {
  id: string;
  homebuyer_name: string;
  homebuyer_email: string;
  home_address: string | null;
  closing_date: string | null;
  premium_months: number;
  status: 'created' | 'sent' | 'activated' | 'expired';
  is_activated: boolean;
  activated_at: string | null;
  created_at: string;
  amount_charged: number;
}

export default function GiftsPage() {
  const router = useRouter();
  const [gifts, setGifts] = useState<Gift[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<string>('all');
  const [showCreateModal, setShowCreateModal] = useState(false);

  useEffect(() => {
    fetchGifts();
  }, [filter]);

  const fetchGifts = async () => {
    try {
      setError(null);
      const url = filter === 'all'
        ? '/api/v1/partners/gifts'
        : `/api/v1/partners/gifts?status=${filter}`;

      const data = await apiClient<Gift[]>(url);
      if (data.success && data.data) {
        setGifts(data.data);
      }
    } catch (err) {
      setError('Failed to load gifts.');
      console.error('Error fetching gifts:', err);
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadge = (status: string, isActivated: boolean) => {
    if (isActivated) {
      return <span className="badge-converted">Activated</span>;
    }
    const classes: Record<string, string> = {
      created: 'badge-approved',
      sent: 'badge-pending',
      expired: 'badge-expired',
    };
    return (
      <span className={classes[status] || 'badge-pending'}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    );
  };

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
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-white">Closing Gifts</h1>
          <p className="text-haven-text-secondary text-sm mt-1">
            Manage gifts for your homebuyers
          </p>
        </div>
        <button
          onClick={() => setShowCreateModal(true)}
          className="btn-primary inline-flex items-center gap-2"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          Create New Gift
        </button>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg p-4 text-haven-error text-sm">
          {error}
          <button onClick={fetchGifts} className="ml-2 underline">Retry</button>
        </div>
      )}

      {/* Filter Tabs */}
      <div className="flex gap-2">
        {['all', 'created', 'activated', 'expired'].map((status) => (
          <button
            key={status}
            onClick={() => setFilter(status)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors duration-200 ${
              filter === status
                ? 'bg-haven-primary text-white'
                : 'bg-haven-surface text-haven-text-secondary hover:bg-haven-elevated hover:text-white border border-haven-border'
            }`}
          >
            {status.charAt(0).toUpperCase() + status.slice(1)}
          </button>
        ))}
      </div>

      {/* Gifts Table */}
      {gifts.length === 0 ? (
        <div className="card text-center py-12">
          <svg
            className="mx-auto h-12 w-12 text-haven-text-tertiary"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
            />
          </svg>
          <h3 className="mt-2 text-sm font-medium text-white">No gifts</h3>
          <p className="mt-1 text-sm text-haven-text-tertiary">
            Get started by creating a new closing gift.
          </p>
          <div className="mt-6">
            <button onClick={() => setShowCreateModal(true)} className="btn-primary">
              Create Gift
            </button>
          </div>
        </div>
      ) : (
        <div className="card p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-haven-border">
                  <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Homebuyer
                  </th>
                  <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Address
                  </th>
                  <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Closing Date
                  </th>
                  <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Premium
                  </th>
                  <th className="text-left py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="text-right py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Cost
                  </th>
                  <th className="text-right py-3 px-4 text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-haven-border">
                {gifts.map((gift) => (
                  <tr key={gift.id} className="hover:bg-haven-elevated/50 transition-colors">
                    <td className="py-3 px-4">
                      <div className="text-sm font-medium text-white">
                        {gift.homebuyer_name}
                      </div>
                      <div className="text-xs text-haven-text-tertiary">
                        {gift.homebuyer_email}
                      </div>
                    </td>
                    <td className="py-3 px-4 text-sm text-haven-text-secondary">
                      {gift.home_address || '\u2014'}
                    </td>
                    <td className="py-3 px-4 text-sm text-haven-text-secondary">
                      {gift.closing_date
                        ? new Date(gift.closing_date).toLocaleDateString()
                        : '\u2014'}
                    </td>
                    <td className="py-3 px-4 text-sm text-haven-text-secondary">
                      {gift.premium_months} months
                    </td>
                    <td className="py-3 px-4">
                      {getStatusBadge(gift.status, gift.is_activated)}
                    </td>
                    <td className="py-3 px-4 text-sm text-white font-medium text-right">
                      ${gift.amount_charged.toFixed(2)}
                    </td>
                    <td className="py-3 px-4 text-right">
                      <button
                        onClick={() => router.push(`/dashboard/gifts/${gift.id}`)}
                        className="text-sm text-haven-primary hover:text-haven-primary/80"
                      >
                        View Details
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Create Gift Modal */}
      {showCreateModal && (
        <CreateGiftModal
          onClose={() => setShowCreateModal(false)}
          onSuccess={() => {
            setShowCreateModal(false);
            fetchGifts();
          }}
        />
      )}
    </div>
  );
}

function CreateGiftModal({
  onClose,
  onSuccess,
}: {
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [formData, setFormData] = useState({
    homebuyer_name: '',
    homebuyer_email: '',
    homebuyer_phone: '',
    home_address: '',
    closing_date: '',
    premium_months: 6,
    custom_message: '',
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const data = await apiClient('/api/v1/partners/gifts', {
        method: 'POST',
        body: formData,
      });

      if (data.success) {
        onSuccess();
      } else {
        setError(data.message || 'Failed to create gift');
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-haven-surface border border-haven-border rounded-xl p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-xl font-bold text-white">Create Closing Gift</h2>
          <button onClick={onClose} className="text-haven-text-tertiary hover:text-white">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {error && (
          <div className="mb-4 bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Homebuyer Name *
            </label>
            <input
              type="text"
              required
              value={formData.homebuyer_name}
              onChange={(e) => setFormData({ ...formData, homebuyer_name: e.target.value })}
              className="input-field"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Email *
            </label>
            <input
              type="email"
              required
              value={formData.homebuyer_email}
              onChange={(e) => setFormData({ ...formData, homebuyer_email: e.target.value })}
              className="input-field"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Phone
            </label>
            <input
              type="tel"
              value={formData.homebuyer_phone}
              onChange={(e) => setFormData({ ...formData, homebuyer_phone: e.target.value })}
              className="input-field"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Home Address
            </label>
            <input
              type="text"
              value={formData.home_address}
              onChange={(e) => setFormData({ ...formData, home_address: e.target.value })}
              className="input-field"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Closing Date
            </label>
            <input
              type="date"
              value={formData.closing_date}
              onChange={(e) => setFormData({ ...formData, closing_date: e.target.value })}
              className="input-field"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Premium Months
            </label>
            <select
              value={formData.premium_months}
              onChange={(e) => setFormData({ ...formData, premium_months: Number(e.target.value) })}
              className="input-field"
            >
              <option value={3}>3 months</option>
              <option value={6}>6 months</option>
              <option value={12}>12 months</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Custom Message
            </label>
            <textarea
              value={formData.custom_message}
              onChange={(e) => setFormData({ ...formData, custom_message: e.target.value })}
              rows={3}
              placeholder="Welcome to your new home! I'm excited to share this tool..."
              className="input-field"
            />
          </div>

          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-secondary flex-1">
              Cancel
            </button>
            <button type="submit" disabled={loading} className="btn-primary flex-1">
              {loading ? 'Creating...' : 'Create Gift'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
