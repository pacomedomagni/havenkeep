'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/react/24/outline'
import { apiClient } from '@/lib/api'

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

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 4000)
      return () => clearTimeout(timer)
    }
  }, [toast])

  const handleApprove = async () => {
    if (!confirm('Are you sure you want to approve this partner?')) return

    setLoading(true)
    try {
      await apiClient(`/api/v1/admin/partners/${partnerId}/approve`, {
        method: 'PUT',
      })
      setToast({ message: 'Partner approved successfully', type: 'success' })
      router.refresh()
    } catch {
      setToast({ message: 'Failed to approve partner. Please try again.', type: 'error' })
    } finally {
      setLoading(false)
    }
  }

  const handleReject = async () => {
    if (!confirm('Are you sure you want to reject this partner?')) return

    setLoading(true)
    try {
      await apiClient(`/api/v1/admin/partners/${partnerId}/reject`, {
        method: 'PUT',
      })
      setToast({ message: 'Partner rejected successfully', type: 'success' })
      router.refresh()
    } catch {
      setToast({ message: 'Failed to reject partner. Please try again.', type: 'error' })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      {toast && (
        <div className={`mb-4 flex items-center gap-2 rounded-lg px-4 py-3 text-sm ${
          toast.type === 'success'
            ? 'bg-haven-active/10 border border-haven-active/30 text-haven-active'
            : 'bg-haven-error/10 border border-haven-error/30 text-haven-error'
        }`}>
          {toast.type === 'success'
            ? <CheckCircleIcon className="h-5 w-5 flex-shrink-0" />
            : <XCircleIcon className="h-5 w-5 flex-shrink-0" />
          }
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
          onClick={handleReject}
          disabled={loading}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors disabled:opacity-50"
        >
          Reject Partner
        </button>
      </div>
    </div>
  )
}
