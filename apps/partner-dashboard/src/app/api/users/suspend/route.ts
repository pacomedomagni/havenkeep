import { createServerSupabaseClient } from '@/lib/supabase-server'
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  try {
    const supabase = await createServerSupabaseClient()
    const { userId } = await request.json()

    if (!userId) {
      return NextResponse.json({ error: 'User ID required' }, { status: 400 })
    }

    // Update user to set a suspended flag (we'll add this to schema)
    // For now, we can set plan to a special value or add custom metadata
    const { error } = await supabase
      .from('users')
      .update({ plan: 'free' }) // Downgrade to free as suspension
      .eq('id', userId)

    if (error) throw error

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('Error suspending user:', error)
    return NextResponse.json(
      { error: 'Failed to suspend user' },
      { status: 500 }
    )
  }
}
