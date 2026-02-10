'use server';

import { createClient } from '@/lib/supabase/server';

export async function updatePartnerProfile(formData: FormData) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: 'Not authenticated' };
  }

  const companyName = formData.get('companyName') as string;
  const partnerType = formData.get('partnerType') as string;
  const licenseNumber = formData.get('licenseNumber') as string;
  const serviceAreasRaw = formData.get('serviceAreas') as string;

  const serviceAreas = serviceAreasRaw
    .split(',')
    .map((area) => area.trim())
    .filter(Boolean);

  const { error } = await supabase
    .from('referral_partners')
    .update({
      company_name: companyName,
      partner_type: partnerType,
      license_number: licenseNumber || null,
      service_areas: serviceAreas,
    })
    .eq('user_id', user.id);

  if (error) {
    return { error: error.message };
  }

  return { success: true };
}
