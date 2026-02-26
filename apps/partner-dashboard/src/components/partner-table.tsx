'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/react/24/outline'
import { apiClient } from '@/lib/api'

interface PartnerTableProps {
  partners: any[]
}

interface Toast {
  message: string
  type: 'success' | 'error'
}

type FilterTab = 'all' | 'pending' | 'active'

export default function PartnerTable({ partners: initialPartners }: PartnerTableProps) {
  const [partners, setPartners] = useState(initialPartners)
  const [searchQuery, setSearchQuery] = useState('')
  const [activeTab, setActiveTab] = useState<FilterTab>('all')
  const [toast, setToast] = useState<Toast | null>(null)
  const [loadingAction, setLoadingAction] = useState<string | null>(null)

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 4000)
      return () => clearTimeout(timer)
    }
  }, [toast])

  const filteredPartners = partners.filter(partner => {
    const matchesSearch =
      (partner.company_name || '').toLowerCase().includes(searchQuery.toLowerCase()) ||
      (partner.email || '').toLowerCase().includes(searchQuery.toLowerCase())

    const matchesTab =
      activeTab === 'all' ||
      (activeTab === 'active' ? partner.is_active : !partner.is_active)

    return matchesSearch && matchesTab
  })

  const handleApprove = async (partnerId: string) => {
    if (!confirm('Are you sure you want to approve this partner?')) return

    setLoadingAction(partnerId)
    try {
      await apiClient(`/api/v1/admin/partners/${partnerId}/approve`, {
        method: 'PUT',
      })

      setPartners(partners.map(p =>
        p.id === partnerId ? { ...p, is_active: true } : p
      ))
      setToast({ message: 'Partner approved successfully', type: 'success' })
    } catch {
      setToast({ message: 'Failed to approve partner. Please try again.', type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const handleReject = async (partnerId: string) => {
    if (!confirm('Are you sure you want to reject this partner?')) return

    setLoadingAction(partnerId)
    try {
      await apiClient(`/api/v1/admin/partners/${partnerId}/reject`, {
        method: 'PUT',
      })

      setPartners(partners.map(p =>
        p.id === partnerId ? { ...p, is_active: false } : p
      ))
      setToast({ message: 'Partner rejected successfully', type: 'success' })
    } catch {
      setToast({ message: 'Failed to reject partner. Please try again.', type: 'error' })
    } finally {
      setLoadingAction(null)
    }
  }

  const tabs: { key: FilterTab; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'pending', label: 'Pending' },
    { key: 'active', label: 'Active' },
  ]

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
            />
          </div>
          <div className="flex rounded-lg overflow-hidden border border-haven-border">
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
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Company
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Type
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Email
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Registered
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Actions
                </th>
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
                filteredPartners.map((partner) => (
                  <tr key={partner.id} className="hover:bg-haven-elevated/50 transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <Link
                        href={`/admin/partners/${partner.id}`}
                        className="text-sm font-medium text-haven-primary hover:text-haven-primary/80 transition-colors"
                      >
                        {partner.company_name}
                      </Link>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {partner.partner_type || '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {partner.email}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                        partner.is_active
                          ? 'bg-green-500/20 text-green-400'
                          : 'bg-yellow-500/20 text-yellow-400'
                      }`}>
                        {partner.is_active ? 'active' : 'pending'}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {partner.created_at
                        ? new Date(partner.created_at).toLocaleDateString()
                        : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      {!partner.is_active && (
                        <div className="flex items-center justify-end gap-2">
                          <button
                            onClick={() => handleApprove(partner.id)}
                            disabled={loadingAction === partner.id}
                            className="px-3 py-1 text-xs font-medium rounded-md bg-green-500/20 text-green-400 hover:bg-green-500/30 transition-colors disabled:opacity-50"
                          >
                            Approve
                          </button>
                          <button
                            onClick={() => handleReject(partner.id)}
                            disabled={loadingAction === partner.id}
                            className="px-3 py-1 text-xs font-medium rounded-md bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors disabled:opacity-50"
                          >
                            Reject
                          </button>
                        </div>
                      )}
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
