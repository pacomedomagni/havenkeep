'use client'

import { BellIcon, UserCircleIcon } from '@heroicons/react/24/outline'

interface HeaderProps {
  title: string
  subtitle?: string
}

export default function Header({ title, subtitle }: HeaderProps) {
  return (
    <div className="bg-haven-surface border-b border-haven-border px-8 py-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">{title}</h1>
          {subtitle && <p className="text-haven-text-secondary mt-1">{subtitle}</p>}
        </div>

        <div className="flex items-center space-x-4">
          <button className="p-2 text-haven-text-tertiary hover:text-white rounded-lg hover:bg-haven-elevated transition">
            <BellIcon className="h-6 w-6" />
          </button>
          <button className="p-2 text-haven-text-tertiary hover:text-white rounded-lg hover:bg-haven-elevated transition">
            <UserCircleIcon className="h-6 w-6" />
          </button>
        </div>
      </div>
    </div>
  )
}
