'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/react/24/outline'
import { apiClient, ApiError } from '@/lib/api'

type PartnerStatus = 'pending' | 'active' | 'rejected'

interface Partner {
  id: string
  company_name?: string | null
  email?: string | null
  partner_type?: string | null
  status?: PartnerStatus
  is_active?: boolean
  created_at?: string | null
}

interface PartnerTableProps {
  partners: Partner[]
}

interface Toast {
  message: string
  type: 'success' | 'error'
}

type FilterTab = 'all' | 'pending' | 'active' | 'rejected'

/**
 * Treat the new `status` enum as authoritative; fall back to the legacy
 * `is_active` boolean only for rows the migration hasn't touched yet.
 * Audit Ch10-W054.
 */
function normalizeStatus(p: Partner): PartnerStatus {
  if (p.status === 'pending' || p.status === 'active' || p.status === 'rejected') {
    return p.status
  }
  return p.is_active ? 'active' : 'pending'
}

const STATUS_CLASS: Record<PartnerStatus, string> = {
  pending: 'bg-yellow-500/20 text-yellow-400',
  active: 'bg-green-500/20 text-green-400',
  rejected: 'bg-red-500/20 text-red-400',
}

export default function PartnerTable({ partners: initialPartners }: PartnerTableProps) {
  const [partners, setPartners] = useState(initialPartners)
  const [searchQuery, setSearchQuery] = useState('')
  const [activeTab, setActiveTab] = useState<FilterTab>('all')
  const [toast, setToast] = useState<Toast | null>(null)
  const [loadingAction, setLoadingAction] = useState<string | null>(null)
  const [rejectingId, setRejectingId] = useState<string | null>(null)
  const [rejectReason, setRejectReason] = useState('')

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 4000)
      return () => clearTimeout(timer)
    }
  }, [toast])

  const filteredPartners = partners.filter((partner) => {
    const matchesSearch =
      (partner.company_name || '').toLowerCase().includes(searchQuery.toLowerCase()) ||
      (partner.email || '').toLowerCase().includes(searchQuery.toLowerCase())
    const status = normalizeStatus(partner)
    const matchesTab = activeTab === 'all' || status === activeTab
    return matchesSearch && matchesTab
  })

  // Audit Ch10-W055: encode every URL segment built from data we don't trust,
  // so a UUID with `..` or `/` characters can't escape the path.
  const partnerUrl = (id: string, suffix: string) =>
    `/api/v1/admin/partners/${encodeURIComponent(id)}${suffix}`

  const handleApprove = async (partnerId: string) => {
    if (!confirm('Approve this partner?')) return

    setLoadingAction(partnerId)
    try {
      await apiClient(partnerUrl(partnerId, '/approve'), { method: 'PUT' })
      setPartners(
        partners.map((p) =>
          p.id === partnerId ? { ...p, status: 'active' as PartnerStatus, is_active: true } : p,
        ),
      )
      setToast({ message: 'Partner approved successfully', type: 'success' })
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : 'Failed to approve partner. Please try again.'
      setToast({ message, type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const beginReject = (partnerId: string) => {
    setRejectingId(partnerId)
    setRejectReason('')
  }

  const submitReject = async () => {
    const partnerId = rejectingId
    if (!partnerId) return
    setLoadingAction(partnerId)
    try {
      await apiClient(partnerUrl(partnerId, '/reject'), {
        method: 'PUT',
        body: { reason: rejectReason.trim() || undefined },
      })
      setPartners(
        partners.map((p) =>
          p.id === partnerId
            ? { ...p, status: 'rejected' as PartnerStatus, is_active: false }
            : p,
        ),
      )
      setToast({ message: 'Partner rejected. Notification email queued.', type: 'success' })
      setRejectingId(null)
      setRejectReason('')
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : 'Failed to reject partner. Please try again.'
      setToast({ message, type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const tabs: { key: FilterTab; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'pending', label: 'Pending' },
    { key: 'active', label: 'Active' },
    { key: 'rejected', label: 'Rejected' },
  ]

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

      {/* Filters */}
      <div className="card mb-6">
        <div className="flex flex-col md:flex-row gap-4">
          <div className="flex-1">
            <input
              type="text"
              placeholder="Search by company name or email..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="input-field"
              aria-label="Search partners"
            />
          </div>
          <div className="flex rounded-lg overflow-hidden border border-haven-border" role="tablist">
            {tabs.map((tab) => (
              <button
                key={tab.key}
                role="tab"
                aria-selected={activeTab === tab.key}
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
        </div>
        <p className="text-sm text-haven-text-tertiary mt-2">
          Showing {filteredPartners.length} of {partners.length} partners
        </p>
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-haven-border">
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Company</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Type</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Email</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Status</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Registered</th>
                <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-haven-border">
              {filteredPartners.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-6 py-8 text-center text-haven-text-tertiary">
                    No partners found
                  </td>
                </tr>
              ) : (
                filteredPartners.map((partner) => {
                  const status = normalizeStatus(partner)
                  return (
                    <tr key={partner.id} className="hover:bg-haven-elevated/50 transition-colors">
                      <td className="px-6 py-4 whitespace-nowrap">
                        <Link
                          href={`/admin/partners/${encodeURIComponent(partner.id)}`}
                          className="text-sm font-medium text-haven-primary hover:text-haven-primary/80 transition-colors"
                        >
                          {partner.company_name || '-'}
                        </Link>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                        {partner.partner_type || '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                        {partner.email || '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${STATUS_CLASS[status]}`}>
                          {status}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                        {partner.created_at ? new Date(partner.created_at).toLocaleDateString() : '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                        {status === 'pending' && (
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => handleApprove(partner.id)}
                              disabled={loadingAction === partner.id}
                              className="px-3 py-1 text-xs font-medium rounded-md bg-green-500/20 text-green-400 hover:bg-green-500/30 transition-colors disabled:opacity-50"
                            >
                              Approve
                            </button>
                            <button
                              onClick={() => beginReject(partner.id)}
                              disabled={loadingAction === partner.id}
                              className="px-3 py-1 text-xs font-medium rounded-md bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors disabled:opacity-50"
                            >
                              Reject
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  )
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {rejectingId && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50" role="dialog" aria-modal="true">
          <div className="bg-haven-surface border border-haven-border rounded-xl p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-semibold text-white mb-2">Reject partner</h3>
            <p className="text-sm text-haven-text-secondary mb-4">
              The partner will be notified by email. Adding a reason is optional but helps with appeals.
            </p>
            <label htmlFor="reject-reason" className="block text-sm font-medium text-haven-text-secondary mb-1.5">
              Reason (optional)
            </label>
            <textarea
              id="reject-reason"
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value.slice(0, 1024))}
              rows={3}
              maxLength={1024}
              className="input-field w-full"
              placeholder="e.g. License could not be verified"
            />
            <div className="flex justify-end gap-3 mt-4">
              <button
                onClick={() => {
                  setRejectingId(null)
                  setRejectReason('')
                }}
                className="btn-secondary"
                disabled={loadingAction === rejectingId}
              >
                Cancel
              </button>
              <button
                onClick={submitReject}
                className="btn-primary"
                disabled={loadingAction === rejectingId}
              >
                {loadingAction === rejectingId ? 'Rejecting…' : 'Reject partner'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
