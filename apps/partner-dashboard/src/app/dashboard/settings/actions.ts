'use server';

import { serverApiClient } from '@/lib/auth';

export async function updatePartnerProfile(formData: FormData) {
  const companyName = formData.get('companyName') as string;
  const partnerType = formData.get('partnerType') as string;
  const phone = formData.get('phone') as string;
  const serviceAreasRaw = formData.get('serviceAreas') as string;
  const brandColor = formData.get('brandColor') as string;
  const logoUrl = formData.get('logoUrl') as string;
  const licenseNumber = formData.get('licenseNumber') as string;

  const serviceAreas = serviceAreasRaw
    .split(',')
    .map((area) => area.trim())
    .filter(Boolean);

  try {
    await serverApiClient('/api/v1/partners/me', {
      method: 'PUT',
      body: {
        company_name: companyName,
        partner_type: partnerType,
        phone: phone || undefined,
        service_areas: serviceAreas,
        brand_color: brandColor || undefined,
        logo_url: logoUrl || undefined,
        license_number: licenseNumber || null,
      },
    });

    return { success: true };
  } catch (error) {
    return { error: error instanceof Error ? error.message : 'Failed to update profile' };
  }
}
