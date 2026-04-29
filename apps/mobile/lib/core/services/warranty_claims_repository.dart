import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles warranty claims CRUD via the Express API.
class WarrantyClaimsRepository {
  final ApiClient _client;

  WarrantyClaimsRepository(this._client);

  /// Get the first page of claims for the current user.
  ///
  /// S2-T: the API returns a keyset cursor in `meta.pagination.next_cursor`
  /// (audit Ch02-F008). The list screen doesn't expose infinite scroll
  /// today, so a single 100-row page is enough — but [getClaimsPage]
  /// surfaces the cursor and `hasMore` flag so a future paginated UI
  /// doesn't have to re-thread the contract.
  Future<List<WarrantyClaim>> getClaims({String? itemId, String? homeId}) async {
    final page = await getClaimsPage(itemId: itemId, homeId: homeId);
    return page.items;
  }

  /// Fetch one page of claims, returning the keyset cursor for the next
  /// page when one exists. Pass [cursor] to fetch subsequent pages.
  Future<ClaimsPage> getClaimsPage({
    String? itemId,
    String? homeId,
    String? cursor,
    int limit = 100,
  }) async {
    try {
      final params = <String, String>{
        'limit': limit.toString(),
      };
      if (itemId != null) params['item_id'] = itemId;
      if (homeId != null) params['home_id'] = homeId;
      if (cursor != null) {
        params['cursor'] = cursor;
      } else {
        params['page'] = '1';
      }

      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'warranty-claims'],
        queryParams: params,
      );
      final claims = (data['data'] as List)
          .map((json) => WarrantyClaim.fromJson(json as Map<String, dynamic>))
          .toList(growable: false);

      final pagination =
          (data['meta'] as Map<String, dynamic>?)?['pagination']
              as Map<String, dynamic>?;
      final nextCursor = pagination?['next_cursor'] as String?;
      final hasMore = pagination?['has_more'] as bool? ?? (nextCursor != null);

      return ClaimsPage(
        items: claims,
        nextCursor: nextCursor,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getClaims failed: $e');
      rethrow;
    }
  }

  /// Get a single claim by ID.
  Future<WarrantyClaim> getClaimById(String id) async {
    try {
      final data = await _client.get(
        pathSegments: ['api', 'v1', 'warranty-claims', id],
      );
      return WarrantyClaim.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getClaimById failed: $e');
      rethrow;
    }
  }

  /// Create a new warranty claim.
  Future<WarrantyClaim> createClaim(WarrantyClaim claim) async {
    try {
      final data = await _client.post(
        pathSegments: const ['api', 'v1', 'warranty-claims'],
        body: claim.toCreateJson(),
      );
      return WarrantyClaim.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] createClaim failed: $e');
      rethrow;
    }
  }

  /// Update an existing claim.
  Future<WarrantyClaim> updateClaim(String id, Map<String, dynamic> updates) async {
    try {
      final data = await _client.put(
        pathSegments: ['api', 'v1', 'warranty-claims', id],
        body: updates,
      );
      return WarrantyClaim.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] updateClaim failed: $e');
      rethrow;
    }
  }

  /// Delete a claim.
  Future<void> deleteClaim(String id) async {
    try {
      await _client.delete(
        pathSegments: ['api', 'v1', 'warranty-claims', id],
      );
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] deleteClaim failed: $e');
      rethrow;
    }
  }

  /// Get total savings from warranty claims.
  Future<Map<String, dynamic>> getSavings() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'warranty-claims', 'savings'],
      );
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getSavings failed: $e');
      rethrow;
    }
  }

  /// Get the public savings feed (anonymized community social proof).
  Future<List<Map<String, dynamic>>> getSavingsFeed({int limit = 10}) async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'warranty-claims', 'feed'],
        queryParams: {'limit': '$limit'},
      );
      return List<Map<String, dynamic>>.from(data['data'] as List);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getSavingsFeed failed: $e');
      rethrow;
    }
  }
}

/// One keyset-paginated page of warranty claims plus the cursor needed to
/// fetch the next page (S2-T).
class ClaimsPage {
  final List<WarrantyClaim> items;
  final String? nextCursor;
  final bool hasMore;

  const ClaimsPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}
