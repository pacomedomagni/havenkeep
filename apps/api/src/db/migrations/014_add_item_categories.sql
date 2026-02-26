-- Migration 014: Add 20 new item categories to PostgreSQL enum
-- These categories were added to validators and Dart enums but missing from DB schema.

ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'air_purifier';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'vacuum';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'ceiling_fan';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'smoke_detector';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'security_system';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'garage_door_opener';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'power_tools';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'lawn_mower';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'pool_equipment';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'grill';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'coffee_maker';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'home_theater';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'printer';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'networking';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'camera';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'lighting';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'dehumidifier';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'freezer';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'wine_cooler';
ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'trash_compactor';

DO $$
BEGIN
  RAISE NOTICE 'Migration 014: Added 20 new item categories to item_category enum';
END $$;
