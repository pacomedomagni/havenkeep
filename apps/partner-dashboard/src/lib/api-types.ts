// S3-H: shared response types for the admin endpoints. Hand-rolled to mirror
// the shape returned by `apps/api/src/routes/admin.ts` — keep these in sync
// when fields are added server-side. Casting happens at the
// `serverApiClient<...>` boundary; pages and components should never need
// `any` after the cast.

import type { AdminCommission, AuditLogEntry } from './types';

export interface PaginationMeta {
  page: number;
  limit: number;
  total: number | null;
  total_pages: number | null;
  next_cursor?: string | null;
  has_more?: boolean;
}

export interface AdminFullStats {
  total_users: number;
  premium_users: number;
  total_items: number;
  items_last_24h: number;
  signups_last_24h: number;
  signups_last_7d: number;
  signups_last_30d: number;
  total_value_protected: number;
  dau: number;
  wau: number;
  mau: number;
}

export interface AdminUserListItem {
  id: string;
  email: string;
  full_name: string;
  plan: string;
  created_at: string;
  total_items?: number;
  total_value?: number | string;
  last_activity?: string | null;
}

export interface AdminUserActivity {
  id: string;
  email: string;
  full_name: string;
  plan: string;
  created_at: string;
  total_items: number;
  total_value: number | string;
  last_activity: string | null;
}

export interface AdminPartnerListItem {
  id: string;
  user_id: string;
  company_name: string | null;
  partner_type: string | null;
  status?: 'pending' | 'active' | 'rejected';
  is_active: boolean;
  has_stripe_account: boolean;
  email: string;
  full_name: string;
  referral_code?: string | null;
  created_at: string;
}

export interface AdminPartnerDetail extends AdminPartnerListItem {
  phone: string | null;
  license_number: string | null;
  service_areas: string[] | string | null;
  brand_color: string | null;
  logo_url: string | null;
  stripe_onboarded: boolean;
  stripe_account_id: string | null;
  updated_at: string;
  gift_count?: number;
  referral_count?: number;
  total_paid_amount?: number | string;
}

export interface AdminCommissionStats {
  total_pending_amount: number | string;
  total_approved_amount: number | string;
  total_paid_amount: number | string;
  total_cancelled_amount?: number | string;
  count_pending: number;
  count_approved: number;
  count_paid: number;
  count_cancelled?: number;
}

export interface AdminAuditStats {
  total_actions: number;
  unique_users: number;
  failed_actions: number;
  by_severity?: Record<string, number>;
}

export interface AdminDailyPoint {
  date: string;
  count: number;
}

export interface AdminPaginated<T> {
  data: T[];
  pagination: PaginationMeta;
}

export type { AdminCommission, AuditLogEntry };
