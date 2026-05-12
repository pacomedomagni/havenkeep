'use client'

import { useState } from 'react'
import Link from 'next/link'

interface Partner {
  id: string
  company_name?: string | null
  email?: string | null
  partner_type?: string | null
  count_gifts?: number | null
  count_activated_gifts?: number | null
  created_at?: string | null
}

interface PartnerTableProps {
  partners: Partner[]
}

export default function PartnerTable({ partners }: PartnerTableProps) {
  const [searchQuery, setSearchQuery] = useState('')

  const filteredPartners = partners.filter((partner) => {
    const q = searchQuery.toLowerCase()
    return (
      (partner.company_name || '').toLowerCase().includes(q) ||
      (partner.email || '').toLowerCase().includes(q)
    )
  })

  return (
    <div>
      <div className="card mb-6">
        <input
          type="text"
          placeholder="Search by company name or email..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="input-field"
          aria-label="Search partners"
        />
        <p className="text-sm text-haven-text-tertiary mt-2">
          Showing {filteredPartners.length} of {partners.length} partners
        </p>
      </div>

      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-haven-border">
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Company</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Type</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Email</th>
                <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Gifts</th>
                <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Activated</th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">Joined</th>
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
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary text-right">
                      {partner.count_gifts ?? 0}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary text-right">
                      {partner.count_activated_gifts ?? 0}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {partner.created_at ? new Date(partner.created_at).toLocaleDateString() : '-'}
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
