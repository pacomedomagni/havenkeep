import Header from '@/components/Header'
import UserTable from '@/components/UserTable'
import { serverApiClient } from '@/lib/auth'

async function getUsers() {
  try {
    const { users } = await serverApiClient<{ users: any[] }>('/api/v1/admin/users/activity')
    return users || []
  } catch {
    return []
  }
}

export default async function UsersPage() {
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
