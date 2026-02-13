-- Notifications enum extensions + preferences table

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'item_added';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'warranty_extended';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'claim_update';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'gift_activated';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'promotional';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'tip';

CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  reminders_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  first_reminder_days INTEGER NOT NULL DEFAULT 30,
  reminder_time VARCHAR(5) NOT NULL DEFAULT '09:00',
  warranty_offers_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  tips_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  email_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'update_notification_preferences_updated_at'
  ) THEN
    CREATE TRIGGER update_notification_preferences_updated_at
      BEFORE UPDATE ON notification_preferences
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- Partner type extension + service areas
ALTER TYPE partner_type_enum ADD VALUE IF NOT EXISTS 'property_manager';

ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS service_areas TEXT[] DEFAULT '{}'::text[];
