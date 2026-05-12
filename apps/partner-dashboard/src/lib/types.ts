export type PartnerType = 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';

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
