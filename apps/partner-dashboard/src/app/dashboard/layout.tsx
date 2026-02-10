import Sidebar from '@/components/sidebar';

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-haven-bg">
      <Sidebar />
      <main className="ml-64 p-8">{children}</main>
    </div>
  );
}
