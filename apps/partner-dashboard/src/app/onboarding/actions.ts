'use server';

import { redirect } from 'next/navigation';
import { serverApiClient } from '@/lib/auth';
import type { PartnerType } from '@/lib/types';

export async function createPartnerProfile(formData: FormData) {
  const companyName = formData.get('companyName') as string;
  const partnerType = formData.get('partnerType') as PartnerType;
  const phone = formData.get('phone') as string;
  const serviceAreasRaw = formData.get('serviceAreas') as string;

  const serviceAreas = serviceAreasRaw
    .split(',')
    .map((area) => area.trim())
    .filter(Boolean);

  try {
    await serverApiClient('/api/v1/partners/register', {
      method: 'POST',
      body: {
        companyName,
        partnerType,
        phone: phone || undefined,
        serviceAreas,
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Something went wrong';

    if (message.includes('already')) {
      return { error: 'A partner profile already exists for this account.' };
    }

    return { error: message };
  }

  redirect('/dashboard');
}
