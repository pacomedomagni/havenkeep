'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  HomeIcon,
  GiftIcon,
  UserGroupIcon,
  ChartBarIcon,
  BanknotesIcon,
  Cog6ToothIcon,
  ArrowRightOnRectangleIcon,
} from '@heroicons/react/24/outline'
import { logout } from '@/lib/api'

const navigation = [
  { name: 'Dashboard', href: '/dashboard', icon: HomeIcon },
  { name: 'Closing Gifts', href: '/dashboard/gifts', icon: GiftIcon },
  { name: 'Referrals', href: '/dashboard/referrals', icon: UserGroupIcon },
  { name: 'Analytics', href: '/dashboard/analytics', icon: ChartBarIcon },
  { name: 'Commissions', href: '/dashboard/commissions', icon: BanknotesIcon },
  { name: 'Settings', href: '/dashboard/settings', icon: Cog6ToothIcon },
]

export default function Sidebar() {
  const pathname = usePathname()

  const handleSignOut = async () => {
    try {
      await logout()
    } catch {
      window.location.href = '/login'
    }
  }

  return (
    <div className="flex flex-col w-64 flex-shrink-0 bg-haven-surface border-r border-haven-border">
      {/* Logo */}
      <div className="flex items-center h-16 px-6 border-b border-haven-border flex-shrink-0">
        <svg className="w-8 h-8 mr-2 flex-shrink-0" viewBox="0 0 64 64" fill="none">
          <defs>
            <linearGradient id="sidebar-grad" x1="8" y1="4" x2="56" y2="63" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stopColor="#6366F1" />
              <stop offset="100%" stopColor="#8B5CF6" />
            </linearGradient>
          </defs>
          <path d="M32 4L8 14v18c0 14.4 10.24 27.84 24 31 13.76-3.16 24-16.6 24-31V14L32 4z" fill="url(#sidebar-grad)" />
          <path d="M32 18L19 28v13h8v-8h10v8h8V28L32 18z" fill="white" opacity="0.95" />
          <path d="M27 30l4 4 8-8" stroke="#10B981" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
        </svg>
        <span className="text-xl font-bold text-white">HavenKeep</span>
        <span className="ml-2 text-xs font-medium text-haven-text-tertiary bg-haven-elevated px-2 py-0.5 rounded">Partner</span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 space-y-0.5 overflow-y-auto">
        {navigation.map((item) => {
          const isActive =
            item.href === '/dashboard'
              ? pathname === '/dashboard'
              : pathname.startsWith(item.href)
          return (
            <Link
              key={item.name}
              href={item.href}
              className={`flex items-center px-3 py-2.5 text-sm font-medium rounded-lg transition-colors duration-150 ${
                isActive
                  ? 'bg-haven-primary/15 text-white'
                  : 'text-haven-text-secondary hover:bg-haven-elevated hover:text-white'
              }`}
            >
              <item.icon className={`h-5 w-5 mr-3 flex-shrink-0 ${isActive ? 'text-haven-primary' : ''}`} />
              {item.name}
            </Link>
          )
        })}
      </nav>

      {/* Sign Out */}
      <div className="p-3 border-t border-haven-border flex-shrink-0">
        <button
          onClick={handleSignOut}
          className="flex items-center w-full px-3 py-2.5 text-sm font-medium text-haven-text-secondary hover:bg-haven-elevated hover:text-white rounded-lg transition-colors duration-150"
        >
          <ArrowRightOnRectangleIcon className="h-5 w-5 mr-3 flex-shrink-0" />
          Sign Out
        </button>
      </div>
    </div>
  )
}
