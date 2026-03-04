-- Add 'pending' to warranty_purchase_status enum if not already present
ALTER TYPE warranty_purchase_status ADD VALUE IF NOT EXISTS 'pending';
