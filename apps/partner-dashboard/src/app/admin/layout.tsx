import AdminSidebar from '@/components/admin-sidebar'
import { requireRole } from '@/lib/auth'

/**
 * Server-side role gate for the entire `/admin` segment (audit Ch10-W044).
 * A page-level `requireAdmin` is still recommended for defence-in-depth, but
 * the layout enforces the role even when a leaf page forgets to.
 */
export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode
}) {
  await requireRole('admin')
  return (
    <div className="flex h-screen bg-haven-bg overflow-hidden">
      <AdminSidebar />
      <main className="flex-1 overflow-y-auto p-8">{children}</main>
    </div>
  )
}
