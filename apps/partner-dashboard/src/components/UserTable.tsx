'use client'

import { useState, useEffect } from 'react'
import { TrashIcon, NoSymbolIcon, CheckCircleIcon, XCircleIcon } from '@heroicons/react/24/outline'
import { apiClient, ApiError } from '@/lib/api'

// Audit Ch10-W040: hard delete is gated on a typed confirmation. A native
// `confirm()` accepts a single button click — that's not a high enough bar
// for an irreversible row deletion that cascades to homes / items / receipts.
const DELETE_CONFIRM_TOKEN = 'DELETE'

interface User {
  id: string
  email: string
  full_name: string
  plan: string
  created_at: string
  total_items: number
  total_value: number
  last_activity: string | null
}

interface UserTableProps {
  users: User[]
}

interface Toast {
  message: string
  type: 'success' | 'error'
}

export default function UserTable({ users: initialUsers }: UserTableProps) {
  const [users, setUsers] = useState(initialUsers)
  const [searchQuery, setSearchQuery] = useState('')
  const [filterPlan, setFilterPlan] = useState<string>('all')
  const [toast, setToast] = useState<Toast | null>(null)
  const [deleteCandidate, setDeleteCandidate] = useState<User | null>(null)
  const [deleteInput, setDeleteInput] = useState('')
  const [deleteLoading, setDeleteLoading] = useState(false)

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 4000)
      return () => clearTimeout(timer)
    }
  }, [toast])

  const filteredUsers = users.filter(user => {
    const matchesSearch =
      user.email.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.full_name.toLowerCase().includes(searchQuery.toLowerCase())

    const matchesPlan = filterPlan === 'all' || user.plan === filterPlan

    return matchesSearch && matchesPlan
  })

  const handleSuspendUser = async (userId: string) => {
    if (!confirm('Are you sure you want to suspend this user?')) return

    try {
      await apiClient(`/api/v1/admin/users/${encodeURIComponent(userId)}/suspend`, {
        method: 'PUT',
      })

      setUsers(users.map(u => u.id === userId ? { ...u, plan: 'suspended' } : u))
      setToast({ message: 'User suspended successfully', type: 'success' })
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : 'Failed to suspend user. Please try again.'
      setToast({ message, type: 'error' })
    }
  }

  const submitDelete = async () => {
    if (!deleteCandidate) return
    if (deleteInput !== DELETE_CONFIRM_TOKEN) return
    setDeleteLoading(true)
    try {
      await apiClient(`/api/v1/admin/users/${encodeURIComponent(deleteCandidate.id)}`, {
        method: 'DELETE',
      })

      setUsers(users.filter(u => u.id !== deleteCandidate.id))
      setToast({ message: 'User deleted successfully', type: 'success' })
      setDeleteCandidate(null)
      setDeleteInput('')
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : 'Failed to delete user. Please try again.'
      setToast({ message, type: 'error' })
    } finally {
      setDeleteLoading(false)
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

      {/* Filters */}
      <div className="card mb-6">
        <div className="flex flex-col md:flex-row gap-4">
          <div className="flex-1">
            <input
              type="text"
              placeholder="Search by name or email..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="input-field"
            />
          </div>
          <select
            value={filterPlan}
            onChange={(e) => setFilterPlan(e.target.value)}
            className="input-field w-auto"
          >
            <option value="all">All Plans</option>
            <option value="free">Free</option>
            <option value="premium">Premium</option>
          </select>
        </div>
        <p className="text-sm text-haven-text-tertiary mt-2">
          Showing {filteredUsers.length} of {users.length} users
        </p>
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-haven-border">
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  User
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Plan
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Items
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Value
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Joined
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Last Activity
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium text-haven-text-tertiary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-haven-border">
              {filteredUsers.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-8 text-center text-haven-text-tertiary">
                    No users found
                  </td>
                </tr>
              ) : (
                filteredUsers.map((user) => (
                  <tr key={user.id} className="hover:bg-haven-elevated/50 transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-white">{user.full_name}</div>
                        <div className="text-sm text-haven-text-secondary">{user.email}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                        user.plan === 'premium'
                          ? 'bg-haven-primary/20 text-haven-primary'
                          : 'bg-haven-elevated text-haven-text-secondary'
                      }`}>
                        {user.plan}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-white">
                      {user.total_items}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-white">
                      ${Number(user.total_value).toLocaleString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {new Date(user.created_at).toLocaleDateString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-haven-text-secondary">
                      {user.last_activity
                        ? new Date(user.last_activity).toLocaleDateString()
                        : 'Never'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <button
                        onClick={() => handleSuspendUser(user.id)}
                        className="text-haven-warning hover:text-haven-warning/80 mr-3"
                        title="Suspend user"
                      >
                        <NoSymbolIcon className="h-5 w-5" />
                      </button>
                      <button
                        onClick={() => {
                          setDeleteCandidate(user)
                          setDeleteInput('')
                        }}
                        className="text-haven-error hover:text-haven-error/80"
                        title="Delete user"
                        aria-label={`Delete ${user.email}`}
                      >
                        <TrashIcon className="h-5 w-5" aria-hidden="true" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {deleteCandidate && (
        <div
          className="fixed inset-0 bg-black/60 flex items-center justify-center z-50"
          role="dialog"
          aria-modal="true"
          aria-labelledby="delete-user-title"
        >
          <div className="bg-haven-surface border border-haven-border rounded-xl p-6 max-w-md w-full mx-4">
            <h3 id="delete-user-title" className="text-lg font-semibold text-white mb-2">
              Delete user account
            </h3>
            <p className="text-sm text-haven-text-secondary mb-2">
              This permanently deletes <strong>{deleteCandidate.email}</strong> and every home, item,
              receipt, and document they own. This action cannot be undone.
            </p>
            <p className="text-sm text-haven-text-secondary mb-3">
              Type <code className="text-white">{DELETE_CONFIRM_TOKEN}</code> to confirm.
            </p>
            <input
              type="text"
              value={deleteInput}
              onChange={(e) => setDeleteInput(e.target.value)}
              className="input-field w-full font-mono"
              placeholder={DELETE_CONFIRM_TOKEN}
              aria-label={`Type ${DELETE_CONFIRM_TOKEN} to confirm deletion`}
              autoFocus
            />
            <div className="flex justify-end gap-3 mt-4">
              <button
                onClick={() => {
                  setDeleteCandidate(null)
                  setDeleteInput('')
                }}
                className="btn-secondary"
                disabled={deleteLoading}
              >
                Cancel
              </button>
              <button
                onClick={submitDelete}
                disabled={deleteLoading || deleteInput !== DELETE_CONFIRM_TOKEN}
                className="px-4 py-2 text-sm font-medium rounded-lg bg-red-500/30 text-red-300 hover:bg-red-500/40 transition-colors disabled:opacity-50"
              >
                {deleteLoading ? 'Deleting…' : 'Delete account'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
