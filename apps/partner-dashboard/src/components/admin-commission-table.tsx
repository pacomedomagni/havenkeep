'use client'

import { useState, useEffect } from 'react'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/react/24/outline'
import { apiClient } from '@/lib/api'

interface AdminCommissionTableProps {
  commissions: any[]
}

interface Toast {
  message: string
  type: 'success' | 'error'
}

type StatusFilter = 'all' | 'pending' | 'approved' | 'paid' | 'cancelled'

export default function AdminCommissionTable({ commissions: initialCommissions }: AdminCommissionTableProps) {
  const [commissions, setCommissions] = useState(initialCommissions)
  const [activeTab, setActiveTab] = useState<StatusFilter>('all')
  const [toast, setToast] = useState<Toast | null>(null)
  const [loadingAction, setLoadingAction] = useState<string | null>(null)

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 4000)
      return () => clearTimeout(timer)
    }
  }, [toast])

  const filteredCommissions = commissions.filter(commission => {
    if (activeTab === 'all') return true
    return commission.status === activeTab
  })

  const handleApprove = async (commissionId: string) => {
    setLoadingAction(commissionId)
    try {
      await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/approve`, {
        method: 'PUT',
      })
      setCommissions(commissions.map(c =>
        c.id === commissionId ? { ...c, status: 'approved' } : c
      ))
      setToast({ message: 'Commission approved successfully', type: 'success' })
    } catch {
      setToast({ message: 'Failed to approve commission. Please try again.', type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const handlePay = async (commissionId: string) => {
    setLoadingAction(commissionId)
    try {
      await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/pay`, {
        method: 'PUT',
      })
      setCommissions(commissions.map(c =>
        c.id === commissionId ? { ...c, status: 'paid' } : c
      ))
      setToast({ message: 'Commission marked as paid', type: 'success' })
    } catch {
      setToast({ message: 'Failed to mark commission as paid. Please try again.', type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const handleCancel = async (commissionId: string) => {
    if (!confirm('Are you sure you want to cancel this commission?')) return

    setLoadingAction(commissionId)
    try {
      await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/cancel`, {
        method: 'PUT',
      })
      setCommissions(commissions.map(c =>
        c.id === commissionId ? { ...c, status: 'cancelled' } : c
      ))
      setToast({ message: 'Commission cancelled', type: 'success' })
    } catch {
      setToast({ message: 'Failed to cancel commission. Please try again.', type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const tabs: { key: StatusFilter; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'pending', label: 'Pending' },
    { key: 'approved', label: 'Approved' },
    { key: 'paid', label: 'Paid' },
    { key: 'cancelled', label: 'Cancelled' },
  ]

  const getStatusBadgeClasses = (status: string) => {
    switch (status) {
      case 'pending':
        return 'bg-yellow-500/20 text-yellow-400'
      case 'approved':
        return 'bg-blue-500/20 text-blue-400'
      case 'paid':
        return 'bg-green-500/20 text-green-400'
      case 'cancelled':
        return 'bg-red-500/20 text-red-400'
      default:
        return 'bg-haven-elevated text-haven-text-secondary'
    }
  }

  return (
    <div>
      {/* Toast notification */}
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

      {/* Filter Tabs */}
      <div className="card mb-6">
        <div className="flex rounded-lg overflow-hidden border border-haven-border w-fit">
          {tabs.map(tab => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`px-4 py-2 text-sm font-medium transition-colors ${
                activeTab === tab.key
                  ? 'bg-haven-primary text-white'
                  : 'bg-haven-elevated text-haven-text-secondary hover:text-white'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
        <p className="text-sm text-haven-text-tertiary mt-2">
          Showing {filteredCommissions.length} of {commissions.length} commissions
        </p>
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-haven-border">
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Partner
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Amount
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Date
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-haven-border">
              {filteredCommissions.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-6 py-8 text-center text-haven-text-tertiary">
                    No commissions found
                  </td>
                </tr>
              ) : (
                filteredCommissions.map((commission) => (
                  <tr key={commission.id} className="hover:bg-haven-elevated/50 transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-white">
                        {commission.partner_name || commission.company_name || '-'}
                      </div>
                      {commission.partner_email && (
                        <div className="text-sm text-haven-text-secondary">
                          {commission.partner_email}
                        </div>
                      )}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-white">
                      ${Number(commission.amount || 0).toLocaleString(undefined, {
                        minimumFractionDigits: 2,
                        maximumFractionDigits: 2,
                      })}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${getStatusBadgeClasses(commission.status)}`}>
                        {commission.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {commission.created_at
                        ? new Date(commission.created_at).toLocaleDateString()
                        : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <div className="flex items-center justify-end gap-2">
                        {commission.status === 'pending' && (
                          <>
                            <button
                              onClick={() => handleApprove(commission.id)}
                              disabled={loadingAction === commission.id}
                              className="px-3 py-1 text-xs font-medium rounded-md bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-colors disabled:opacity-50"
                            >
                              Approve
                            </button>
                            <button
                              onClick={() => handleCancel(commission.id)}
                              disabled={loadingAction === commission.id}
                              className="px-3 py-1 text-xs font-medium rounded-md bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors disabled:opacity-50"
                            >
                              Cancel
                            </button>
                          </>
                        )}
                        {commission.status === 'approved' && (
                          <button
                            onClick={() => handlePay(commission.id)}
                            disabled={loadingAction === commission.id}
                            className="px-3 py-1 text-xs font-medium rounded-md bg-green-500/20 text-green-400 hover:bg-green-500/30 transition-colors disabled:opacity-50"
                          >
                            Mark Paid
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
