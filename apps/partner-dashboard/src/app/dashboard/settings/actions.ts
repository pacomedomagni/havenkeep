'use server';

import { serverApiClient } from '@/lib/auth';
import { isSafeLogoUrl } from '@/lib/utils';

const HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;

export async function updatePartnerProfile(formData: FormData) {
  const companyName = ((formData.get('companyName') as string) ?? '').trim();
  const partnerType = (formData.get('partnerType') as string) ?? '';
  const phone = ((formData.get('phone') as string) ?? '').trim();
  const serviceAreasRaw = (formData.get('serviceAreas') as string) ?? '';
  const brandColor = ((formData.get('brandColor') as string) ?? '').trim();
  const logoUrl = ((formData.get('logoUrl') as string) ?? '').trim();

  if (!companyName) {
    return { error: 'Company name is required.' };
  }
  if (brandColor && !HEX_COLOR.test(brandColor)) {
    return { error: 'Brand color must be a 6-character hex code (e.g. #6C63FF).' };
  }
  if (logoUrl && !isSafeLogoUrl(logoUrl)) {
    return { error: 'Logo URL must be an https URL.' };
  }

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
      },
    });

    return { success: true };
  } catch (error) {
    return { error: error instanceof Error ? error.message : 'Failed to update profile' };
  }
}
