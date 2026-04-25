'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/react/24/outline'
import { apiClient, ApiError } from '@/lib/api'

interface PartnerActionsProps {
  partnerId: string
}

interface Toast {
  message: string
  type: 'success' | 'error'
}

export default function PartnerActions({ partnerId }: PartnerActionsProps) {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [toast, setToast] = useState<Toast | null>(null)
  const [showRejectModal, setShowRejectModal] = useState(false)
  const [reason, setReason] = useState('')

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 4000)
      return () => clearTimeout(timer)
    }
  }, [toast])

  // Audit Ch10-W055: encode the id once at the boundary.
  const url = (suffix: string) => `/api/v1/admin/partners/${encodeURIComponent(partnerId)}${suffix}`

  const handleApprove = async () => {
    if (!confirm('Approve this partner?')) return

    setLoading(true)
    try {
      await apiClient(url('/approve'), { method: 'PUT' })
      setToast({ message: 'Partner approved successfully', type: 'success' })
      router.refresh()
    } catch (err) {
      setToast({
        message:
          err instanceof ApiError ? err.message : 'Failed to approve partner. Please try again.',
        type: 'error',
      })
    } finally {
      setLoading(false)
    }
  }

  const submitReject = async () => {
    setLoading(true)
    try {
      await apiClient(url('/reject'), {
        method: 'PUT',
        body: { reason: reason.trim() || undefined },
      })
      setToast({ message: 'Partner rejected. Notification email queued.', type: 'success' })
      setShowRejectModal(false)
      setReason('')
      router.refresh()
    } catch (err) {
      setToast({
        message:
          err instanceof ApiError ? err.message : 'Failed to reject partner. Please try again.',
        type: 'error',
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      {toast && (
        <div
          role="status"
          className={`mb-4 flex items-center gap-2 rounded-lg px-4 py-3 text-sm ${
            toast.type === 'success'
              ? 'bg-haven-active/10 border border-haven-active/30 text-haven-active'
              : 'bg-haven-error/10 border border-haven-error/30 text-haven-error'
          }`}
        >
          {toast.type === 'success' ? (
            <CheckCircleIcon className="h-5 w-5 flex-shrink-0" aria-hidden="true" />
          ) : (
            <XCircleIcon className="h-5 w-5 flex-shrink-0" aria-hidden="true" />
          )}
          {toast.message}
        </div>
      )}

      <div className="flex items-center gap-3">
        <button
          onClick={handleApprove}
          disabled={loading}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-green-500/20 text-green-400 hover:bg-green-500/30 transition-colors disabled:opacity-50"
        >
          Approve Partner
        </button>
        <button
          onClick={() => setShowRejectModal(true)}
          disabled={loading}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors disabled:opacity-50"
        >
          Reject Partner
        </button>
      </div>

      {showRejectModal && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50" role="dialog" aria-modal="true">
          <div className="bg-haven-surface border border-haven-border rounded-xl p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-semibold text-white mb-2">Reject partner</h3>
            <p className="text-sm text-haven-text-secondary mb-4">
              The partner will be notified by email. Adding a reason is optional but helps with appeals.
            </p>
            <label htmlFor="partner-reject-reason" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Reason (optional)
            </label>
            <textarea
              id="partner-reject-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value.slice(0, 1024))}
              rows={3}
              maxLength={1024}
              className="input-field w-full"
              placeholder="e.g. License could not be verified"
            />
            <div className="flex justify-end gap-3 mt-4">
              <button
                onClick={() => {
                  setShowRejectModal(false)
                  setReason('')
                }}
                className="btn-secondary"
                disabled={loading}
              >
                Cancel
              </button>
              <button onClick={submitReject} className="btn-primary" disabled={loading}>
                {loading ? 'Rejecting…' : 'Reject partner'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
