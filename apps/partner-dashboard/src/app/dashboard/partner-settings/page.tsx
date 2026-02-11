import { redirect } from 'next/navigation';

export default function PartnerSettingsRedirect() {
  redirect('/dashboard/settings');
}
