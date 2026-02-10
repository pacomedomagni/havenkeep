import Header from '@/components/Header'
import UserTable from '@/components/UserTable'
import { createServerSupabaseClient } from '@/lib/supabase-server'

async function getUsers() {
  const supabase = await createServerSupabaseClient()
  
  const { data: users } = await supabase
    .from('admin_user_activity')
    .select('*')
    .order('created_at', { ascending: false })

  return users || []
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
