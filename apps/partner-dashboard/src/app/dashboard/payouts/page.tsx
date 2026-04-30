'use client';

import { useEffect, useState } from 'react';
import {
  ArrowDownTrayIcon,
  ClockIcon,
  CurrencyDollarIcon,
  CheckCircleIcon,
  DocumentTextIcon,
  ExclamationTriangleIcon,
} from '@heroicons/react/24/outline';
import { apiClient } from '@/lib/api';
import { logError } from '@/lib/log-error';
import { formatCurrency } from '@/lib/utils';

type PayoutSummary = {
  pending_amount: number;
  approved_amount: number;
  paid_lifetime: number;
  paid_ytd: number;
  stripe_account_status: string;
  stripe_payouts_enabled: boolean;
  last_payout_requested_at: string | null;
};

type PayoutResult = {
  paid_count: number;
  failed_count: number;
  paid_total: number;
  transfers: Array<{ commission_id: string; transfer_id: string; amount: number }>;
};

export default function PayoutsPage() {
  const [summary, setSummary] = useState<PayoutSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [requesting, setRequesting] = useState(false);
  const [result, setResult] = useState<PayoutResult | null>(null);
  const [taxLinkLoading, setTaxLinkLoading] = useState(false);

  useEffect(() => {
    fetchSummary();
  }, []);

  const fetchSummary = async () => {
    try {
      setError(null);
      const res = await apiClient<PayoutSummary>('/api/v1/partners/me/payouts/summary');
      if (res.success && res.data) {
        setSummary(res.data);
      } else {
        setError(res.error || 'Failed to load payouts summary');
      }
    } catch (err) {
      setError('Failed to load payouts summary. Please try again.');
      logError('Error fetching payout summary', err);
    } finally {
      setLoading(false);
    }
  };

  const requestPayout = async () => {
    if (!summary || summary.approved_amount <= 0) return;
    setRequesting(true);
    setResult(null);
    try {
      const res = await apiClient<PayoutResult>('/api/v1/partners/me/payouts', {
        method: 'POST',
      });
      if (res.success && res.data) {
        setResult(res.data);
        await fetchSummary();
      } else {
        setError(res.error || 'Payout request failed');
      }
    } catch (err) {
      setError('Payout request failed. Please try again.');
      logError('Error requesting payout', err);
    } finally {
      setRequesting(false);
    }
  };

  const openTaxDocs = async () => {
    setTaxLinkLoading(true);
    try {
      const res = await apiClient<{ url: string }>('/api/v1/partners/me/tax-form-link', {
        method: 'POST',
      });
      if (res.success && res.data?.url) {
        // The Stripe-hosted Express dashboard is where 1099-NEC forms
        // appear. Open in a new tab so the partner doesn't lose their
        // place here.
        window.open(res.data.url, '_blank', 'noopener,noreferrer');
      } else {
        setError(res.error || 'Could not open tax documents');
      }
    } catch (err) {
      setError('Could not open tax documents. Please try again.');
      logError('Error fetching tax form link', err);
    } finally {
      setTaxLinkLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-haven-primary"></div>
      </div>
    );
  }

  const onboardingIncomplete =
    !summary?.stripe_payouts_enabled || summary.stripe_account_status !== 'enabled';
  const canRequestPayout =
    !!summary &&
    summary.stripe_payouts_enabled &&
    summary.approved_amount > 0 &&
    !requesting;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Payouts</h1>
        <p className="text-haven-text-secondary text-sm mt-1">
          Withdraw your earnings to your connected bank account, anytime.
        </p>
      </div>

      {/* Error banner */}
      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400 text-sm flex items-start gap-3">
          <ExclamationTriangleIcon className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            {error}
            <button onClick={fetchSummary} className="ml-2 underline">
              Retry
            </button>
          </div>
        </div>
      )}

      {/* Onboarding-incomplete banner */}
      {onboardingIncomplete && (
        <div className="bg-yellow-500/10 border border-yellow-500/30 rounded-lg p-4 text-yellow-400 text-sm flex items-start gap-3">
          <ExclamationTriangleIcon className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="font-medium">
              Stripe Connect onboarding is not complete
              {summary?.stripe_account_status
                ? ` (current status: ${summary.stripe_account_status})`
                : ''}
              .
            </p>
            <p className="mt-1">
              Finish setup in{' '}
              <a href="/dashboard/settings" className="underline hover:text-yellow-300">
                Settings
              </a>{' '}
              to start receiving payouts.
            </p>
          </div>
        </div>
      )}

      {/* Last payout result */}
      {result && (
        <div
          className={`rounded-lg p-4 text-sm flex items-start gap-3 ${
            result.failed_count > 0
              ? 'bg-yellow-500/10 border border-yellow-500/30 text-yellow-400'
              : result.paid_count > 0
                ? 'bg-haven-active/10 border border-haven-active/30 text-haven-active'
                : 'bg-haven-elevated border border-haven-border text-haven-text-secondary'
          }`}
        >
          <CheckCircleIcon className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div>
            {result.paid_count === 0 && result.failed_count === 0 ? (
              <p>No commissions were eligible for payout right now.</p>
            ) : (
              <>
                <p className="font-medium">
                  Sent {formatCurrency(result.paid_total)} across {result.paid_count} commission
                  {result.paid_count === 1 ? '' : 's'}.
                </p>
                {result.failed_count > 0 && (
                  <p className="mt-1">
                    {result.failed_count} commission{result.failed_count === 1 ? '' : 's'} did
                    not transfer; we&apos;ll retry on your next payout.
                  </p>
                )}
              </>
            )}
          </div>
        </div>
      )}

      {/* Earnings summary cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card">
          <div className="flex items-center gap-3 mb-2">
            <ClockIcon className="w-5 h-5 text-haven-warning" />
            <span className="text-sm text-haven-text-secondary">Pending</span>
          </div>
          <p className="text-2xl font-bold text-haven-warning">
            {formatCurrency(summary?.pending_amount ?? 0)}
          </p>
          <p className="text-xs text-haven-text-tertiary mt-2">In 30-day refund window</p>
        </div>
        <div className="card">
          <div className="flex items-center gap-3 mb-2">
            <CurrencyDollarIcon className="w-5 h-5 text-haven-primary" />
            <span className="text-sm text-haven-text-secondary">Available</span>
          </div>
          <p className="text-2xl font-bold text-haven-primary">
            {formatCurrency(summary?.approved_amount ?? 0)}
          </p>
          <p className="text-xs text-haven-text-tertiary mt-2">Ready to withdraw</p>
        </div>
        <div className="card">
          <div className="flex items-center gap-3 mb-2">
            <CheckCircleIcon className="w-5 h-5 text-haven-active" />
            <span className="text-sm text-haven-text-secondary">Paid (this year)</span>
          </div>
          <p className="text-2xl font-bold text-haven-active">
            {formatCurrency(summary?.paid_ytd ?? 0)}
          </p>
          <p className="text-xs text-haven-text-tertiary mt-2">Reported to Stripe for 1099</p>
        </div>
        <div className="card">
          <div className="flex items-center gap-3 mb-2">
            <CheckCircleIcon className="w-5 h-5 text-haven-text-secondary" />
            <span className="text-sm text-haven-text-secondary">Paid (lifetime)</span>
          </div>
          <p className="text-2xl font-bold text-white">
            {formatCurrency(summary?.paid_lifetime ?? 0)}
          </p>
          <p className="text-xs text-haven-text-tertiary mt-2">Since you joined</p>
        </div>
      </div>

      {/* Action panel */}
      <div className="card">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div>
            <h2 className="text-lg font-semibold text-white">Withdraw your earnings</h2>
            <p className="text-sm text-haven-text-secondary mt-1">
              Available funds transfer to the bank account you connected via Stripe. Most
              banks see the deposit in 1&ndash;2 business days.
            </p>
            {summary?.last_payout_requested_at && (
              <p className="text-xs text-haven-text-tertiary mt-2">
                Last requested:{' '}
                {new Date(summary.last_payout_requested_at).toLocaleString()}
              </p>
            )}
          </div>
          <button
            onClick={requestPayout}
            disabled={!canRequestPayout}
            className={`flex items-center justify-center gap-2 px-6 py-3 rounded-lg font-semibold transition-colors duration-150 whitespace-nowrap ${
              canRequestPayout
                ? 'bg-haven-primary hover:bg-haven-primary/90 text-white'
                : 'bg-haven-elevated text-haven-text-tertiary cursor-not-allowed'
            }`}
          >
            <ArrowDownTrayIcon className="w-5 h-5" />
            {requesting
              ? 'Sending...'
              : summary && summary.approved_amount > 0
                ? `Request payout (${formatCurrency(summary.approved_amount)})`
                : 'No funds available'}
          </button>
        </div>
      </div>

      {/* Tax docs panel */}
      <div className="card">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div>
            <h2 className="text-lg font-semibold text-white">Tax documents</h2>
            <p className="text-sm text-haven-text-secondary mt-1">
              Stripe issues your 1099-NEC each January for any year we paid you $600 or more.
              Open your Stripe dashboard to download forms and see payout history.
            </p>
          </div>
          <button
            onClick={openTaxDocs}
            disabled={taxLinkLoading || !summary?.stripe_account_status}
            className="flex items-center justify-center gap-2 px-6 py-3 rounded-lg font-semibold bg-haven-elevated hover:bg-haven-elevated/70 text-white border border-haven-border transition-colors duration-150 whitespace-nowrap disabled:cursor-not-allowed disabled:opacity-60"
          >
            <DocumentTextIcon className="w-5 h-5" />
            {taxLinkLoading ? 'Opening...' : 'Open tax documents'}
          </button>
        </div>
      </div>
    </div>
  );
}
