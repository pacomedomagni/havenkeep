export type PartnerType = 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
export type ReferralStatus = 'pending' | 'converted' | 'expired';
export type CommissionStatus = 'pending' | 'paid' | 'cancelled';

export interface Partner {
  id: string;
  userId: string;
  companyName: string;
  partnerType: PartnerType;
  licenseNumber?: string;
  serviceAreas: string[];
  isApproved: boolean;
  referralCode: string;
  createdAt: string;
}

export interface Referral {
  id: string;
  partnerId: string;
  code: string;
  referredEmail?: string;
  referredUserId?: string;
  status: ReferralStatus;
  convertedAt?: string;
  createdAt: string;
}

export interface Commission {
  id: string;
  partnerId: string;
  referralId: string;
  amount: number;
  status: CommissionStatus;
  paidAt?: string;
  createdAt: string;
}

export interface AdminPartner {
  id: string
  user_id: string
  email: string
  full_name: string
  company_name: string
  partner_type: string
  license_number?: string
  phone?: string
  service_areas: string[]
  brand_color?: string
  logo_url?: string
  stripe_connect_id?: string
  stripe_onboarded: boolean
  referral_code: string
  is_active: boolean
  total_commissions: number
  total_gifts: number
  total_referrals: number
  created_at: string
  updated_at: string
}

export interface AdminCommission {
  id: string
  partner_id: string
  referral_id: string
  amount: number
  status: 'pending' | 'approved' | 'paid' | 'cancelled'
  partner_company_name: string
  partner_email: string
  referral_code?: string
  created_at: string
}

export interface CommissionStats {
  total_pending_amount: number
  total_approved_amount: number
  total_paid_amount: number
  total_cancelled_amount: number
  count_pending: number
  count_approved: number
  count_paid: number
  count_cancelled: number
}

export interface AuditLogEntry {
  id: string
  user_id?: string
  user_email?: string
  action: string
  severity: 'info' | 'warning' | 'error' | 'critical'
  resource_type?: string
  resource_id?: string
  description?: string
  metadata?: Record<string, any>
  ip_address?: string
  user_agent?: string
  endpoint?: string
  http_method?: string
  success: boolean
  created_at: string
}

export interface AuditStats {
  total_logs: number
  security_events_24h: number
  warning_plus_events: number
}

export interface HealthCheck {
  status: 'ok' | 'degraded' | 'error'
  timestamp: string
  uptime: number
  environment: string
  checks: {
    database: { status: string; message?: string }
    redis: { status: string; message?: string }
    minio: { status: string; message?: string }
  }
}

export interface PaginationInfo {
  page: number
  limit: number
  total: number
  totalPages: number
}
