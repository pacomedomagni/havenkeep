import Sidebar from '@/components/sidebar';
import { requireRole } from '@/lib/auth';

// S2-O: server-side role gate so an authenticated non-partner user can't
// briefly render any /dashboard subtree before a client-side check kicks
// in. Mirrors the /admin layout (mig Ch10-W044). Partners *and* admins
// see the dashboard — admins use it to support partner accounts.
export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireRole('partner-or-admin');
  return (
    <div className="flex h-screen bg-haven-bg overflow-hidden">
      <Sidebar />
      <main className="flex-1 overflow-y-auto p-8">{children}</main>
    </div>
  );
}
