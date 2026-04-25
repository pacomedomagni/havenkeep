'use server';

import { redirect } from 'next/navigation';
import { ApiError, serverApiClient } from '@/lib/auth';
import type { PartnerType } from '@/lib/types';

export async function createPartnerProfile(formData: FormData) {
  const companyName = (formData.get('companyName') ?? '').toString().trim();
  const partnerType = formData.get('partnerType') as PartnerType;
  const licenseNumber = (formData.get('licenseNumber') ?? '').toString().trim();
  const serviceAreasRaw = (formData.get('serviceAreas') ?? '').toString();

  if (!companyName) {
    return { error: 'Company name is required.' };
  }

  const serviceAreas = serviceAreasRaw
    .split(',')
    .map((area) => area.trim())
    .filter(Boolean);

  if (serviceAreas.length === 0) {
    return { error: 'At least one service area is required.' };
  }

  try {
    await serverApiClient('/api/v1/partners/register', {
      method: 'POST',
      body: {
        company_name: companyName,
        partner_type: partnerType,
        ...(licenseNumber ? { license_number: licenseNumber } : {}),
        service_areas: serviceAreas,
      },
    });
  } catch (error) {
    if (error instanceof ApiError && error.status === 409) {
      return { error: 'A partner profile already exists for this account.' };
    }
    return {
      error:
        error instanceof Error
          ? error.message
          : 'We could not save your partner profile. Please try again.',
    };
  }

  redirect('/dashboard');
}
