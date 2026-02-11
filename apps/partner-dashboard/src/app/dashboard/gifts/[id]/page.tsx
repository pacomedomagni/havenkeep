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
  activation_code: string;
  activation_url: string;
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
      console.error('Error fetching gift:', err);
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
        alert('Gift email resent successfully!');
      } else {
        alert(data.message || 'Failed to resend email');
      }
    } catch (err: any) {
      alert(err.message || 'An error occurred. Please try again.');
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
    if (isActivated) {
      return (
        <span className="px-3 py-1 text-sm font-semibold rounded-full bg-green-100 text-green-800">
          ✓ Activated
        </span>
      );
    }

    const badges: Record<string, JSX.Element> = {
      created: (
        <span className="px-3 py-1 text-sm font-semibold rounded-full bg-blue-100 text-blue-800">
          Created
        </span>
      ),
      sent: (
        <span className="px-3 py-1 text-sm font-semibold rounded-full bg-yellow-100 text-yellow-800">
          Sent
        </span>
      ),
      expired: (
        <span className="px-3 py-1 text-sm font-semibold rounded-full bg-red-100 text-red-800">
          Expired
        </span>
      ),
    };

    return badges[status] || badges.created;
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (error || !gift) {
    return (
      <div className="p-6">
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <p className="text-red-800">{error || 'Gift not found'}</p>
          <button
            onClick={() => router.push('/dashboard/gifts')}
            className="mt-4 text-blue-600 hover:text-blue-800"
          >
            ← Back to Gifts
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-5xl">
      {/* Header */}
      <div className="mb-6">
        <button
          onClick={() => router.push('/dashboard/gifts')}
          className="text-blue-600 hover:text-blue-800 mb-4 flex items-center gap-2"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Gifts
        </button>
        <div className="flex justify-between items-start">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">Gift Details</h1>
            <p className="text-gray-600 mt-1">
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
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-4">Homebuyer Information</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Name</label>
                <p className="text-gray-900">{gift.homebuyer_name}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
                <p className="text-gray-900">{gift.homebuyer_email}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Phone</label>
                <p className="text-gray-900">{gift.homebuyer_phone || '—'}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Closing Date</label>
                <p className="text-gray-900">
                  {gift.closing_date ? new Date(gift.closing_date).toLocaleDateString() : '—'}
                </p>
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-medium text-gray-700 mb-1">Home Address</label>
                <p className="text-gray-900">{gift.home_address || '—'}</p>
              </div>
            </div>
          </div>

          {/* Gift Details */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-4">Gift Details</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Premium Duration</label>
                <p className="text-gray-900 text-2xl font-bold">{gift.premium_months} months</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Amount Charged</label>
                <p className="text-gray-900 text-2xl font-bold">${gift.amount_charged.toFixed(2)}</p>
              </div>
              {gift.custom_message && (
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-gray-700 mb-1">Custom Message</label>
                  <p className="text-gray-900 bg-gray-50 p-3 rounded border border-gray-200">
                    {gift.custom_message}
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Activation Status */}
          {gift.is_activated && gift.activated_at && (
            <div className="bg-green-50 border border-green-200 rounded-lg p-6">
              <div className="flex items-center gap-3 mb-2">
                <svg className="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <h3 className="text-lg font-semibold text-green-900">Gift Activated!</h3>
              </div>
              <p className="text-green-800">
                This gift was activated on {new Date(gift.activated_at).toLocaleDateString()} at{' '}
                {new Date(gift.activated_at).toLocaleTimeString()}
              </p>
            </div>
          )}
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Activation Information */}
          {!gift.is_activated && (
            <div className="bg-white rounded-lg shadow-sm p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-4">Activation Details</h3>

              <div className="mb-4">
                <label className="block text-sm font-medium text-gray-700 mb-2">Activation Code</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={gift.activation_code}
                    readOnly
                    className="flex-1 px-3 py-2 border border-gray-300 rounded-md bg-gray-50 font-mono text-sm"
                  />
                  <button
                    onClick={() => copyToClipboard(gift.activation_code, 'code')}
                    className="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
                  >
                    {copiedCode ? '✓' : 'Copy'}
                  </button>
                </div>
              </div>

              <div className="mb-4">
                <label className="block text-sm font-medium text-gray-700 mb-2">Activation URL</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={gift.activation_url}
                    readOnly
                    className="flex-1 px-3 py-2 border border-gray-300 rounded-md bg-gray-50 text-xs"
                  />
                  <button
                    onClick={() => copyToClipboard(gift.activation_url, 'url')}
                    className="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
                  >
                    {copiedUrl ? '✓' : 'Copy'}
                  </button>
                </div>
              </div>

              <button
                onClick={() => setShowResendModal(true)}
                className="w-full px-4 py-2 border border-blue-600 text-blue-600 rounded-md hover:bg-blue-50"
              >
                Resend Gift Email
              </button>
            </div>
          )}

          {/* Quick Stats */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Quick Stats</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Status</span>
                <span className="text-sm font-medium text-gray-900 capitalize">{gift.status}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Premium Value</span>
                <span className="text-sm font-medium text-gray-900">
                  ${(gift.premium_months * 2).toFixed(2)}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Days Since Created</span>
                <span className="text-sm font-medium text-gray-900">
                  {Math.floor((Date.now() - new Date(gift.created_at).getTime()) / (1000 * 60 * 60 * 24))}
                </span>
              </div>
            </div>
          </div>

          {/* Actions */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Actions</h3>
            <div className="space-y-2">
              <button
                onClick={() => window.open(`mailto:${gift.homebuyer_email}`, '_blank')}
                className="w-full px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 flex items-center justify-center gap-2"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
                Email Homebuyer
              </button>
              {gift.homebuyer_phone && (
                <button
                  onClick={() => window.open(`tel:${gift.homebuyer_phone}`, '_blank')}
                  className="w-full px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 flex items-center justify-center gap-2"
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
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-xl font-bold mb-4">Resend Gift Email</h3>
            <p className="text-gray-600 mb-6">
              Are you sure you want to resend the gift activation email to{' '}
              <strong>{gift.homebuyer_email}</strong>?
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setShowResendModal(false)}
                className="flex-1 px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                onClick={handleResendEmail}
                className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
              >
                Resend Email
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
