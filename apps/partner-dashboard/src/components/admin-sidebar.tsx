'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  HomeIcon,
  UsersIcon,
  ChartBarIcon,
  BuildingStorefrontIcon,
  BanknotesIcon,
  ClipboardDocumentListIcon,
  ServerIcon,
  Cog6ToothIcon,
  ArrowRightOnRectangleIcon,
} from '@heroicons/react/24/outline'
import { logout } from '@/lib/api'

const navigation = [
  { name: 'Dashboard', href: '/admin', icon: HomeIcon },
  { name: 'Users', href: '/admin/users', icon: UsersIcon },
  { name: 'Analytics', href: '/admin/analytics', icon: ChartBarIcon },
  { name: 'Partners', href: '/admin/partners', icon: BuildingStorefrontIcon },
  { name: 'Commissions', href: '/admin/commissions', icon: BanknotesIcon },
  { name: 'Audit Logs', href: '/admin/audit', icon: ClipboardDocumentListIcon },
  { name: 'System Health', href: '/admin/health', icon: ServerIcon },
  { name: 'Settings', href: '/admin/settings', icon: Cog6ToothIcon },
]

export default function AdminSidebar() {
  const pathname = usePathname()

  const handleSignOut = async () => {
    try {
      await logout()
    } catch {
      // Force redirect to login even if logout API fails
      window.location.href = '/login'
    }
  }

  return (
    <div className="flex flex-col h-full bg-gray-900 w-64">
      {/* Logo */}
      <div className="flex items-center h-16 px-6 bg-gray-800">
        <svg className="w-8 h-8 mr-2 flex-shrink-0" viewBox="0 0 64 64" fill="none">
          <defs>
            <linearGradient id="admin-sidebar-grad" x1="8" y1="4" x2="56" y2="63" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stopColor="#6366F1"/>
              <stop offset="100%" stopColor="#8B5CF6"/>
            </linearGradient>
          </defs>
          <path d="M32 4L8 14v18c0 14.4 10.24 27.84 24 31 13.76-3.16 24-16.6 24-31V14L32 4z" fill="url(#admin-sidebar-grad)" />
          <path d="M32 18L19 28v13h8v-8h10v8h8V28L32 18z" fill="white" opacity="0.95"/>
          <path d="M27 30l4 4 8-8" stroke="#10B981" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
        </svg>
        <h1 className="text-xl font-bold text-white">HavenKeep</h1>
        <span className="ml-2 text-xs text-gray-400">Admin</span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-4 py-6 space-y-1">
        {navigation.map((item) => {
          const isActive = item.href === '/admin'
            ? pathname === '/admin'
            : pathname.startsWith(item.href)
          return (
            <Link
              key={item.name}
              href={item.href}
              className={`
                flex items-center px-4 py-3 text-sm font-medium rounded-lg transition
                ${
                  isActive
                    ? 'bg-gray-800 text-white'
                    : 'text-gray-300 hover:bg-gray-800 hover:text-white'
                }
              `}
            >
              <item.icon className="h-5 w-5 mr-3" />
              {item.name}
            </Link>
          )
        })}
      </nav>

      {/* Sign Out */}
      <div className="p-4 border-t border-gray-800">
        <button
          onClick={handleSignOut}
          className="flex items-center w-full px-4 py-3 text-sm font-medium text-gray-300 hover:bg-gray-800 hover:text-white rounded-lg transition"
        >
          <ArrowRightOnRectangleIcon className="h-5 w-5 mr-3" />
          Sign Out
        </button>
      </div>
    </div>
  )
}
