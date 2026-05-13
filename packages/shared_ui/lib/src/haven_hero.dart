/// Canonical hero-tag generators. Hero animations break silently when two
/// widgets on the same screen share a tag (and silently when source and
/// destination *don't* share one) — using these helpers makes the contract
/// explicit and keeps the four hero flows in HavenKeep namespaced apart.
///
/// Usage:
/// ```dart
/// // In the items list row:
/// Hero(tag: HavenHeroTag.item(item.id), child: ...)
/// // In the item detail screen:
/// Hero(tag: HavenHeroTag.item(itemId), child: ...)
/// ```
class HavenHeroTag {
  HavenHeroTag._();

  /// Item card → item detail (thumbnail / title morph).
  static String item(String id) => 'item:$id';

  /// Claim row → claim detail / item detail (status badge morph).
  static String claim(String id) => 'claim:$id';

  /// Gift card → gift detail (premium badge morph).
  static String gift(String id) => 'gift:$id';

  /// Dashboard stat ring → drilldown screen (number morph).
  static String stat(String name) => 'stat:$name';
}
