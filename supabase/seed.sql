-- ============================================
-- HavenKeep Seed Data
-- Run after migrations: supabase db reset (or manually after migration)
-- Source: docs/havenkeep-ux-spec.md v6 (Data Models section)
-- ============================================

-- ============================================
-- 1. CATEGORY DEFAULTS
-- Maps each category to its default room, warranty duration, and icon.
-- Used by Quick-Add to auto-assign room from category.
-- ============================================

INSERT INTO public.category_defaults (category, default_room, warranty_months, icon)
VALUES
  -- Kitchen appliances
  ('refrigerator',     'kitchen',      12,  '🧊'),
  ('dishwasher',       'kitchen',      12,  '🍽️'),
  ('oven_range',       'kitchen',      12,  '🔥'),
  ('microwave',        'kitchen',      12,  '📡'),
  ('garbage_disposal', 'kitchen',      12,  '♻️'),
  ('range_hood',       'kitchen',      12,  '🌬️'),

  -- Laundry
  ('washer',           'laundry',      12,  '👕'),
  ('dryer',            'laundry',      12,  '💨'),

  -- HVAC & Utility
  ('hvac',             'hvac_utility', 60,  '❄️'),
  ('furnace',          'hvac_utility', 60,  '🔥'),
  ('water_heater',     'hvac_utility', 72,  '🚿'),
  ('water_softener',   'hvac_utility', 60,  '💧'),
  ('sump_pump',        'basement',     36,  '🌊'),

  -- Electronics
  ('tv',               'living_room',  12,  '📺'),
  ('computer',         'office',       12,  '💻'),
  ('smart_home',       'living_room',  12,  '🏠'),

  -- Structure (no default room — shown under "General" in UI)
  ('roofing',          NULL,           120, '🏠'),
  ('windows',          NULL,           120, '🪟'),
  ('doors',            NULL,           60,  '🚪'),
  ('flooring',         NULL,           60,  '🟫'),

  -- Systems (no default room)
  ('plumbing',         NULL,           12,  '🔧'),
  ('electrical',       NULL,           12,  '⚡'),

  -- Other
  ('furniture',        NULL,           12,  '🪑'),
  ('other',            NULL,           12,  '📦')
ON CONFLICT (category) DO UPDATE SET
  default_room    = EXCLUDED.default_room,
  warranty_months = EXCLUDED.warranty_months,
  icon            = EXCLUDED.icon;


-- ============================================
-- 2. BRAND SUGGESTIONS
-- Pre-populated brand dropdowns per category.
-- sort_order determines display order in the UI.
-- ============================================

-- Clear existing brand suggestions (idempotent re-seeding)
TRUNCATE public.brand_suggestions;

-- Refrigerator brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('refrigerator', 'Samsung',     1),
  ('refrigerator', 'LG',          2),
  ('refrigerator', 'GE',          3),
  ('refrigerator', 'Whirlpool',   4),
  ('refrigerator', 'Frigidaire',  5),
  ('refrigerator', 'KitchenAid',  6),
  ('refrigerator', 'Bosch',       7),
  ('refrigerator', 'Maytag',      8);

-- Dishwasher brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('dishwasher', 'Bosch',       1),
  ('dishwasher', 'Samsung',     2),
  ('dishwasher', 'LG',          3),
  ('dishwasher', 'GE',          4),
  ('dishwasher', 'Whirlpool',   5),
  ('dishwasher', 'KitchenAid',  6),
  ('dishwasher', 'Maytag',      7),
  ('dishwasher', 'Frigidaire',  8);

-- Oven/Range brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('oven_range', 'GE',          1),
  ('oven_range', 'Samsung',     2),
  ('oven_range', 'LG',          3),
  ('oven_range', 'Whirlpool',   4),
  ('oven_range', 'KitchenAid',  5),
  ('oven_range', 'Frigidaire',  6),
  ('oven_range', 'Bosch',       7),
  ('oven_range', 'Wolf',        8);

-- Microwave brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('microwave', 'GE',          1),
  ('microwave', 'Samsung',     2),
  ('microwave', 'LG',          3),
  ('microwave', 'Whirlpool',   4),
  ('microwave', 'Panasonic',   5),
  ('microwave', 'Frigidaire',  6);

-- Washer brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('washer', 'Samsung',      1),
  ('washer', 'LG',           2),
  ('washer', 'Whirlpool',    3),
  ('washer', 'Maytag',       4),
  ('washer', 'GE',           5),
  ('washer', 'Bosch',        6),
  ('washer', 'Speed Queen',  7);

-- Dryer brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('dryer', 'Samsung',      1),
  ('dryer', 'LG',           2),
  ('dryer', 'Whirlpool',    3),
  ('dryer', 'Maytag',       4),
  ('dryer', 'GE',           5),
  ('dryer', 'Bosch',        6),
  ('dryer', 'Speed Queen',  7);

-- HVAC brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('hvac', 'Carrier',           1),
  ('hvac', 'Trane',             2),
  ('hvac', 'Lennox',            3),
  ('hvac', 'Goodman',           4),
  ('hvac', 'Rheem',             5),
  ('hvac', 'York',              6),
  ('hvac', 'Daikin',            7),
  ('hvac', 'American Standard', 8);

-- Water Heater brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('water_heater', 'Rheem',           1),
  ('water_heater', 'AO Smith',        2),
  ('water_heater', 'Bradford White',  3),
  ('water_heater', 'Rinnai',          4),
  ('water_heater', 'Navien',          5),
  ('water_heater', 'Noritz',          6);

-- Furnace brands (shared with HVAC)
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('furnace', 'Carrier',           1),
  ('furnace', 'Trane',             2),
  ('furnace', 'Lennox',            3),
  ('furnace', 'Goodman',           4),
  ('furnace', 'Rheem',             5),
  ('furnace', 'York',              6),
  ('furnace', 'Bryant',            7);

-- Roofing brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('roofing', 'GAF',            1),
  ('roofing', 'Owens Corning',  2),
  ('roofing', 'CertainTeed',    3),
  ('roofing', 'Tamko',          4),
  ('roofing', 'Atlas',          5);

-- Windows brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('windows', 'Andersen',  1),
  ('windows', 'Pella',     2),
  ('windows', 'Marvin',    3),
  ('windows', 'Milgard',   4),
  ('windows', 'Jeld-Wen',  5);

-- Flooring brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('flooring', 'Shaw',       1),
  ('flooring', 'Mohawk',     2),
  ('flooring', 'Armstrong',  3),
  ('flooring', 'Pergo',      4),
  ('flooring', 'Bruce',      5);

-- TV brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('tv', 'Samsung',  1),
  ('tv', 'LG',       2),
  ('tv', 'Sony',     3),
  ('tv', 'TCL',      4),
  ('tv', 'Hisense',  5),
  ('tv', 'Vizio',    6);

-- Computer brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('computer', 'Apple',    1),
  ('computer', 'Dell',     2),
  ('computer', 'HP',       3),
  ('computer', 'Lenovo',   4),
  ('computer', 'ASUS',     5),
  ('computer', 'Microsoft', 6);

-- Smart Home brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('smart_home', 'Google Nest',  1),
  ('smart_home', 'Amazon Ring',  2),
  ('smart_home', 'Ecobee',      3),
  ('smart_home', 'Philips Hue', 4),
  ('smart_home', 'Lutron',      5);

-- Garbage Disposal brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('garbage_disposal', 'InSinkErator',  1),
  ('garbage_disposal', 'Waste King',    2),
  ('garbage_disposal', 'Moen',          3),
  ('garbage_disposal', 'GE',            4);

-- Range Hood brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('range_hood', 'Broan',       1),
  ('range_hood', 'Zephyr',      2),
  ('range_hood', 'GE',          3),
  ('range_hood', 'KitchenAid',  4),
  ('range_hood', 'Bosch',       5);

-- Water Softener brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('water_softener', 'Culligan',    1),
  ('water_softener', 'GE',          2),
  ('water_softener', 'Whirlpool',   3),
  ('water_softener', 'Fleck',       4),
  ('water_softener', 'Pelican',     5);

-- Sump Pump brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('sump_pump', 'Wayne',          1),
  ('sump_pump', 'Zoeller',        2),
  ('sump_pump', 'Superior Pump',  3),
  ('sump_pump', 'Liberty Pumps',  4);

-- Door brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('doors', 'Therma-Tru',   1),
  ('doors', 'Masonite',     2),
  ('doors', 'Jeld-Wen',     3),
  ('doors', 'Pella',        4),
  ('doors', 'Andersen',     5);

-- Furniture brands
INSERT INTO public.brand_suggestions (category, brand, sort_order) VALUES
  ('furniture', 'IKEA',            1),
  ('furniture', 'Ashley',          2),
  ('furniture', 'Pottery Barn',    3),
  ('furniture', 'West Elm',        4),
  ('furniture', 'Crate & Barrel',  5);


-- ============================================
-- 3. TEST DATA (for local development only)
-- Uses Supabase-generated UUIDs. In production,
-- users are created via Supabase Auth (auth.users).
-- ============================================

-- NOTE: Test user must exist in auth.users first.
-- When running `supabase db reset`, Supabase creates auth schema before seed.
-- We insert a test auth user, then our public.users profile.

-- Test auth user (Supabase local dev uses this pattern)
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  confirmation_token,
  recovery_token,
  raw_app_meta_data,
  raw_user_meta_data
) VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'testuser@havenkeep.dev',
  crypt('password123', gen_salt('bf')),
  NOW(),
  NOW(),
  NOW(),
  '',
  '',
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Alex Johnson"}'
) ON CONFLICT (id) DO NOTHING;

-- Ensure auth identity exists for the test user
INSERT INTO auth.identities (
  id,
  user_id,
  provider_id,
  provider,
  identity_data,
  last_sign_in_at,
  created_at,
  updated_at
) VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'testuser@havenkeep.dev',
  'email',
  '{"sub":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","email":"testuser@havenkeep.dev"}',
  NOW(),
  NOW(),
  NOW()
) ON CONFLICT DO NOTHING;

-- Test user profile
INSERT INTO public.users (id, email, full_name, auth_provider, plan)
VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'testuser@havenkeep.dev',
  'Alex Johnson',
  'email',
  'free'
) ON CONFLICT (id) DO NOTHING;

-- Test notification preferences
INSERT INTO public.notification_preferences (
  user_id, reminders_enabled, first_reminder_days, reminder_time,
  warranty_offers_enabled, tips_enabled, push_enabled, email_enabled
) VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  TRUE, 30, '09:00', TRUE, TRUE, TRUE, FALSE
) ON CONFLICT (user_id) DO NOTHING;

-- Test home
INSERT INTO public.homes (id, user_id, name, address, city, state, zip, home_type, move_in_date)
VALUES (
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'My House',
  '123 Oak Street',
  'Austin',
  'TX',
  '78701',
  'house',
  '2024-06-15'
) ON CONFLICT (id) DO NOTHING;

-- Test items (variety of categories, warranty statuses, and add methods)

-- 1. Samsung Refrigerator — active warranty (purchased 3 months ago)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'c3d4e5f6-a7b8-9012-cdef-123456789012',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'French Door Refrigerator',
  'Samsung',
  'RF28T5001SR',
  'refrigerator',
  'kitchen',
  CURRENT_DATE - INTERVAL '3 months',
  'Home Depot',
  1899.99,
  12,
  'manufacturer',
  'quick_add'
) ON CONFLICT (id) DO NOTHING;

-- 2. Bosch Dishwasher — expiring soon (purchased 10 months ago, 12mo warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'd4e5f6a7-b8c9-0123-defa-234567890123',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Silence Plus Dishwasher',
  'Bosch',
  'SHPM88Z75N',
  'dishwasher',
  'kitchen',
  CURRENT_DATE - INTERVAL '10 months',
  'Lowes',
  1249.00,
  12,
  'manufacturer',
  'receipt_scan'
) ON CONFLICT (id) DO NOTHING;

-- 3. Carrier HVAC — active (purchased 2 years ago, 5-year warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'e5f6a7b8-c9d0-1234-efab-345678901234',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Infinity 24 Heat Pump',
  'Carrier',
  '24VNA024A003',
  'hvac',
  'hvac_utility',
  CURRENT_DATE - INTERVAL '2 years',
  'ABC Heating & Cooling',
  8500.00,
  60,
  'manufacturer',
  'manual'
) ON CONFLICT (id) DO NOTHING;

-- 4. Rheem Water Heater — active (purchased 1 year ago, 6-year warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'f6a7b8c9-d0e1-2345-fabc-456789012345',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Performance Plus 50 Gal',
  'Rheem',
  'XE50T10HD50U1',
  'water_heater',
  'hvac_utility',
  CURRENT_DATE - INTERVAL '1 year',
  'Home Depot',
  849.00,
  72,
  'manufacturer',
  'quick_add'
) ON CONFLICT (id) DO NOTHING;

-- 5. Samsung Washer — expired (purchased 14 months ago, 12mo warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'a7b8c9d0-e1f2-3456-abcd-567890123456',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Smart Front Load Washer',
  'Samsung',
  'WF45R6100AW',
  'washer',
  'laundry',
  CURRENT_DATE - INTERVAL '14 months',
  'Best Buy',
  799.99,
  12,
  'manufacturer',
  'quick_add'
) ON CONFLICT (id) DO NOTHING;

-- 6. LG Dryer — expired (purchased 14 months ago, 12mo warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'b8c9d0e1-f2a3-4567-bcde-678901234567',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Smart Electric Dryer',
  'LG',
  'DLEX3900W',
  'dryer',
  'laundry',
  CURRENT_DATE - INTERVAL '14 months',
  'Best Buy',
  899.99,
  12,
  'manufacturer',
  'quick_add'
) ON CONFLICT (id) DO NOTHING;

-- 7. GAF Roofing — active (installed 3 years ago, 10-year warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, category,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'c9d0e1f2-a3b4-5678-cdef-789012345678',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Timberline HDZ Shingles',
  'GAF',
  'roofing',
  CURRENT_DATE - INTERVAL '3 years',
  'Local Roofing Co',
  12500.00,
  120,
  'manufacturer',
  'manual'
) ON CONFLICT (id) DO NOTHING;

-- 8. GE Microwave — expiring (purchased 11 months ago, 12mo warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via
) VALUES (
  'd0e1f2a3-b4c5-6789-defa-890123456789',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Profile Over-the-Range Microwave',
  'GE',
  'PVM9005SJ',
  'microwave',
  'kitchen',
  CURRENT_DATE - INTERVAL '11 months',
  'Lowes',
  549.00,
  12,
  'manufacturer',
  'barcode_scan'
) ON CONFLICT (id) DO NOTHING;

-- 9. Samsung TV — active (purchased 6 months ago, extended warranty)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, warranty_provider, added_via
) VALUES (
  'e1f2a3b4-c5d6-7890-efab-901234567890',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  '65" Neo QLED 4K TV',
  'Samsung',
  'QN65QN90C',
  'tv',
  'living_room',
  CURRENT_DATE - INTERVAL '6 months',
  'Best Buy',
  1799.99,
  36,
  'extended',
  'Geek Squad Protection',
  'receipt_scan'
) ON CONFLICT (id) DO NOTHING;

-- 10. InSinkErator Garbage Disposal — active (purchased 1 month ago)
INSERT INTO public.items (
  id, home_id, user_id, name, brand, model_number, category, room,
  purchase_date, store, price, warranty_months, warranty_type, added_via, notes
) VALUES (
  'f2a3b4c5-d6e7-8901-fabc-012345678901',
  'b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Evolution Excel 1HP',
  'InSinkErator',
  '?"?"?"?"',
  'garbage_disposal',
  'kitchen',
  CURRENT_DATE - INTERVAL '1 month',
  'Amazon',
  329.95,
  84,
  'manufacturer',
  'quick_add',
  'Installed by plumber. 7-year in-home warranty from InSinkErator.'
) ON CONFLICT (id) DO NOTHING;

-- Test notifications

-- Expiring warranty notification (for the Bosch dishwasher)
INSERT INTO public.notifications (
  id, user_id, item_id, type, title, body, is_read,
  action_type, action_data, scheduled_at
) VALUES (
  'a0b1c2d3-e4f5-6789-0abc-def012345678',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'd4e5f6a7-b8c9-0123-defa-234567890123',
  'warranty_expiring',
  'Warranty Expiring Soon',
  'Your Bosch Silence Plus Dishwasher warranty expires in 60 days. Consider extending your protection.',
  FALSE,
  'get_protection',
  '{"item_id": "d4e5f6a7-b8c9-0123-defa-234567890123"}',
  NOW() + INTERVAL '1 day'
) ON CONFLICT (id) DO NOTHING;

-- Expired warranty notification (for the Samsung washer)
INSERT INTO public.notifications (
  id, user_id, item_id, type, title, body, is_read,
  action_type, action_data, scheduled_at, sent_at
) VALUES (
  'b1c2d3e4-f5a6-7890-1bcd-ef0123456789',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'a7b8c9d0-e1f2-3456-abcd-567890123456',
  'warranty_expired',
  'Warranty Expired',
  'Your Samsung Smart Front Load Washer warranty has expired. Find affordable repair coverage.',
  TRUE,
  'find_repair',
  '{"item_id": "a7b8c9d0-e1f2-3456-abcd-567890123456"}',
  CURRENT_DATE - INTERVAL '2 months',
  CURRENT_DATE - INTERVAL '2 months'
) ON CONFLICT (id) DO NOTHING;

-- Tip notification
INSERT INTO public.notifications (
  id, user_id, item_id, type, title, body, is_read,
  scheduled_at, sent_at
) VALUES (
  'c2d3e4f5-a6b7-8901-2cde-f01234567890',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  NULL,
  'tip',
  'Pro Tip: Receipt Photos',
  'Snap a photo of your receipts right after purchase. The ink fades over time!',
  FALSE,
  CURRENT_DATE - INTERVAL '1 day',
  CURRENT_DATE - INTERVAL '1 day'
) ON CONFLICT (id) DO NOTHING;


-- ============================================
-- Test referral partner (for testing partner flow)
-- ============================================

INSERT INTO public.referral_partners (
  id, email, full_name, company_name, phone,
  partner_type, referral_code, is_active
) VALUES (
  'p1a2b3c4-d5e6-7890-pqrs-tuvwxyz12345',
  'sarah.realtor@example.com',
  'Sarah Mitchell',
  'Austin Prime Realty',
  '512-555-0123',
  'realtor',
  'SARAH-APR-2024',
  TRUE
) ON CONFLICT (id) DO NOTHING;

-- Link test user as referred by the test partner
UPDATE public.users
SET referred_by = 'p1a2b3c4-d5e6-7890-pqrs-tuvwxyz12345'
WHERE id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
  AND referred_by IS NULL;

-- Create the referral record
INSERT INTO public.referrals (partner_id, user_id, source)
VALUES (
  'p1a2b3c4-d5e6-7890-pqrs-tuvwxyz12345',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'realtor'
) ON CONFLICT (partner_id, user_id) DO NOTHING;


-- ============================================
-- DONE
-- ============================================
-- Summary of test data:
--   1 test user (testuser@havenkeep.dev / password123)
--   1 home (123 Oak Street, Austin TX)
--   10 items across 9 categories:
--     - 5 active warranties (fridge, HVAC, water heater, roofing, TV, disposal)
--     - 2 expiring soon (dishwasher, microwave)
--     - 2 expired (washer, dryer)
--     - Mix of added_via methods: quick_add, receipt_scan, manual, barcode_scan
--     - Mix of warranty types: manufacturer, extended
--   3 notifications (expiring, expired, tip)
--   1 referral partner + referral record
--   24 category defaults
--   130+ brand suggestions across 21 categories
