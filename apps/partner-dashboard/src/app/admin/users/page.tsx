import Header from '@/components/Header'
import UserTable from '@/components/UserTable'
import { serverApiClient, requireAdmin } from '@/lib/auth'

async function getUsers() {
  try {
    const { data: users } = await serverApiClient<{ data: any[] }>('/api/v1/admin/users/activity')
    return users || []
  } catch {
    return []
  }
}

export default async function UsersPage() {
  await requireAdmin()

  const users = await getUsers()

  return (
    <>
      <Header
        title="User Management"
        subtitle={`${users.length} total users`}
      />

      <div className="p-8">
        <UserTable users={users} />
      </div>
    </>
  )
}
