'use server';

import { serverApiClient } from '@/lib/auth';

export async function updatePartnerProfile(formData: FormData) {
  const companyName = formData.get('companyName') as string;
  const partnerType = formData.get('partnerType') as string;
  const phone = formData.get('phone') as string;
  const serviceAreasRaw = formData.get('serviceAreas') as string;

  const serviceAreas = serviceAreasRaw
    .split(',')
    .map((area) => area.trim())
    .filter(Boolean);

  try {
    await serverApiClient('/api/v1/partners/me', {
      method: 'PUT',
      body: {
        companyName,
        partnerType,
        phone: phone || undefined,
        serviceAreas,
      },
    });

    return { success: true };
  } catch (error) {
    return { error: error instanceof Error ? error.message : 'Failed to update profile' };
  }
}
