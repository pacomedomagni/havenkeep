'use client'

import { useState } from 'react'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/react/24/outline'

interface AuditLogTableProps {
  initialLogs: any[]
}

type SeverityFilter = 'all' | 'info' | 'warning' | 'error' | 'critical'

export default function AuditLogTable({ initialLogs }: AuditLogTableProps) {
  const [logs] = useState(initialLogs)
  const [severityFilter, setSeverityFilter] = useState<SeverityFilter>('all')
  const [actionSearch, setActionSearch] = useState('')
  const [expandedRow, setExpandedRow] = useState<string | null>(null)

  const filteredLogs = logs.filter(log => {
    const matchesSeverity =
      severityFilter === 'all' || log.severity === severityFilter

    const matchesAction =
      actionSearch === '' ||
      (log.action || '').toLowerCase().includes(actionSearch.toLowerCase())

    return matchesSeverity && matchesAction
  })

  const getSeverityBadgeClasses = (severity: string) => {
    switch (severity) {
      case 'info':
        return 'bg-blue-500/20 text-blue-400'
      case 'warning':
        return 'bg-yellow-500/20 text-yellow-400'
      case 'error':
        return 'bg-red-500/20 text-red-400'
      case 'critical':
        return 'bg-red-600/30 text-red-300 font-bold'
      default:
        return 'bg-haven-elevated text-haven-text-secondary'
    }
  }

  const formatTimestamp = (timestamp: string) => {
    if (!timestamp) return '-'

    const date = new Date(timestamp)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMinutes = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMs / 3600000)
    const diffDays = Math.floor(diffMs / 86400000)

    if (diffMinutes < 1) return 'Just now'
    if (diffMinutes < 60) return `${diffMinutes}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    if (diffDays < 7) return `${diffDays}d ago`

    return date.toLocaleString()
  }

  const toggleRow = (logId: string) => {
    setExpandedRow(expandedRow === logId ? null : logId)
  }

  return (
    <div>
      {/* Filters */}
      <div className="card mb-6">
        <div className="flex flex-col md:flex-row gap-4">
          <div className="flex-1">
            <input
              type="text"
              placeholder="Search by action type..."
              value={actionSearch}
              onChange={(e) => setActionSearch(e.target.value)}
              className="input-field"
            />
          </div>
          <select
            value={severityFilter}
            onChange={(e) => setSeverityFilter(e.target.value as SeverityFilter)}
            className="input-field w-auto"
          >
            <option value="all">All Severities</option>
            <option value="info">Info</option>
            <option value="warning">Warning</option>
            <option value="error">Error</option>
            <option value="critical">Critical</option>
          </select>
        </div>
        <p className="text-sm text-haven-text-tertiary mt-2">
          Showing {filteredLogs.length} of {logs.length} events
        </p>
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-haven-border">
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider w-8">
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Timestamp
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  User
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Action
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Severity
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Resource
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Description
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-haven-border">
              {filteredLogs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-8 text-center text-haven-text-tertiary">
                    No audit logs found
                  </td>
                </tr>
              ) : (
                filteredLogs.map((log) => (
                  <>
                    <tr
                      key={log.id}
                      className="hover:bg-haven-elevated/50 transition-colors cursor-pointer"
                      onClick={() => toggleRow(log.id)}
                    >
                      <td className="px-6 py-4">
                        {expandedRow === log.id
                          ? <ChevronUpIcon className="h-4 w-4 text-haven-text-tertiary" />
                          : <ChevronDownIcon className="h-4 w-4 text-haven-text-tertiary" />
                        }
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                        <span title={log.created_at ? new Date(log.created_at).toLocaleString() : ''}>
                          {formatTimestamp(log.created_at)}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="text-sm text-white">{log.user_email || log.user_id || '-'}</div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-white font-mono">
                        {log.action || '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${getSeverityBadgeClasses(log.severity)}`}>
                          {log.severity || 'info'}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                        {log.resource_type || '-'}
                        {log.resource_id && (
                          <span className="text-haven-text-tertiary ml-1 font-mono text-xs">
                            ({log.resource_id.slice(0, 8)}...)
                          </span>
                        )}
                      </td>
                      <td className="px-6 py-4 text-sm text-haven-text-secondary max-w-xs truncate">
                        {log.description || '-'}
                      </td>
                    </tr>
                    {expandedRow === log.id && (
                      <tr key={`${log.id}-expanded`} className="bg-haven-elevated/30">
                        <td colSpan={7} className="px-6 py-4">
                          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                            <div>
                              <label className="block text-xs font-medium text-haven-text-tertiary mb-1">
                                Full Timestamp
                              </label>
                              <p className="text-white">
                                {log.created_at ? new Date(log.created_at).toLocaleString() : '-'}
                              </p>
                            </div>
                            <div>
                              <label className="block text-xs font-medium text-haven-text-tertiary mb-1">
                                IP Address
                              </label>
                              <p className="text-white font-mono">
                                {log.ip_address || '-'}
                              </p>
                            </div>
                            <div>
                              <label className="block text-xs font-medium text-haven-text-tertiary mb-1">
                                User Agent
                              </label>
                              <p className="text-white text-xs break-all">
                                {log.user_agent || '-'}
                              </p>
                            </div>
                            {log.metadata && Object.keys(log.metadata).length > 0 && (
                              <div className="md:col-span-3">
                                <label className="block text-xs font-medium text-haven-text-tertiary mb-1">
                                  Metadata
                                </label>
                                <pre className="text-white text-xs bg-haven-bg rounded-lg p-3 overflow-x-auto">
                                  {JSON.stringify(log.metadata, null, 2)}
                                </pre>
                              </div>
                            )}
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
