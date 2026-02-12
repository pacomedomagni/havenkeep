'use client'

import { useState } from 'react'
import { TrashIcon, NoSymbolIcon } from '@heroicons/react/24/outline'
import { apiClient } from '@/lib/api'

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

export default function UserTable({ users: initialUsers }: UserTableProps) {
  const [users, setUsers] = useState(initialUsers)
  const [searchQuery, setSearchQuery] = useState('')
  const [filterPlan, setFilterPlan] = useState<string>('all')

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
      await apiClient(`/api/v1/admin/users/${userId}/suspend`, {
        method: 'PUT',
      })

      alert('User suspended successfully')
    } catch {
      alert('Error suspending user')
    }
  }

  const handleDeleteUser = async (userId: string) => {
    if (!confirm('Are you sure you want to delete this user? This action cannot be undone.')) return

    try {
      await apiClient(`/api/v1/admin/users/${userId}`, {
        method: 'DELETE',
      })

      setUsers(users.filter(u => u.id !== userId))
      alert('User deleted successfully')
    } catch {
      alert('Error deleting user')
    }
  }

  return (
    <div>
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
                        onClick={() => handleDeleteUser(user.id)}
                        className="text-haven-error hover:text-haven-error/80"
                        title="Delete user"
                      >
                        <TrashIcon className="h-5 w-5" />
                      </button>
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
