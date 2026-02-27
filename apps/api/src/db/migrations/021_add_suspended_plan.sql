-- Migration 021: Add 'suspended' value to user_plan enum
-- Required for admin user suspension feature (admin.ts PUT /users/:id/suspend)

ALTER TYPE user_plan ADD VALUE IF NOT EXISTS 'suspended';
