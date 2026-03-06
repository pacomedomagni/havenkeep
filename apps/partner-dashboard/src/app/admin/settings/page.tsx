import Header from '@/components/Header'
import { requireAdmin } from '@/lib/auth'

export default async function SettingsPage() {
  const user = await requireAdmin()

  return (
    <>
      <Header
        title="Settings"
        subtitle="Manage your admin account"
      />

      <div className="p-8">
        <div className="max-w-2xl">
          {/* Account Info */}
          <div className="card mb-6">
            <h3 className="text-lg font-semibold text-white mb-4">Account Information</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                  Email
                </label>
                <p className="text-white">{user.email}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-haven-text-tertiary mb-1">
                  User ID
                </label>
                <p className="text-haven-text-secondary text-sm font-mono">{user.id}</p>
              </div>
            </div>
          </div>

        </div>
      </div>
    </>
  )
}
