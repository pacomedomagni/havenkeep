export type PartnerType = 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
export type ReferralStatus = 'pending' | 'converted' | 'expired';
export type CommissionStatus = 'pending' | 'approved' | 'paid' | 'cancelled';

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
