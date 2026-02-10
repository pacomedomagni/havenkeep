'use server';

import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import type { PartnerType } from '@/lib/types';

export async function createPartnerProfile(formData: FormData) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: 'Not authenticated' };
  }

  const companyName = formData.get('companyName') as string;
  const partnerType = formData.get('partnerType') as PartnerType;
  const licenseNumber = formData.get('licenseNumber') as string;
  const serviceAreasRaw = formData.get('serviceAreas') as string;

  const serviceAreas = serviceAreasRaw
    .split(',')
    .map((area) => area.trim())
    .filter(Boolean);

  // Generate a unique referral code
  const referralCode = `HK-${companyName
    .substring(0, 3)
    .toUpperCase()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

  const { error } = await supabase.from('referral_partners').insert({
    user_id: user.id,
    company_name: companyName,
    partner_type: partnerType,
    license_number: licenseNumber || null,
    service_areas: serviceAreas,
    is_approved: false,
    referral_code: referralCode,
  });

  if (error) {
    return { error: error.message };
  }

  redirect('/dashboard');
}
