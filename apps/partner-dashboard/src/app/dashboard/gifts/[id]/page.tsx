'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { apiClient } from '@/lib/api';

interface Gift {
  id: string;
  homebuyer_name: string;
  homebuyer_email: string;
  homebuyer_phone: string | null;
  home_address: string | null;
  closing_date: string | null;
  premium_months: number;
  status: 'created' | 'sent' | 'activated' | 'expired';
  is_activated: boolean;
  activated_at: string | null;
  created_at: string;
  amount_charged: number;
  custom_message: string | null;
  activation_code?: string;
  activation_url?: string;
}

export default function GiftDetailPage() {
  const router = useRouter();
  const params = useParams();
  const giftId = params.id as string;

  const [gift, setGift] = useState<Gift | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showResendModal, setShowResendModal] = useState(false);
  const [copiedCode, setCopiedCode] = useState(false);
  const [copiedUrl, setCopiedUrl] = useState(false);

  useEffect(() => {
    fetchGift();
  }, [giftId]);

  const fetchGift = async () => {
    try {
      const data = await apiClient<Gift>(`/api/v1/partners/gifts/${giftId}`);
      if (data.success && data.data) {
        setGift(data.data);
      } else {
        setError(data.message || 'Failed to load gift');
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred while loading the gift');
    } finally {
      setLoading(false);
    }
  };

  const handleResendEmail = async () => {
    try {
      const data = await apiClient(`/api/v1/partners/gifts/${giftId}/resend`, {
        method: 'POST',
      });
      if (data.success) {
        setShowResendModal(false);
      } else {
        setError(data.message || 'Failed to resend email');
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred. Please try again.');
    }
  };

  const copyToClipboard = (text: string, type: 'code' | 'url') => {
    navigator.clipboard.writeText(text);
    if (type === 'code') {
      setCopiedCode(true);
      setTimeout(() => setCopiedCode(false), 2000);
    } else {
      setCopiedUrl(true);
      setTimeout(() => setCopiedUrl(false), 2000);
    }
  };

  const getStatusBadge = (status: string, isActivated: boolean) => {
    if (isActivated) return <span className="badge-converted">Activated</span>;
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

  if (error || !gift) {
    return (
      <div className="space-y-4">
        <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg p-4">
          <p className="text-haven-error">{error || 'Gift not found'}</p>
          <button
            onClick={() => router.push('/dashboard/gifts')}
            className="mt-4 text-haven-primary hover:text-haven-primary/80"
          >
            Back to Gifts
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-5xl">
      {/* Header */}
      <div>
        <button
          onClick={() => router.push('/dashboard/gifts')}
          className="text-haven-primary hover:text-haven-primary/80 mb-4 flex items-center gap-2 text-sm"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Gifts
        </button>
        <div className="flex justify-between items-start">
          <div>
            <h1 className="text-2xl font-bold text-white">Gift Details</h1>
            <p className="text-haven-text-secondary text-sm mt-1">
              Created {new Date(gift.created_at).toLocaleDateString()}
            </p>
          </div>
          {getStatusBadge(gift.status, gift.is_activated)}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Homebuyer Information */}
          <div className="card">
            <h2 className="text-lg font-semibold text-white mb-4">Homebuyer Information</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Name</label>
                <p className="text-white">{gift.homebuyer_name}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Email</label>
                <p className="text-white">{gift.homebuyer_email}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Phone</label>
                <p className="text-white">{gift.homebuyer_phone || '\u2014'}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Closing Date</label>
                <p className="text-white">
                  {gift.closing_date ? new Date(gift.closing_date).toLocaleDateString() : '\u2014'}
                </p>
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Home Address</label>
                <p className="text-white">{gift.home_address || '\u2014'}</p>
              </div>
            </div>
          </div>

          {/* Gift Details */}
          <div className="card">
            <h2 className="text-lg font-semibold text-white mb-4">Gift Details</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Premium Duration</label>
                <p className="text-white text-2xl font-bold">{gift.premium_months} months</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Amount Charged</label>
                <p className="text-white text-2xl font-bold">${gift.amount_charged.toFixed(2)}</p>
              </div>
              {gift.custom_message && (
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-haven-text-tertiary mb-1">Custom Message</label>
                  <p className="text-haven-text-secondary bg-haven-elevated p-3 rounded-lg border border-haven-border">
                    {gift.custom_message}
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Activation Status */}
          {gift.is_activated && gift.activated_at && (
            <div className="bg-haven-active/10 border border-haven-active/30 rounded-xl p-6">
              <div className="flex items-center gap-3 mb-2">
                <svg className="w-6 h-6 text-haven-active" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <h3 className="text-lg font-semibold text-haven-active">Gift Activated!</h3>
              </div>
              <p className="text-haven-text-secondary">
                This gift was activated on {new Date(gift.activated_at).toLocaleDateString()} at{' '}
                {new Date(gift.activated_at).toLocaleTimeString()}
              </p>
            </div>
          )}
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Activation Information */}
          {!gift.is_activated && gift.activation_code && (
            <div className="card">
              <h3 className="text-lg font-semibold text-white mb-4">Activation Details</h3>

              <div className="mb-4">
                <label className="block text-sm font-medium text-haven-text-tertiary mb-2">Activation Code</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={gift.activation_code}
                    readOnly
                    className="input-field flex-1 font-mono text-sm"
                  />
                  <button
                    onClick={() => copyToClipboard(gift.activation_code!, 'code')}
                    className="btn-primary px-3"
                  >
                    {copiedCode ? 'Copied' : 'Copy'}
                  </button>
                </div>
              </div>

              {gift.activation_url && (
                <div className="mb-4">
                  <label className="block text-sm font-medium text-haven-text-tertiary mb-2">Activation URL</label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={gift.activation_url}
                      readOnly
                      className="input-field flex-1 text-xs"
                    />
                    <button
                      onClick={() => copyToClipboard(gift.activation_url!, 'url')}
                      className="btn-primary px-3"
                    >
                      {copiedUrl ? 'Copied' : 'Copy'}
                    </button>
                  </div>
                </div>
              )}

              <button
                onClick={() => setShowResendModal(true)}
                className="btn-secondary w-full"
              >
                Resend Gift Email
              </button>
            </div>
          )}

          {/* Quick Stats */}
          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Quick Stats</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-sm text-haven-text-tertiary">Status</span>
                <span className="text-sm font-medium text-white capitalize">{gift.status}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-haven-text-tertiary">Amount Charged</span>
                <span className="text-sm font-medium text-white">
                  ${gift.amount_charged.toFixed(2)}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-haven-text-tertiary">Days Since Created</span>
                <span className="text-sm font-medium text-white">
                  {Math.max(0, Math.floor((Date.now() - new Date(gift.created_at).getTime()) / (1000 * 60 * 60 * 24)))}
                </span>
              </div>
            </div>
          </div>

          {/* Actions */}
          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Actions</h3>
            <div className="space-y-2">
              <button
                onClick={() => window.open(`mailto:${gift.homebuyer_email}`, '_blank')}
                className="btn-secondary w-full flex items-center justify-center gap-2"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
                Email Homebuyer
              </button>
              {gift.homebuyer_phone && (
                <button
                  onClick={() => window.open(`tel:${gift.homebuyer_phone}`, '_blank')}
                  className="btn-secondary w-full flex items-center justify-center gap-2"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                  </svg>
                  Call Homebuyer
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Resend Email Modal */}
      {showResendModal && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
          <div className="bg-haven-surface border border-haven-border rounded-xl p-6 max-w-md w-full mx-4">
            <h3 className="text-xl font-bold text-white mb-4">Resend Gift Email</h3>
            <p className="text-haven-text-secondary mb-6">
              Are you sure you want to resend the gift activation email to{' '}
              <strong className="text-white">{gift.homebuyer_email}</strong>?
            </p>
            <div className="flex gap-3">
              <button onClick={() => setShowResendModal(false)} className="btn-secondary flex-1">
                Cancel
              </button>
              <button onClick={handleResendEmail} className="btn-primary flex-1">
                Resend Email
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
