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

          {/* Platform Settings */}
          <div className="card">
            <h3 className="text-lg font-semibold text-white mb-4">Platform Settings</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-white">Email Notifications</p>
                  <p className="text-sm text-haven-text-secondary">Receive alerts about platform activity</p>
                </div>
                <input
                  type="checkbox"
                  defaultChecked
                  className="h-4 w-4 text-haven-primary focus:ring-haven-primary border-haven-border rounded bg-haven-elevated"
                />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-white">Daily Reports</p>
                  <p className="text-sm text-haven-text-secondary">Send daily summary emails</p>
                </div>
                <input
                  type="checkbox"
                  defaultChecked
                  className="h-4 w-4 text-haven-primary focus:ring-haven-primary border-haven-border rounded bg-haven-elevated"
                />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-white">Critical Alerts</p>
                  <p className="text-sm text-haven-text-secondary">Notify on system issues</p>
                </div>
                <input
                  type="checkbox"
                  defaultChecked
                  className="h-4 w-4 text-haven-primary focus:ring-haven-primary border-haven-border rounded bg-haven-elevated"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}
