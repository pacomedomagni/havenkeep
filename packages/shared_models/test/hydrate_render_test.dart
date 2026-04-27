// Phase 8 hydrate-render coverage.
//
// Each test deserializes a representative API payload, re-serializes it,
// and asserts the round trip is symmetric. Catches DateTime drift, enum
// silent-default coercion, and toJson/fromJson key drift.

import 'package:test/test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('User round-trip is symmetric', () {
    final json = {
      'id': '11111111-1111-1111-1111-111111111111',
      'email': 'kouakou@havenkeep.com',
      'full_name': 'Kouakou Domagni',
      'avatar_url': null,
      'auth_provider': 'google',
      'plan': 'premium',
      'plan_expires_at': '2026-12-31T23:59:59.000Z',
      'referred_by': null,
      'referral_code': 'KD-7',
      'email_verified': true,
      'apple_user_id': null,
      'is_admin': false,
      'is_partner': true,
      'deleted_at': null,
      'deletion_scheduled_for': null,
      'created_at': '2026-01-01T12:00:00.000Z',
      'updated_at': '2026-04-25T10:00:00.000Z',
    };
    final user = User.fromJson(json);
    expect(User.fromJson(user.toJson()).toJson(), user.toJson());
    expect(user.authProvider, AuthProvider.google);
    expect(user.isPartner, isTrue);
  });

  test('Home round-trip strips create-only fields via toCreateJson', () {
    final json = {
      'id': '22222222-2222-2222-2222-222222222222',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'name': 'Cocody House',
      'address': '12 Rue des Jardins',
      'city': 'Abidjan',
      'state': 'Lagunes',
      'zip': '00225',
      'home_type': 'house',
      'move_in_date': '2024-03-15',
      'created_at': '2024-03-15T08:00:00.000Z',
      'updated_at': '2024-03-15T08:00:00.000Z',
    };
    final home = Home.fromJson(json);
    expect(Home.fromJson(home.toJson()).toJson(), home.toJson());

    final create = home.toCreateJson();
    expect(create.containsKey('id'), isFalse);
    expect(create.containsKey('created_at'), isFalse);
    expect(create.containsKey('updated_at'), isFalse);
  });

  test('Item round-trip survives DECIMAL price + warranty_end_date', () {
    final json = {
      'id': '33333333-3333-3333-3333-333333333333',
      'home_id': '22222222-2222-2222-2222-222222222222',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'name': 'Bosch Series 6 Dishwasher',
      'brand': 'Bosch',
      'model_number': 'SHPM78W55N',
      'serial_number': 'BSH-2026-00001',
      'category': 'dishwasher',
      'room': 'kitchen',
      'product_image_url': null,
      'barcode': null,
      'purchase_date': '2026-01-15',
      'store': 'Best Buy',
      'price': 1199.99,
      'warranty_months': 24,
      'warranty_end_date': '2028-01-15',
      'warranty_type': 'manufacturer',
      'warranty_provider': null,
      'installation_date': null,
      'last_maintenance_date': null,
      'next_maintenance_due': null,
      'notes': null,
      'is_archived': false,
      'added_via': 'manual',
      'archived_at': null,
      'created_at': '2026-01-15T10:00:00.000Z',
      'updated_at': '2026-01-15T10:00:00.000Z',
    };
    final item = Item.fromJson(json);
    expect(Item.fromJson(item.toJson()).toJson(), item.toJson());

    final insert = item.toInsertJson();
    expect(insert.containsKey('warranty_end_date'), isFalse);
    expect(insert.containsKey('id'), isFalse);
    expect(insert.containsKey('archived_at'), isFalse);
  });

  test('Document round-trip survives nullable item_id (mig 043)', () {
    final json = {
      'id': '44444444-4444-4444-4444-444444444444',
      'item_id': null,
      'user_id': '11111111-1111-1111-1111-111111111111',
      'type': 'receipt',
      'file_url': 'https://cdn.havenkeep.com/receipts/abc.webp',
      'file_name': 'abc.webp',
      'file_size': 4294967296, // > INT32 max — proves BIGINT carries
      'mime_type': 'image/webp',
      'thumbnail_url': null,
      'created_at': '2026-04-25T09:00:00.000Z',
      'updated_at': '2026-04-25T09:00:00.000Z',
    };
    final doc = Document.fromJson(json);
    expect(doc.itemId, isNull);
    expect(doc.fileSize, 4294967296);
    expect(Document.fromJson(doc.toJson()).toJson(), doc.toJson());
  });

  test('WarrantyClaim round-trip preserves snake_case in_review status', () {
    final json = {
      'id': '55555555-5555-5555-5555-555555555555',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'item_id': '33333333-3333-3333-3333-333333333333',
      'claim_date': '2026-04-01T00:00:00.000Z',
      'issue_description': 'Door seal failed',
      'repair_description': 'Replaced door gasket',
      'repair_cost': 145.0,
      'amount_saved': 800.0,
      'out_of_pocket': 0.0,
      'status': 'in_review',
      'filed_with': 'Bosch',
      'claim_number': 'CLM-99',
      'notes': null,
      'created_at': '2026-04-01T09:00:00.000Z',
      'updated_at': '2026-04-01T09:00:00.000Z',
    };
    final claim = WarrantyClaim.fromJson(json);
    expect(claim.status, ClaimStatus.inReview);
    expect(claim.toJson()['status'], 'in_review');
  });

  test('WarrantyPurchase round-trip requires expires_at + purchase_date', () {
    final json = {
      'id': '66666666-6666-6666-6666-666666666666',
      'item_id': '33333333-3333-3333-3333-333333333333',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'provider': 'Asurion',
      'plan_name': 'Major Appliance — 3yr',
      'external_policy_id': null,
      'duration_months': 36,
      'starts_at': '2026-01-15T00:00:00.000Z',
      'expires_at': '2029-01-15T00:00:00.000Z',
      'price': 199.0,
      'deductible': 0.0,
      'claim_limit': null,
      'commission_amount': null,
      'commission_rate': null,
      'purchase_date': '2026-01-15T10:00:00.000Z',
      'stripe_payment_intent_id': 'pi_test',
      'status': 'active',
      'cancelled_at': null,
      'cancellation_reason': null,
      'created_at': '2026-01-15T10:00:00.000Z',
      'updated_at': '2026-01-15T10:00:00.000Z',
    };
    final wp = WarrantyPurchase.fromJson(json);
    expect(wp.status, WarrantyPurchaseStatus.active);
    expect(WarrantyPurchase.fromJson(wp.toJson()).toJson(), wp.toJson());
  });

  test('AppNotification round-trip carries gift_id + delivered_at', () {
    final json = {
      'id': '77777777-7777-7777-7777-777777777777',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'template_id': '88888888-8888-8888-8888-888888888888',
      'item_id': null,
      'gift_id': '99999999-9999-9999-9999-999999999999',
      'type': 'gift_received',
      'title': 'You received a gift!',
      'body': 'Aya gave you 6 months of Premium.',
      'data': {'partner_name': 'Aya'},
      'sent_at': '2026-04-25T08:00:00.000Z',
      'delivered_at': '2026-04-25T08:00:01.000Z',
      'opened_at': null,
      'action_taken': null,
      'action_taken_at': null,
      'platform': 'mobile',
      'fcm_message_id': 'fcm-abc',
      'created_at': '2026-04-25T08:00:00.000Z',
    };
    final n = AppNotification.fromJson(json);
    expect(n.giftId, '99999999-9999-9999-9999-999999999999');
    expect(n.deliveredAt, isNotNull);
    expect(n.platform, 'mobile');
    expect(AppNotification.fromJson(n.toJson()).toJson(), n.toJson());
  });

  test('NotificationPreferences round-trip carries timestamps', () {
    final json = {
      'user_id': '11111111-1111-1111-1111-111111111111',
      'reminders_enabled': true,
      'first_reminder_days': 30,
      'reminder_time': '09:00',
      'warranty_offers_enabled': true,
      'tips_enabled': true,
      'push_enabled': true,
      'email_enabled': false,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-04-25T08:00:00.000Z',
    };
    final p = NotificationPreferences.fromJson(json);
    expect(p.firstReminderDays, 30);
    expect(NotificationPreferences.fromJson(p.toJson()).toJson(), p.toJson());
  });

  test('Partner round-trip carries every D050..D061 field', () {
    final json = {
      'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'partner_type': 'realtor',
      'company_name': 'Cocody Realty',
      'phone': '+2250100000000',
      'website': 'https://cocodyrealty.com',
      'brand_color': '#1F4FB6',
      'logo_url': 'https://cdn.havenkeep.com/logos/cocody.png',
      'subscription_tier': 'premium',
      'default_message': 'Welcome to your new home!',
      'default_premium_months': 12,
      'stripe_onboarded': true,
      'is_active': true,
      'is_verified': true,
      'service_areas': ['Cocody', 'Marcory'],
      'license_number': 'CI-RE-12345',
      'created_at': '2025-12-01T00:00:00.000Z',
      'updated_at': '2026-04-25T00:00:00.000Z',
    };
    final p = Partner.fromJson(json);
    expect(p.subscriptionTier, PartnerSubscriptionTier.premium);
    expect(p.serviceAreas, hasLength(2));
    expect(Partner.fromJson(p.toJson()).toJson(), p.toJson());
  });

  test('PartnerCommission round-trip preserves enum reference_type', () {
    final json = {
      'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'partner_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'type': 'gift',
      'amount': 14.85,
      'commission_rate': 0.15,
      'status': 'paid',
      'reference_id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'reference_type': 'partner_gift',
      'payout_method': 'stripe_connect',
      'stripe_transfer_id': 'tr_test',
      'created_at': '2026-04-01T00:00:00.000Z',
      'updated_at': '2026-04-01T00:00:00.000Z',
    };
    final c = PartnerCommission.fromJson(json);
    expect(c.referenceType, PartnerCommissionReferenceType.partner_gift);
    expect(c.payoutMethod, PartnerCommissionPayoutMethod.stripe_connect);
    expect(PartnerCommission.fromJson(c.toJson()).toJson(), c.toJson());
  });

  test('EmailScan round-trip carries integer counts', () {
    final json = {
      'id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
      'user_id': '11111111-1111-1111-1111-111111111111',
      'provider': 'gmail',
      'provider_email': 'kouakou@gmail.com',
      'scan_date': '2026-04-20T00:00:00.000Z',
      'date_range_start': '2026-01-01',
      'date_range_end': '2026-04-20',
      'emails_scanned': 1245,
      'receipts_found': 73,
      'items_imported': 41,
      'status': 'completed',
      'error_message': null,
      'completed_at': '2026-04-20T00:05:00.000Z',
      'created_at': '2026-04-20T00:00:00.000Z',
    };
    final scan = EmailScan.fromJson(json);
    expect(scan.emailsScanned, 1245);
    expect(EmailScan.fromJson(scan.toJson()).toJson(), scan.toJson());
  });

  test('ContactSubmission round-trip', () {
    final json = {
      'id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
      'name': 'Aya Konan',
      'email': 'aya@example.com',
      'subject': 'Technical Support',
      'message': 'My HVAC reminder did not fire after the last update.',
      'ip_address': '203.0.113.4',
      'created_at': '2026-04-25T11:00:00.000Z',
    };
    final c = ContactSubmission.fromJson(json);
    expect(ContactSubmission.fromJson(c.toJson()).toJson(), c.toJson());
  });

  test('Tip round-trip carries trigger_condition', () {
    final json = {
      'id': 42,
      'category': 'maintenance',
      'trigger_condition': 'no_maintenance',
      'content': 'Schedule your first maintenance task to keep your items in top shape.',
      'is_active': true,
      'created_at': '2026-01-01T00:00:00.000Z',
    };
    final tip = Tip.fromJson(json);
    expect(tip.triggerCondition, 'no_maintenance');
    expect(Tip.fromJson(tip.toJson()).toJson(), tip.toJson());
  });

  test('MaintenanceSchedule round-trip uses ItemCategory + difficulty enums', () {
    final json = {
      'id': 'ffffffff-ffff-ffff-ffff-ffffffffffff',
      'category': 'hvac',
      'task_name': 'Replace HVAC Filter',
      'description': 'Swap the standard 16x25x1 filter.',
      'frequency_months': 3,
      'priority': 8,
      'frequency_label': 'Quarterly',
      'estimated_duration_minutes': 5,
      'difficulty': 'easy',
      'prevents_cost': 250.0,
      'how_to_url': null,
      'video_url': null,
      'tools_needed': null,
      'is_required_for_warranty': false,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-04-25T00:00:00.000Z',
    };
    final s = MaintenanceSchedule.fromJson(json);
    expect(s.category, ItemCategory.hvac);
    expect(s.difficulty, MaintenanceDifficulty.easy);
    expect(MaintenanceSchedule.fromJson(s.toJson()).toJson(), s.toJson());
  });

  test('ClaimStatus._byName surfaces unknown as filed without throwing', () {
    expect(ClaimStatus.fromJson('made_up_status'), ClaimStatus.filed);
  });

  // S3-12.2 / S1-A: every server-issued claim status round-trips verbatim.
  test('ClaimStatus round-trips every server-issued value', () {
    final wireValues = [
      'filed',
      'in_review',
      'approved',
      'denied',
      'settled',
      'closed',
    ];
    for (final wire in wireValues) {
      final parsed = ClaimStatus.fromJson(wire);
      expect(parsed.toJson(), wire,
          reason: 'ClaimStatus.$wire must round-trip without coercion');
    }
  });

  // S3-12.6 / S1-F: Partner.status hydrates from `status` and falls through
  // unknown values to pending without throwing.
  test('Partner round-trip preserves status field', () {
    final json = {
      'id': '11111111-1111-1111-1111-111111111111',
      'user_id': '22222222-2222-2222-2222-222222222222',
      'partner_type': 'realtor',
      'company_name': 'Acme Realty',
      'subscription_tier': 'basic',
      'default_premium_months': 6,
      'stripe_onboarded': true,
      'status': 'pending',
      'is_active': false,
      'is_verified': false,
      'service_areas': <String>[],
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-04-25T00:00:00.000Z',
    };
    final partner = Partner.fromJson(json);
    expect(partner.status, PartnerStatus.pending);
    expect(partner.toJson()['status'], 'pending');
    final round = Partner.fromJson(partner.toJson());
    expect(round.status, partner.status);
  });

  test('PartnerStatus.fromJson coerces unknown values to pending', () {
    expect(PartnerStatus.fromJson('made_up'), PartnerStatus.pending);
  });
}
