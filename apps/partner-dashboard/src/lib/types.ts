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
