import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// Maps each [ItemCategory] to a representative emoji and provides a
/// convenience widget for rendering it at a given size.
///
/// This class is not meant to be instantiated.
class CategoryIcon {
  CategoryIcon._();

  /// Returns the emoji string associated with the given [category].
  static String get(ItemCategory category) => switch (category) {
        ItemCategory.refrigerator => '\u{1F9CA}', // 🧊
        ItemCategory.dishwasher => '\u{1F37D}\u{FE0F}', // 🍽️
        ItemCategory.washer => '\u{1F455}', // 👕
        ItemCategory.dryer => '\u{1F4A8}', // 💨
        ItemCategory.oven_range => '\u{1F525}', // 🔥
        ItemCategory.microwave => '\u{1F4E1}', // 📡
        ItemCategory.garbage_disposal => '\u{267B}\u{FE0F}', // ♻️
        ItemCategory.range_hood => '\u{1F32C}\u{FE0F}', // 🌬️
        ItemCategory.hvac => '\u{2744}\u{FE0F}', // ❄️
        ItemCategory.water_heater => '\u{1F6BF}', // 🚿
        ItemCategory.furnace => '\u{1F525}', // 🔥
        ItemCategory.water_softener => '\u{1F4A7}', // 💧
        ItemCategory.sump_pump => '\u{1F30A}', // 🌊
        ItemCategory.tv => '\u{1F4FA}', // 📺
        ItemCategory.computer => '\u{1F4BB}', // 💻
        ItemCategory.smart_home => '\u{1F3E0}', // 🏠
        ItemCategory.roofing => '\u{1F3E0}', // 🏠
        ItemCategory.windows => '\u{1FA9F}', // 🪟
        ItemCategory.doors => '\u{1F6AA}', // 🚪
        ItemCategory.flooring => '\u{1FAB5}', // 🪵
        ItemCategory.plumbing => '\u{1F527}', // 🔧
        ItemCategory.electrical => '\u{26A1}', // ⚡
        ItemCategory.furniture => '\u{1FA91}', // 🪑
        ItemCategory.air_purifier => '\u{1F4A8}', // 💨
        ItemCategory.vacuum => '\u{1F9F9}', // 🧹
        ItemCategory.ceiling_fan => '\u{1F32C}\u{FE0F}', // 🌬️
        ItemCategory.smoke_detector => '\u{1F6A8}', // 🚨
        ItemCategory.security_system => '\u{1F512}', // 🔒
        ItemCategory.garage_door_opener => '\u{1F3DA}\u{FE0F}', // 🏚️
        ItemCategory.power_tools => '\u{1F529}', // 🔩
        ItemCategory.lawn_mower => '\u{1F33F}', // 🌿
        ItemCategory.pool_equipment => '\u{1F3CA}', // 🏊
        ItemCategory.grill => '\u{1F356}', // 🍖
        ItemCategory.coffee_maker => '\u{2615}', // ☕
        ItemCategory.home_theater => '\u{1F3AC}', // 🎬
        ItemCategory.printer => '\u{1F5A8}\u{FE0F}', // 🖨️
        ItemCategory.networking => '\u{1F310}', // 🌐
        ItemCategory.camera => '\u{1F4F7}', // 📷
        ItemCategory.lighting => '\u{1F4A1}', // 💡
        ItemCategory.dehumidifier => '\u{1F4A7}', // 💧
        ItemCategory.freezer => '\u{1F9CA}', // 🧊
        ItemCategory.wine_cooler => '\u{1F377}', // 🍷
        ItemCategory.trash_compactor => '\u{1F5D1}\u{FE0F}', // 🗑️
        ItemCategory.other => '\u{1F4E6}', // 📦
      };

  /// Returns a [Text] widget displaying the category emoji at the given
  /// [size] (defaults to 24).
  static Widget widget(ItemCategory category, {double size = 24}) {
    return Semantics(
      label: category.displayLabel,
      excludeSemantics: true,
      child: Text(
        get(category),
        style: TextStyle(fontSize: size),
      ),
    );
  }
}
