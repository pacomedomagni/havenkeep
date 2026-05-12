'use server';

import { redirect } from 'next/navigation';
import { ApiError, serverApiClient } from '@/lib/auth';
import type { PartnerType } from '@/lib/types';

const VALID_PARTNER_TYPES: readonly PartnerType[] = [
  'realtor',
  'builder',
  'contractor',
  'property_manager',
  'other',
];

export async function recoverPartnerProfile(formData: FormData) {
  const companyName = (formData.get('companyName') ?? '').toString().trim();
  const partnerTypeRaw = (formData.get('partnerType') ?? 'realtor').toString();
  const partnerType: PartnerType = VALID_PARTNER_TYPES.includes(partnerTypeRaw as PartnerType)
    ? (partnerTypeRaw as PartnerType)
    : 'realtor';

  if (!companyName) {
    return { error: 'Company or business name is required.' };
  }

  try {
    await serverApiClient('/api/v1/partners/register', {
      method: 'POST',
      body: { company_name: companyName, partner_type: partnerType },
    });
  } catch (error) {
    if (error instanceof ApiError && error.status === 409) {
      // The row already exists — middleware will pick that up on the
      // next request and route them to /dashboard.
      redirect('/dashboard');
    }
    return {
      error: error instanceof Error ? error.message : 'We could not save your profile. Try again.',
    };
  }

  redirect('/dashboard');
}
